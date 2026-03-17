[English](DESIGN.md) | 日本語

# unicodegrapheme 設計

## 目的

MoonBit で Unicode grapheme cluster 単位の文字列操作を提供する。

## アーキテクチャ

### GraphemeView

元の String を保持し、grapheme cluster の境界オフセット配列を持つ。
各 cluster へのアクセスは StringView（ゼロコピースライス）で返す。

```
GraphemeView {
  source: String              // 元の文字列（所有）
  boundaries: Array[Int]      // grapheme cluster 境界の UTF-16 オフセット
}
// 不変条件:
//   空文字列: boundaries == [], length() == 0
//   非空文字列: boundaries[0] == 0, boundaries[last] == source.length()
//   length() == max(0, boundaries.length() - 1)
//   op_get(i) は boundaries[i]..boundaries[i+1] でスライス
```

### UAX #29 実装方針

1. `Grapheme_Cluster_Break` プロパティテーブル — Unicode 16.0.0 の `GraphemeBreakProperty.txt` から生成
2. `Extended_Pictographic` プロパティ — `emoji-data.txt` から生成
3. テーブル生成 — Python or Rust スクリプトで `.mbt` ファイルを自動生成
4. ステートマシン — UAX #29 の GB ルール群を状態遷移テーブルで実装

### 3層の Unicode 問題と本ライブラリの位置

| レイヤー | 問題 | 解決 |
|----------|------|------|
| L1: UTF-16 encoding | `str[i]` がコードユニット単位 | MoonBit core の `iter()` / `char_length()` |
| **L2: Grapheme cluster** | 合成絵文字が複数コードポイント | **本ライブラリ** |
| L3: Display width | 全角/半角の表示幅 | `rami3l/unicodewidth` |

### 段階的実装

1. **Phase 0（完了）**: コードポイント単位の暫定実装。サロゲートペアは正しく処理。
2. **Phase 1**: UAX #29 全GBルール実装（テーブル生成 + ステートマシン + 全テストケース合格）
3. **Phase 2**: パフォーマンス最適化（二段ルックアップテーブル、Compressed Bitset等）
4. **Phase 3**: 追加 API（スライス、逆イテレーション、grapheme 単位 width 等）

---

## Phase 1 詳細設計

### 1. アーキテクチャ

#### ファイル構成

```
src/
  lib.mbt              # GraphemeView 構造体、graphemes()、公開 API（既存）
  gcb.mbt              # GCBCategory enum 定義、gcb_category() ルックアップ関数
  gcb_table.mbt        # 自動生成: GCBレンジテーブル（GCB_TABLE）
  segmenter.mbt        # check_boundary(): ペアルール + 状態追跡によるセグメンテーション
  lib_wbtest.mbt       # ホワイトボックステスト（既存 + 追加）
  gcb_wbtest.mbt       # ホワイトボックステスト: gcb_category() のテスト
  segmenter_wbtest.mbt # ホワイトボックステスト: check_boundary() の個別GBルールテスト
  uax29_test.mbt       # ブラックボックステスト: 公式テストデータ全1,093件
tools/
  gen_gcb_table.py     # テーブル生成スクリプト
  gen_uax29_tests.py   # 公式テストデータからテストコード生成
  data/                # Unicode データファイル（git管理外、スクリプトが自動ダウンロード）
```

#### GCBカテゴリ enum

UAX #29 の `Grapheme_Cluster_Break` プロパティ値に、セグメンテーションに必要な追加カテゴリを統合した16種:

```moonbit
enum GCBCategory {
  Other             // 上記いずれにも該当しない
  CR
  LF
  Control
  Extend
  ZWJ
  Regional_Indicator
  Prepend
  SpacingMark
  L                 // Hangul Leading Jamo
  V                 // Hangul Vowel Jamo
  T                 // Hangul Trailing Jamo
  LV                // Hangul LV Syllable
  LVT               // Hangul LVT Syllable
  Extended_Pictographic  // GCB=Other かつ Extended_Pictographic=Yes → 統合
  InCB_Consonant    // InCB=Consonant → 統合
}
```

Design rationale: Extended_Pictographic と InCB_Consonant を独立カテゴリとして GCB に統合する。
これにより gcb_category() の1回のルックアップで GB11/GB9c に必要な情報が得られ、
別テーブルへの二重ルックアップが不要になる。Rust unicode-segmentation も同じアプローチ。

#### テーブルのエンコーディング

Phase 1 ではシンプルさを優先し、ソート済みレンジ配列 + バイナリサーチを採用する。

```moonbit
// 各エントリ: (range_start, range_end_inclusive, category)
// range_end が不要な単一コードポイントは start == end
let gcb_table : FixedArray[(Int, Int, GCBCategory)] = [
  (0x000A, 0x000A, LF),
  (0x000D, 0x000D, CR),
  (0x0000, 0x0009, Control),
  // ... ソート済みで約1,200エントリ
]
```

テーブルに存在しないコードポイントは `Other` を返す。

#### InCB 補助テーブル

GB9c の判定には InCB=Linker と InCB=Extend の情報が追加で必要。
これらは小さなテーブル（数十エントリ）で別途保持する。

```moonbit
// InCB=Linker のコードポイント（ソート済み配列、バイナリサーチ）
let incb_linker_table : FixedArray[Int] = [0x094D, 0x09CD, ...]

// InCB=Extend のコードポイント/レンジ（ソート済みレンジ配列）
let incb_extend_table : FixedArray[(Int, Int)] = [(0x0900, 0x0902), ...]
```

Design rationale: InCB_Consonant は出現頻度が高くメインテーブルに統合する価値がある。
一方 InCB_Linker/Extend は GB9c の後方スキャン時のみ参照するため、
メインの GCB カテゴリを汚さず補助テーブルとして分離する。

#### セグメンテーションアルゴリズム

`graphemes()` 関数は、コードポイントを前方走査しながらペアルール判定 + 状態追跡で境界を決定する。

```
初期化:
  boundaries = []                -- 空で開始
  prev_gcb: なし（最初のコードポイントは無条件で境界）
  ri_count: 0
  emoji_state: ES_None
  incb_state: IC_None

各コードポイントについて:
  1. gcb_category() でカテゴリ取得
  2. 最初のコードポイント（GB1: sot ÷ Any）、または
     check_boundary(prev_gcb, cur_gcb, state) が true の場合:
     → boundaries に現在の UTF-16 オフセットを追加
  3. 状態更新（prev_gcb, ri_count, emoji_state, incb_state）
  4. UTF-16 オフセットを進める（BMP: +1、サロゲートペア: +2）

ループ終了後:
  boundaries が空でなければ（= 文字列が非空なら）:
    boundaries に文字列末尾オフセット（= source.length()）を追加（GB2: Any ÷ eot）

不変条件:
  空文字列 → boundaries == []、length() == 0
  非空文字列 → boundaries[0] == 0、boundaries[last] == source.length()
  length() == max(0, boundaries.length() - 1)
  op_get(i) は boundaries[i]..boundaries[i+1] で安全にスライスできる
```

### 2. テーブル生成

#### 生成スクリプト `tools/gen_gcb_table.py`

**入力データ:**
- `GraphemeBreakProperty.txt` (Unicode 16.0.0) — GCB プロパティ
- `emoji-data.txt` (Unicode 16.0.0) — Extended_Pictographic プロパティ
- `DerivedCoreProperties.txt` (Unicode 16.0.0) — InCB プロパティ

**処理:**
1. 各データファイルをパースし、コードポイント→プロパティのマッピングを構築
2. GCB カテゴリの優先度で統合:
   - GCB に明示的な値がある → そのカテゴリ（Control, Prepend, SpacingMark 等は決して上書きしない）
   - GCB なし（= Other 相当）+ Extended_Pictographic=Yes → `Extended_Pictographic`
   - GCB なし（= Other 相当）+ InCB=Consonant → `InCB_Consonant`
   - **安全弁:** GCB が Other 以外のコードポイントに InCB=Consonant が付与されている場合、生成スクリプトが警告を出力し、GCB 側のカテゴリを優先する。これにより GB4/5/9a/9b の判定を壊さない
   - **注:** Unicode 16.0.0 では InCB=Consonant と GCB!=Other の重なりは 0 件（Rust unicode-segmentation も同一方式）。将来の Unicode バージョンで衝突が発生した場合は、InCB_Consonant を補助テーブルに退避する等の対応を検討する
3. 隣接する同一カテゴリのレンジをマージ
4. コードポイント昇順でソート

**出力:** `src/gcb_table.mbt`
- `gcb_table`: メインの GCB レンジテーブル
- `incb_linker_table`: InCB=Linker のコードポイントテーブル
- `incb_extend_table`: InCB=Extend のレンジテーブル

**データファイルの取得:**
スクリプトが `tools/data/` ディレクトリに自動ダウンロード（存在しなければ）。
`tools/data/` は `.gitignore` に追加。

#### 生成スクリプト `tools/gen_uax29_tests.py`

**入力:** `GraphemeBreakTest.txt` (Unicode 16.0.0)
**出力:** `src/uax29_test.mbt` — 1,093件のテスト関数

テストデータの `÷`（境界）/ `×`（非境界）記法をパースし、
各行を `test "UAX29/NNN: ..."` の形式で出力する。

### 3. プロパティルックアップ

```moonbit
/// コードポイントの GCB カテゴリを返す。
/// テーブルに存在しないコードポイントは Other を返す。
fn gcb_category(cp : Int) -> GCBCategory {
  // gcb_table に対するバイナリサーチ
  // cp が [range_start, range_end] に含まれるエントリを探す
  // 見つからなければ Other
}

/// コードポイントが InCB=Linker かどうかを返す。
fn is_incb_linker(cp : Int) -> Bool {
  // incb_linker_table に対するバイナリサーチ
}

/// コードポイントが InCB=Extend かどうかを返す。
fn is_incb_extend(cp : Int) -> Bool {
  // incb_extend_table に対するバイナリサーチ
}
```

### 4. セグメンテーション実装

#### 状態型

```moonbit
enum EmojiState {
  ES_None
  ES_EP_Seen           // Extended_Pictographic を見た
  ES_EP_Extend_ZWJ     // EP の後に Extend* ZWJ を見た
}

enum InCBState {
  IC_None
  IC_Consonant_Seen           // InCB_Consonant を見た
  IC_Consonant_Linker_Seen    // Consonant の後に [Extend|Linker]* Linker を見た
}
```

#### ペアルール判定 `check_boundary()`

```moonbit
/// prev と cur のペアで境界を判定する。
/// true = 境界あり（÷）、false = 境界なし（×）
fn check_boundary(
  prev : GCBCategory,
  cur : GCBCategory,
  ri_count : Int,
  emoji_state : EmojiState,
  incb_state : InCBState,
) -> Bool {
  // GB3: CR × LF
  if prev == CR && cur == LF { return false }
  // GB4: (Control|CR|LF) ÷
  if prev == Control || prev == CR || prev == LF { return true }
  // GB5: ÷ (Control|CR|LF)
  if cur == Control || cur == CR || cur == LF { return true }
  // GB6: L × (L|V|LV|LVT)
  if prev == L && (cur == L || cur == V || cur == LV || cur == LVT) { return false }
  // GB7: (LV|V) × (V|T)
  if (prev == LV || prev == V) && (cur == V || cur == T) { return false }
  // GB8: (LVT|T) × T
  if (prev == LVT || prev == T) && cur == T { return false }
  // GB9: × (Extend|ZWJ)
  if cur == Extend || cur == ZWJ { return false }
  // GB9a: × SpacingMark
  if cur == SpacingMark { return false }
  // GB9b: Prepend ×
  if prev == Prepend { return false }
  // GB9c: \p{InCB=Consonant} [\p{InCB=Extend}\p{InCB=Linker}]* \p{InCB=Linker} [\p{InCB=Extend}\p{InCB=Linker}]* × \p{InCB=Consonant}
  if incb_state == IC_Consonant_Linker_Seen && cur == InCB_Consonant { return false }
  // GB11: \p{Extended_Pictographic} Extend* ZWJ × \p{Extended_Pictographic}
  if emoji_state == ES_EP_Extend_ZWJ && cur == Extended_Pictographic { return false }
  // GB12/13: sot (RI RI)* RI × RI / [^RI] (RI RI)* RI × RI
  if prev == Regional_Indicator && cur == Regional_Indicator && ri_count % 2 == 1 { return false }
  // GB999: Any ÷ Any
  true
}
```

#### 状態更新ロジック

各コードポイント処理後に状態を更新:

```
ri_count:
  cur == Regional_Indicator → ri_count + 1
  それ以外 → 0

emoji_state:
  cur == Extended_Pictographic → ES_EP_Seen
  emoji_state == ES_EP_Seen && cur == Extend → ES_EP_Seen（維持）
  emoji_state == ES_EP_Seen && cur == ZWJ → ES_EP_Extend_ZWJ
  GB11 が成立した（ES_EP_Extend_ZWJ && cur == EP）→ ES_EP_Seen（新しいEP列の開始）
  それ以外 → ES_None

incb_state:
  cur == InCB_Consonant → IC_Consonant_Seen
  incb_state != IC_None && is_incb_extend(cp) → 維持
  incb_state != IC_None && is_incb_linker(cp) → IC_Consonant_Linker_Seen
  GB9c が成立した（IC_Consonant_Linker_Seen && cur == InCB_Consonant）→ IC_Consonant_Seen
  それ以外 → IC_None
```

注意: GB9 により Extend/ZWJ は境界を作らないため、emoji_state と incb_state は
Extend/ZWJ を跨いで維持される。これはルールの評価順（GB9 が GB9c/GB11 より前）と
状態更新の組み合わせで自然に実現される。

#### graphemes() の更新

既存の `graphemes()` を、上記のステートマシンを使った実装に置き換える。
公開 API（GraphemeView, length, op_get, iter）は変更なし。

### 5. テスト戦略

#### 5.1 公式テストデータ全件（自動生成）

`tools/gen_uax29_tests.py` が `GraphemeBreakTest.txt` の全1,093ケースを
`src/uax29_test.mbt` に出力する。各テストは grapheme cluster の境界位置を検証。

```moonbit
// 例: ÷ 0020 ÷ 0020 ÷  →  " " と " " に分割
test "UAX29/001: ÷ [0.2] SPACE ÷ [999.0] SPACE ÷ [0.3]" {
  let g = @lib.graphemes("\u{0020}\u{0020}")
  inspect!(g.length(), content="2")
  inspect!(g[0].to_string(), content="\u{0020}")
  inspect!(g[1].to_string(), content="\u{0020}")
}
```

#### 5.2 各GBルール個別テスト（手書き）

`src/segmenter_wbtest.mbt` に、各GBルールを狙い撃ちするテストを手書きする。
公式テストでカバーされないエッジケースを補完。

| ルール | テスト内容 |
|--------|-----------|
| GB3 | CR+LF が1クラスタ |
| GB4/5 | Control 前後で分割 |
| GB6-8 | ハングル音節の結合 |
| GB9 | Extend/ZWJ が前のクラスタに結合 |
| GB9a | SpacingMark が前のクラスタに結合 |
| GB9b | Prepend が後のクラスタに結合 |
| GB9c | インド系文字の子音結合（Consonant + Linker + Consonant） |
| GB11 | 絵文字ZWJシーケンス（👨‍👩‍👧‍👦 等） |
| GB12/13 | 国旗シーケンス（🇯🇵 = RI+RI が1クラスタ、🇯🇵🇺🇸 = 2クラスタ） |

#### 5.3 実世界テキストテスト（手書き）

`src/lib_wbtest.mbt` に追加。ユーザーが実際に遭遇する文字列でのテスト。

- 家族絵文字: "👨‍👩‍👧‍👦" → 1 grapheme cluster
- 国旗: "🇯🇵" → 1 cluster、"🇯🇵🇺🇸" → 2 clusters
- 結合文字: "が" (U+304B U+3099) → 1 cluster
- テキスト+絵文字混在: "Hello🌍World"
- 空文字列: "" → 0 clusters

#### 5.4 gcb_category() テスト（手書き）

`src/gcb_wbtest.mbt` に、代表的なコードポイントのカテゴリ判定テスト。

- ASCII: 0x41('A') → Other, 0x0A(LF) → LF, 0x0D(CR) → CR
- Extend: 0x0300(COMBINING GRAVE ACCENT) → Extend
- RI: 0x1F1E6(REGIONAL INDICATOR SYMBOL LETTER A) → Regional_Indicator
- EP: 0x1F600(GRINNING FACE) → Extended_Pictographic
- Hangul: 0x1100 → L, 0x1161 → V, 0x11A8 → T

### 6. 不採用技術と理由

#### moonbit-community/unicode_data を使わない理由

`moonbit-community/unicode_data` は General_Category 等の基本プロパティを提供するが、
`Grapheme_Cluster_Break` の全13カテゴリは提供していない。
また、Extended_Pictographic や InCB といったセグメンテーション固有のプロパティも未対応。
本ライブラリではこれらを統合した独自カテゴリ（16種）が必要なため、自前でテーブルを生成する。

#### 二段ルックアップテーブル（Trie）を使わない理由

Unicode プロパティのルックアップには、上位ビットで第一テーブルを引き、
下位ビットで第二テーブルを引く二段方式が空間効率に優れる。
しかし Phase 1 ではシンプルさと正確性を優先し、ソート済みレンジ配列 + バイナリサーチを採用する。
テーブルサイズは約1,200エントリ（約14KB）で、バイナリサーチは O(log 1200) ≈ 11回の比較で完了する。
Phase 2 で性能問題が判明した場合に二段テーブルへの移行を検討する。

#### Compressed Bitset を使わない理由

Bitset は「あるプロパティを持つか否か」の bool 判定には適するが、
本ライブラリでは16種のカテゴリ値を返す必要がある。
Bitset をカテゴリ数分用意する方法もあるが、レンジテーブル + バイナリサーチの方が
シンプルで実装・デバッグが容易。Phase 1 の方針に合致する。

### 7. 実装ステップ（TDD順序）

全ステップでテストファーストを徹底する。

#### Step 1: GCBCategory enum 定義

1. `src/gcb.mbt` に `GCBCategory` enum を定義（16種）
2. `derive(Eq, Show)` で比較・表示可能にする
3. `moon test` で既存テスト4件が引き続きパスすることを確認

#### Step 2: テーブル生成スクリプト

1. `tools/gen_gcb_table.py` を実装
   - Unicode データファイルのダウンロード機能
   - パース・統合・レンジマージ・ソート
   - `src/gcb_table.mbt` の出力
2. スクリプトを実行し、`src/gcb_table.mbt` を生成
3. `moon check` でコンパイルが通ることを確認

#### Step 3: gcb_category() ルックアップ — テストファースト

1. `src/gcb_wbtest.mbt` に代表的コードポイントのテストを書く（RED）
2. `src/gcb.mbt` に `gcb_category()` をバイナリサーチで実装（GREEN）
3. エッジケース（テーブル先頭・末尾・レンジ境界）のテスト追加
4. リファクタリング

#### Step 4: check_boundary() ペアルール — テストファースト

1. `src/segmenter_wbtest.mbt` に GB3（CR×LF）のテストを書く（RED）
2. `src/segmenter.mbt` に `check_boundary()` の骨格を実装（GREEN）
3. GB4/5 → GB6-8 → GB9/9a/9b → GB999 の順にテスト追加 → 実装
4. この段階では状態依存ルール（GB9c/GB11/GB12-13）はスキップ（GB999 にフォールスルー）

#### Step 5: graphemes() をステートマシンに置き換え — テストファースト

1. 既存の `lib_wbtest.mbt` のテスト4件がパスする状態を維持しつつ
2. `graphemes()` の内部を、gcb_category() + check_boundary() を使う実装に書き換え
3. 実世界テキストテスト（結合文字「が」等）を追加して通す

#### Step 6: GB12/13（Regional Indicator）— テストファースト

1. 国旗テスト追加（🇯🇵 = 1 cluster、🇯🇵🇺🇸 = 2 clusters）（RED）
2. ri_count による偶奇判定を実装（GREEN）
3. RI×3、RI×4 等のエッジケーステスト追加

#### Step 7: GB11（絵文字ZWJシーケンス）— テストファースト

1. 絵文字ZWJテスト追加（👨‍👩‍👧‍👦 等）（RED）
2. emoji_state による状態追跡を実装（GREEN）
3. EP+Extend+ZWJ+EP の連鎖テスト追加

#### Step 8: GB9c（InCB Conjunct）— テストファースト

1. InCB 補助テーブル生成を `gen_gcb_table.py` に追加
2. `is_incb_linker()`, `is_incb_extend()` のテスト・実装
3. デーヴァナーガリー文字等のインド系文字結合テスト追加（RED）
4. incb_state による状態追跡を実装（GREEN）

#### Step 9: 公式テストデータ全件

1. `tools/gen_uax29_tests.py` を実装
2. `src/uax29_test.mbt` を生成
3. `moon test` で全1,093件を実行
4. 失敗するテストがあれば原因調査・修正

#### Step 10: 最終確認・クリーンアップ

1. 全テスト合格を確認
2. 不要なコメント・TODO の除去
3. `moon check` で警告なしを確認

## 参考

- [UAX #29: Unicode Text Segmentation](https://unicode.org/reports/tr29/)
- [Rust unicode-segmentation](https://github.com/unicode-rs/unicode-segmentation)
- [moonbit-community/unicode_data](https://github.com/moonbit-community/unicode_data)
- [rami3l/unicodewidth](https://github.com/moonbit-community/unicodewidth.mbt)

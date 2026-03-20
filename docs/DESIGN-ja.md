[English](DESIGN.md) | 日本語

# grapheme 設計

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
  cluster_start: Int          // boundaries 内の最初のクラスタインデックス（inclusive）
  cluster_end: Int            // boundaries 内の末尾クラスタインデックス（exclusive）
}
// 不変条件:
//   空文字列: boundaries == [], cluster_start == 0, cluster_end == 0
//   非空文字列: boundaries[0] == 0, boundaries[last] == source.length()
//   length() == cluster_end - cluster_start
//   op_get(i) は boundaries[cluster_start + i]..boundaries[cluster_start + i + 1] でスライス
//   op_as_view によるスライスは cluster_start/cluster_end を調整するだけで boundaries はコピーしない
```

### UAX #29 実装方針

1. `Grapheme_Cluster_Break` プロパティテーブル — Unicode 17.0.0 の `GraphemeBreakProperty.txt` から生成
2. `Extended_Pictographic` プロパティ — `emoji-data.txt` から生成
3. テーブル生成 — Python or Rust スクリプトで `.mbt` ファイルを自動生成
4. ステートマシン — UAX #29 の GB ルール群を状態遷移テーブルで実装

### 3層の Unicode 問題と本ライブラリの位置

| レイヤー | 問題 | 解決 |
|----------|------|------|
| L1: UTF-16 encoding | `str[i]` がコードユニット単位 | MoonBit core の `iter()` / `char_length()` |
| **L2: Grapheme cluster** | 合成絵文字が複数コードポイント | **本ライブラリ** |
| L3: Display width | 全角/半角の表示幅 | `rami3l/unicodewidth` |

### 実装状況

- **UAX #29 全GBルール実装済み** -- テーブル生成、ステートマシン、公式テスト全766件パス。
- **パフォーマンス最適化** -- 二段ルックアップテーブル実装済み（O(1) 定数時間）。ASCII fast path は O(1) テーブルルックアップにより不要となり削除。
- **API** -- `graphemes()`、`grapheme_iter()`（遅延評価）、スライス（`op_as_view`）、逆イテレーション（`rev_iter`）、`iter2`、`grapheme_indices`、`Show`/`Eq`/`Hash` trait、`get`/`is_empty`/`to_string`。

---

## 詳細設計

### 1. アーキテクチャ

#### ファイル構成

```
src/
  lib.mbt              # GraphemeView 構造体、graphemes()、grapheme_iter()、公開 API
  gcb.mbt              # GCBCategory enum 定義、gcb_category() ルックアップ関数
  gcb_table.mbt        # 自動生成: GCB二段ルックアップテーブル（gcb_stage1, gcb_stage2）
  segmenter.mbt        # SegmenterState, check_boundary(): ペアルール + 状態追跡
  lib_wbtest.mbt       # ホワイトボックステスト（既存 + 追加）
  gcb_wbtest.mbt       # ホワイトボックステスト: gcb_category() のテスト
  segmenter_wbtest.mbt # ホワイトボックステスト: check_boundary() の個別GBルールテスト
  uax29_test.mbt       # ブラックボックステスト: 公式テストデータ全766件
  lib_wbbench.mbt      # ベンチマーク
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

#### テーブル設計

二段ルックアップテーブル（4bit packed）を採用し、O(1) 定数時間でカテゴリを取得する。

- **Stage1:** 4,352 bytes（`cp >> 8` でブロックインデックスを取得）
- **Stage2:** 14,208 bytes（111 ユニークブロック x 128 bytes、4bit packed）
- **合計:** 18,560 bytes（18.1 KB）
- **重複排除率:** 97.4%（4,352 ブロック中 111 ユニーク）

```moonbit
// 二段テーブルルックアップ
// Stage1: cp >> 8 → ブロックインデックス
// Stage2: block_idx * 128 + (cp & 0xFF) >> 1 → 4bit ニブル抽出
let gcb_stage1 : Bytes = b"..."  // 4,352 bytes
let gcb_stage2 : Bytes = b"..."  // 14,208 bytes (4-bit packed)
```

テーブルに存在しないコードポイント（ニブル値 0）は `Other` を返す。

Design rationale: 初期実装ではソート済みレンジ配列 + バイナリサーチ（O(log n)、約1,200エントリ）を採用していたが、
二段テーブルに移行することで O(1) 定数時間ルックアップを実現した。テーブルサイズは 18.5 KB と
コンパクトで、97.4% のブロック重複排除により空間効率も良好。

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
- `GraphemeBreakProperty.txt` (Unicode 17.0.0) — GCB プロパティ
- `emoji-data.txt` (Unicode 17.0.0) — Extended_Pictographic プロパティ
- `DerivedCoreProperties.txt` (Unicode 17.0.0) — InCB プロパティ

**処理:**
1. 各データファイルをパースし、コードポイント→プロパティのマッピングを構築
2. GCB カテゴリの優先度で統合:
   - GCB に明示的な値がある → そのカテゴリ（Control, Prepend, SpacingMark 等は決して上書きしない）
   - GCB なし（= Other 相当）+ Extended_Pictographic=Yes → `Extended_Pictographic`
   - GCB なし（= Other 相当）+ InCB=Consonant → `InCB_Consonant`
   - **安全弁:** GCB が Other 以外のコードポイントに InCB=Consonant が付与されている場合、生成スクリプトが警告を出力し、GCB 側のカテゴリを優先する。これにより GB4/5/9a/9b の判定を壊さない
   - **注:** Unicode 17.0.0 では InCB=Consonant と GCB!=Other の重なりは 0 件（Rust unicode-segmentation も同一方式）。将来の Unicode バージョンで衝突が発生した場合は、InCB_Consonant を補助テーブルに退避する等の対応を検討する
3. 隣接する同一カテゴリのレンジをマージ
4. コードポイント昇順でソート

**出力:** `src/gcb_table.mbt`
- `gcb_stage1` / `gcb_stage2`: 二段ルックアップテーブル（4bit packed）
- `incb_linker_table`: InCB=Linker のコードポイントテーブル
- `incb_extend_table`: InCB=Extend のレンジテーブル

**データファイルの取得:**
スクリプトが `tools/data/` ディレクトリに自動ダウンロード（存在しなければ）。
`tools/data/` は `.gitignore` に追加。

#### 生成スクリプト `tools/gen_uax29_tests.py`

**入力:** `GraphemeBreakTest.txt` (Unicode 17.0.0)
**出力:** `src/uax29_test.mbt` — 766件のテスト関数

テストデータの `÷`（境界）/ `×`（非境界）記法をパースし、
各行を `test "UAX29/NNN: ..."` の形式で出力する。

### 3. プロパティルックアップ

```moonbit
/// コードポイントの GCB カテゴリを返す。
/// テーブルに存在しないコードポイントは Other を返す。
fn gcb_category(cp : Int) -> GCBCategory {
  // 二段テーブルルックアップ（O(1) 定数時間）
  // stage1[cp >> 8] → ブロックインデックス
  // stage2[block_idx * 128 + (cp & 0xFF) >> 1] → 4bit ニブル抽出
  // ニブル値 0 は Other
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

#### graphemes() の実装

`graphemes()` は上記のステートマシンで境界を決定する。
公開 API（GraphemeView, length, op_get, iter）は変更なし。

### 5. テスト戦略

#### 5.1 公式テストデータ全件（自動生成）

`tools/gen_uax29_tests.py` が `GraphemeBreakTest.txt` の全766ケースを
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

#### Compressed Bitset を使わない理由

Bitset は「あるプロパティを持つか否か」の bool 判定には適するが、
本ライブラリでは16種のカテゴリ値を返す必要がある。
Bitset をカテゴリ数分用意する方法もあるが、二段ルックアップテーブルの方が
シンプルで実装・デバッグが容易。

### 7. 開発履歴

TDD（テストファースト）で以下の順序で実装した:

1. GCBCategory enum 定義（16種）
2. テーブル生成スクリプト（`gen_gcb_table.py`）→ `gcb_table.mbt` 生成
3. `gcb_category()` バイナリサーチ実装
4. `check_boundary()` ペアルール実装（GB3 → GB4/5 → GB6-8 → GB9/9a/9b → GB999）
5. `graphemes()` をステートマシンベースに置き換え
6. GB12/13（Regional Indicator）ri_count による偶奇判定
7. GB11（絵文字ZWJシーケンス）emoji_state による状態追跡
8. GB9c（InCB Conjunct）incb_state + 補助テーブル
9. 公式テストデータ全766件パス（`gen_uax29_tests.py`）
10. 追加 API（スライス、逆イテレーション、遅延評価イテレータ等）
11. GCB テーブルを二段ルックアップテーブルに移行（O(log n) → O(1)、ASCII fast path 不要化）

## 参考

- [UAX #29: Unicode Text Segmentation](https://unicode.org/reports/tr29/)
- [Rust unicode-segmentation](https://github.com/unicode-rs/unicode-segmentation)
- [moonbit-community/unicode_data](https://github.com/moonbit-community/unicode_data)
- [rami3l/unicodewidth](https://github.com/moonbit-community/unicodewidth.mbt)

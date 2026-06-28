# 2026-06-29: テストスタイル相互レビュー (timespec.mbt vs grapheme.mbt) と統合論アンチパターン

## 背景

`claude-rules-personal/for-all/rules/tdd-and-test-design.md` (= 旧
`tdd-twada.md` を supersede した統合版) の inline コメント原則
(= 「DR ref は補助 marker、判断本質を文章で inline、test 単体で
self-contained」) に従って、grapheme.mbt と timespec.mbt の両 session
で並行に test inline 化作業を実施。kawaz から「同じ作業を今日隣でやってた、
互いの感想とテスト変化を相互レビューしてみて」と指示があり、両 session で
cmux-msg 経由の相互レビューを行った。

## 両 session のスタイル差

### grapheme.mbt の書き方 (= commit `b98016f6`)

```moonbit
///|
// Input: prev=CR, cur=LF with all state defaults.
// Expected: false (no boundary).
// Why: UAX #29 GB3 keeps CR LF as a single grapheme — a CRLF newline pair must
// not split, otherwise text rendering would treat the two halves of a Windows
// line ending as separate clusters.
test "check_boundary: GB3 CR×LF" {
  inspect(check_boundary(CR, LF, 0, ES_None, IC_None), content="false")
}
```

特徴:
- **構造化テンプレ** (Input / Expected / Why の 3 行)
- **UAX #29 仕様番号を直接引用** (= GB3 / GB4 等)
- **expected が syntactic** (= `content="false"`)、Why で意味補強
- `[script]` decorator + structured assert で「機械的に読みやすい」
- `gen_uax29_tests.py` の generator が自動生成する case にも同テンプレが乗る

### timespec.mbt の書き方 (= commit `7b2ff3d0`)

```moonbit
///|
test "parse_timespec: @ suffix (Absolute)" {
  // 末尾 @ も先頭 @ と同等に Absolute フラグを立てる。配置位置で意味を変えると
  // @ の idempotency (= 任意位置 / 任意回でも一意な状態に収束) が壊れるため、
  // prefix/suffix を同じ Absolute 化として扱う (DR-0007 Phase 2, DR-0008)。
  debug_inspect(
    @timespec.parse_timespec("-5h@", now=test_now, default_sign=Minus),
    content=(
      #|Some(Absolute(EpochTime(-17000000), Duration(-18000000)))
    ),
  )
}
```

特徴:
- **自然文段落** (1-3 行)
- **ドメイン語彙が前面** (= 「@ idempotent 規約」「結果 vs やり方」)
- **expected が semantic** (= `Some(Absolute(EpochTime(...), Duration(...)))`、constructor 名で意味が読める)
- DR ref は文末に cosmetic な history pointer として併記
- test が「ドメイン概念の動く辞書」として機能

## 相互レビュー → 統合論アンチパターン

grapheme 側 (= 私) は最初「**両スタイルのハイブリッド** が正解」と整理しかけた:

- Input/Expected の 2 行は構造化 (= grapheme スタイル)
- Why は自然文で 1-3 行 (= timespec スタイル)
- 外部仕様 ref は積極的に inline
- 内部 DR ref は cosmetic 末尾併記
- invariant を section banner で先に宣言

ハイブリッド案を timespec に投げたところ、kawaz から決定的な指摘が入った:

> あちらとこちらは扱ってるドメインが違うからね。grapheme の方は
> 標準ありきでその準拠度が至上価値、timespec は自分で使うツールで
> 好きに仕様も決めるし責任範囲も違う。

これで両 session スタイル差の **根本理由** が一発で言語化された。

## 非対称構造の整理

- **grapheme = 外部 source of truth (UAX #29) への準拠度が至上価値**
  - test は「仕様準拠の証明」
  - 仕様番号引用が source of truth 直接参照
  - Input/Expected/Why の構造化は「準拠条件と帰結を機械的にチェック」
  - invariant banner は「仕様 N 章を cell 群で覆う」カバレッジマトリクス
- **timespec = 内部 source of truth (自分で決めた仕様)**
  - test は「自分が決めた仕様の動く辞書」
  - ドメイン語彙の固定は「自分で決めた概念名」を test に pin する作業
  - 自然文段落は「なぜそう決めたか」のニュアンスを残す余白

両者の長所 (= 構造化テンプレ + 仕様 ref / ドメイン語彙固定 + 自然文段落) は
**domain 性質が互いに排他的** な制約から導かれているため、ハイブリッドに
すると両方の domain 性質を裏切る。

具体的に何が崩れるか:
- grapheme が自然文段落に振ると、外部仕様との 1:1 対応が見えにくくなる
  (= 準拠カバレッジの可視性が下がる)
- timespec が構造化テンプレに振ると、ドメイン概念のニュアンスが失われる
  (= 動く辞書としての機能が下がる)

= 「両方の良いとこ取り」は「両方の悪いとこ取り」に転化する典型例。

## 私 (grapheme.mbt 側) の self-blindspot 記録

「ハイブリッドが正解」と整理しかけた瞬間の雑さは記録に残す価値あり。
具体的には:

1. 比較レビューを始めた時点で **「両方の長所を集約できる第 3 案」を探す癖** が
   無意識に発動した
2. 各長所の **由来 (= domain 制約)** を確認しないまま集約案を組み立てた
3. timespec への返信に「ハイブリッドの方向性は上記提案」と書いた時点で
   既に集約論にコミット状態
4. kawaz の domain 性質差指摘で集約不可能と判明、提案取り下げ

= 「統合論への衝動」が `feedback-evaluation` rule の「悪い面を必ず探す」と
裏返しのアンチパターン。両方褒める = 両方の悪い面を見ていない徴候。

## 取り入れる項目 (= domain 性質を裏切らない範囲)

ハイブリッド統合論は取り下げたが、**domain 性質を裏切らない範囲で互いに
学ぶ** ことは可能、と timespec とも合意:

### grapheme 側で取り入れるもの

1. **複合仕様 (= GB11 と GB9/GB12 の相互作用) で 3 行テンプレが詰まる時、
   段落化を例外的に許容** — 仕様 cell が独立じゃない箇所では構造化テンプレ
   が表現力不足
2. **UAX #29 が ambiguous で grapheme が独自解釈を取った箇所 (= lone
   surrogate / Plane 14 ordering) は自然文段落で記録** — 外部仕様が
   source of truth でなくなる箇所では DR + 自然文段落が正解
3. **invariant の section banner で軸を宣言** — DR-0007 の scope/NA banner と
   方向が同じ、もう一段階下のレベル (= section 内の軸) に同じ手法を持ち込む

### timespec 側で取り入れるもの (= timespec session が自身で整理)

1. invariant の section banner 追加検討
2. basic units の根拠 1 行追加
3. ISO 8601 への ref 置換候補洗い出し (= 外部 source of truth が乗る部分の
   strengthening)

## 結晶化 → rule 提案

統合論アンチパターン自体は domain 横断で発動する self-blindspot なので、
`claude-rules-personal/for-all/rules/synthesis-temptation-guard.md` として
個人 rule に結晶化する提案を claude-rules-personal session に投げた
(2026-06-29 02:31)。

ハイブリッド衝動が出る場面 (= 「両方の良いとこ取り」「ハイブリッド」
「統合案」「中間 / 折衷」と書きたくなる瞬間) で 3 つの自問を強制する形:

1. **各長所の由来は何か?** (= domain 性質 / トレードオフ)
2. **その由来は集約案でも保持されるか?**
3. **集約案を採用した時、両元案の長所は何 % 維持されるか?**

3 つすべてを答えられないなら、ハイブリッド案を書かず各案を **並列のまま**
ユーザに渡す。

## 関連

- [DR-0003-uax29-corpus-coverage-strategy](../decisions/DR-0003-uax29-corpus-coverage-strategy.md)
- [DR-0007-test-scope-split](../decisions/DR-0007-test-scope-split.md)
- 個人 rule: `tdd-and-test-design.md` (= 旧 `tdd-twada.md` から supersede、
  inline コメント原則)
- 個人 rule: `feedback-evaluation.md` (= 悪い面を必ず探す、ハイブリッド衝動の対極)
- 個人 rule (= 提案中): `synthesis-temptation-guard.md`
- timespec.mbt commit `7b2ff3d0` (= 自然文段落スタイルの test inline 化)
- grapheme.mbt commit `b98016f6` (= 構造化テンプレスタイルの test inline 化 + assert tighten)

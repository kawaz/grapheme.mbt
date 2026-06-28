# DR-0004: `graphemes()` と `grapheme_iter()` の境界判定 parity

- Status: Active
- Date: 2026-06-28

## Context

公開 API は 2 つの経路で grapheme cluster 境界を返す:

- **`graphemes(s)`**: 文字列を頭から終端まで pre-scan して boundaries 配列を
  構築 (O(n) 前処理)、その後 `GraphemeView` 経由でランダムアクセス可能。
- **`grapheme_iter(s)`**: 遅延 iterator、`next()` で 1 cluster ずつ消費。
  前方探索のみで途中停止が可能、early-break 用途で `graphemes()` の数倍速い。

実装は `SegmenterState` (= GB ルールを実装した state machine) を **両経路で
共有**しており、同じ入力に対して **同じ cluster 列を返す**ことが必要不変条件。
この parity が崩れると iter() 専用利用者と view 経由利用者で結果が乖離し、
ライブラリの信頼性が崩れる。

しかし現状の test 構成では `graphemes()` だけが公式 766 ケース (UAX #29
コーパス) を通っており、`grapheme_iter()` は手書き白箱テストのみ。コーパス
規模での parity が unverified。

## Decision

`grapheme_iter()` を公式コーパス 766 ケース全てに通し、`graphemes()` と同じ
cluster 列を返すことを inspect する **生成テストファイル `src/uax29_iter_test.mbt`**
を `tools/gen_uax29_tests.py` の追加成果物として導入する。

具体的には:

```moonbit
test "UAX29/0001-iter: <input>" {
  let input = "..."
  let g = graphemes(input)
  let from_iter : Array[String] =
    grapheme_iter(input).map(fn(v) { v.to_owned() }).collect()
  let from_view : Array[String] =
    g.iter().map(fn(v) { v.to_owned() }).collect()
  assert_eq(from_iter, from_view)
}
```

これにより両経路の **boundaries / cluster 列が一致することがコーパス規模で
保証**される。

加えて、UAX #29 公式コーパス由来 766 ケースの主 test (`uax29_test.mbt`) にも
**`iter()` ordering を 1 行で pin** する assert を追加 (= `g.iter()` の cluster
列が `g[0..]` の index アクセス列と一致)、index 経由と iter 経由の swap が
silent に壊れないようにする。

## Alternatives Considered

- 案 A: parity を property-based test で取る (= ランダム入力で `graphemes` と
  `grapheme_iter` の差分を取り 0 を assert)
  - 不採用理由: 公式コーパスの方が UAX 仕様への適合根拠として強い (= UCD が
    保証する境界判定の正解集合)。property-based は **既知の仕様** に対する
    回帰検知としては優位だが、現状の本ライブラリでは公式コーパスの全件通過
    で十分。属性 fuzz は将来の `tools/` 拡張で別途検討する。
- 案 B: parity を doc にだけ書いて test しない
  - 不採用理由: 不変条件が test で固定化されていないと、片方の経路だけが
    変更された時に silent regression する。仕様契約として最優先で test 化。

## Consequences

- `tools/gen_uax29_tests.py` は **2 つの test ファイル**を生成する:
  `src/uax29_test.mbt` (= `graphemes()` の cluster 列を pin)、
  `src/uax29_iter_test.mbt` (= `grapheme_iter()` が同じ列を返すことを pin)。
- `just gen-tests` 実行で両者が同時更新される。
- 公式コーパスが 766 ケースから増えても両ファイルが同期して拡張される。
- `graphemes()` と `grapheme_iter()` のどちらか片方を修正した PR は両ファイル
  でテストを走らせるため、parity 破壊を CI が検知する。

## 関連

- [DR-0003-uax29-corpus-coverage-strategy](./DR-0003-uax29-corpus-coverage-strategy.md)
- 実装: `src/lib.mbt::graphemes`, `src/lib.mbt::grapheme_iter`,
  `src/segmenter.mbt::SegmenterState`
- 生成器: `tools/gen_uax29_tests.py`

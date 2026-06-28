# Decision Records 一覧

## Active

- [DR-0001-moonbit-new-syntax-migration](./DR-0001-moonbit-new-syntax-migration.md) —
  MoonBit 0.1.20260618 系の破壊的変更 (moon.mod 新形式、`fn` 必須化、
  StringView::to_owned、@debug.debug_inspect) への追従方針
- [DR-0002-justfile-canonical-alignment](./DR-0002-justfile-canonical-alignment.md) —
  justfile を kawaz canonical pattern (bump-semver vcs 委譲 + gate stack +
  workflow が tag を打つ release flow) に揃え、publish.yml を tag-trigger 型から
  moon.mod paths-trigger 型に置換
- [DR-0003-uax29-corpus-coverage-strategy](./DR-0003-uax29-corpus-coverage-strategy.md) —
  UAX #29 公式 766 ケースが何をカバーし何を補完 test ファイルに委ねるかの責務表
- [DR-0004-segmenter-state-parity](./DR-0004-segmenter-state-parity.md) —
  `graphemes()` と `grapheme_iter()` の境界判定 parity をコーパス規模で固定
- [DR-0005-plane14-tag-ordering](./DR-0005-plane14-tag-ordering.md) —
  Plane 14 タグ範囲 (絵文字旗 / VS17-256) の Extend → Control フォールバック順序
- [DR-0006-lone-surrogate-policy](./DR-0006-lone-surrogate-policy.md) —
  Lone surrogate を 1 cluster として切る lenient policy、両経路の観察結果一致
- [DR-0007-test-scope-split](./DR-0007-test-scope-split.md) —
  4 + 2 個の test ファイルの scope / NA 責務分割表

## Archived

<!-- 現役の文脈を汚す古い DR は decisions/archive/ に退避し、ここに記載 -->

## Moved to research/

<!-- 判断記録の体を成さなくなり research/ に降格した DR -->

## Superseded

<!-- 後続 DR に上書きされた DR (Status: Superseded by DR-XXXX) -->

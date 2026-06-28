# DR-0003: UAX #29 公式コーパスのカバレッジ戦略

- Status: Active
- Date: 2026-06-28

## Context

UAX #29 `GraphemeBreakTest.txt` (Unicode 17.0.0、766 ケース) を本ライブラリの
仕様適合の主要根拠としているが、コーパスがカバーしない仕様軸が複数存在する。
test ファイル間で「どの軸がどこに属するか」を暗黙にすると、後続セッションが
「漏れ」と「意図的な NA」を区別できない。

## Decision

UAX #29 コーパスは `src/uax29_test.mbt` に **upstream のテキストを完全自動
生成** (= `tools/gen_uax29_tests.py`) で取り込み、GB ルールの組合せ網羅を担う。
コーパスがカバーしない以下の軸は **別 test ファイル**で受け、各ファイル先頭に
「このファイルが担う軸 / 担わない軸」を明示する:

| 軸 | 担う test ファイル |
|---|---|
| GB3..GB13 のルール組合せ (766 ケース) | `src/uax29_test.mbt` (生成物) |
| `graphemes()` と `grapheme_iter()` の parity | `src/uax29_iter_test.mbt` (生成物、DR-0004 参照) |
| Plane 14 タグ範囲 (E0000-E01FF, ordering 依存) | `src/plane14_tags_test.mbt` (手書き、DR-0005 参照) |
| Lone high surrogate の処理 | `src/lib_wbtest.mbt` (DR-0006 参照) |
| GraphemeView の公開 API + 不変条件 | `src/lib_wbtest.mbt` |
| 状態遷移 (next_emoji_state / next_incb_state / check_boundary cell 網羅) | `src/segmenter_wbtest.mbt` |
| GCB カテゴリ表 (二段 lookup + InCB packed table) | `src/gcb_wbtest.mbt` |
| Eq / Hash / Show trait の振る舞い | `src/lib_wbtest.mbt` |

## Alternatives Considered

- 案 A: コーパスを唯一の基準とし、補助 test を持たない
  - 不採用理由: コーパスは UTF-16 surrogate-pair 経路 / GraphemeView スライス /
    iter() の lazy 経路 / Plane 14 ordering / GraphemeView::Eq/Hash の trait
    意味論をカバーしない。これらは仕様の一部だが UCD 由来テキストには表現
    できないため、別の test ファイルで担う必要がある。
- 案 B: コーパスをパースして「足りない軸を自動生成」する totalizer を書く
  - 不採用理由: パース対象が UCD 1 ファイルでは情報が足らない (= 例えば
    GraphemeView の trait 意味論はコーパス外)。さらに生成器を複雑化させると
    `gen_uax29_tests.py` の責務 (= UCD → MoonBit テストファイル変換) を逸脱、
    保守困難になる。

## Consequences

- 各 test ファイル先頭に「scope」「out-of-scope (NA)」セクションを置き、
  本 DR を cross-ref する (例: `// scope: GB3..GB13 corpus 766 cases / NA:
  surrogate, view API, trait — DR-0003 参照`)。
- 新しい軸を見つけたら本 DR の表に追記し、担当ファイルを明示する。
- `tools/gen_uax29_tests.py` は header コメントに `https://www.unicode.org/
  Public/17.0.0/ucd/auxiliary/GraphemeBreakTest.txt` と SHA-256 を埋め込み、
  コーパスの version 追跡を可能にする。

## 関連

- [DR-0004-segmenter-state-parity](./DR-0004-segmenter-state-parity.md)
- [DR-0005-plane14-tag-ordering](./DR-0005-plane14-tag-ordering.md)
- [DR-0006-lone-surrogate-policy](./DR-0006-lone-surrogate-policy.md)
- [DR-0007-test-scope-split](./DR-0007-test-scope-split.md)
- UAX #29: <https://www.unicode.org/reports/tr29/>
- Test data: <https://www.unicode.org/Public/17.0.0/ucd/auxiliary/GraphemeBreakTest.txt>

# DR-0007: 白箱テストファイルの責務分割

- Status: Active
- Date: 2026-06-28

## Context

`src/` 配下の白箱テストファイルは 4 つに分かれている:

- `lib_wbtest.mbt` (~2000 行): `GraphemeView` の公開 API + trait 振る舞い
- `segmenter_wbtest.mbt` (~300 行): state machine cell (check_boundary,
  next_emoji_state, next_incb_state) + state transition
- `gcb_wbtest.mbt` (~320 行): GCB カテゴリ表の lookup (二段 lookup + InCB
  packed table)
- `uax29_test.mbt` (~8900 行): UAX #29 公式コーパス 766 ケース (自動生成)

これらが「どの仕様軸を担当するか」が暗黙だと、後続セッションが他ファイルに
担当が移っている軸を「漏れ」と誤検知し、重複追加してしまう。逆に、どこにも
担当が割り当てられていない軸が silent に放置されるリスクもある。

## Decision

各ファイル先頭に **scope (担う軸) と NA (担わない軸 + 担当ファイル参照)**
を明示する banner コメントを置く。具体的に以下の責務分割を canonical 実装と
する:

### `lib_wbtest.mbt`

- **scope**:
  - `GraphemeView` 公開 API (length, op_get, get, is_empty, to_string,
    op_as_view, iter, iter2, rev_iter, grapheme_indices)
  - Eq / Hash / Show trait の振る舞い
  - `grapheme_iter()` の API (lazy 経路の挙動)
  - GraphemeView の不変条件 (boundaries, cluster_start/end, slicing)
  - lone surrogate の挙動 (= DR-0006 参照)
- **NA**:
  - UAX #29 GB1-GB13 ルール組合せ網羅 → `uax29_test.mbt` が担当
  - state machine cell 網羅 → `segmenter_wbtest.mbt` が担当
  - GCB カテゴリ表の境界点 → `gcb_wbtest.mbt` が担当
  - Plane 14 タグ順序依存 → `plane14_tags_test.mbt` が担当 (DR-0005 参照)

### `segmenter_wbtest.mbt`

- **scope**:
  - `check_boundary(prev, cur, ri_count, emoji_state, incb_state)` の cell
    網羅 (= GB ルール 1 個ずつの戻り値)
  - `next_emoji_state` の state × input 遷移行列
  - `next_incb_state` の state × input 遷移行列
  - ri_count parity invariant (= ri_count は両側 RI の時のみ意味を持つ)
- **NA**:
  - GCB カテゴリ判定 (lookup) → `gcb_wbtest.mbt` が担当
  - 公開 API → `lib_wbtest.mbt` が担当
  - 公式コーパス → `uax29_test.mbt` が担当

### `gcb_wbtest.mbt`

- **scope**:
  - `gcb_category(cp)` の境界点 (= 各 Unicode plane 境界、二段 lookup の
    stage1 transition 点、各 GCB カテゴリの neighbor cp)
  - `is_incb_consonant` / `is_incb_linker` / `is_incb_extend` packed
    Bytes 表の bound 探索 (first entry, last entry, gap-between-entries)
  - Plane 14 ordering 依存の境界点 (= DR-0005 参照)
- **NA**:
  - GB ルールに基づく境界判定 → `segmenter_wbtest.mbt` + `uax29_test.mbt`
    が担当
  - 公開 API → `lib_wbtest.mbt` が担当

### `uax29_test.mbt` (自動生成)

- **scope**:
  - UAX #29 公式 `GraphemeBreakTest.txt` 766 ケース全件 (= GB3-GB13 ルール
    組合せの網羅根拠)
  - 各ケースの cluster 列 (content) + iter() ordering parity
- **NA**:
  - Plane 14 タグ列 (= 公式コーパス未収録) → `plane14_tags_test.mbt`
  - lone surrogate (= 公式コーパス未収録) → `lib_wbtest.mbt`
  - GraphemeView 公開 API → `lib_wbtest.mbt`
  - Eq/Hash/Show → `lib_wbtest.mbt`

### `uax29_iter_test.mbt` (自動生成、DR-0004 参照)

- **scope**: `grapheme_iter()` を同じ 766 ケースに通し、`graphemes()` と
  cluster 列が一致することを pin
- **NA**: `uax29_test.mbt` と同じ

### `plane14_tags_test.mbt` (手書き、DR-0005 参照)

- **scope**: Plane 14 タグ範囲の end-to-end セグメンテーション (絵文字旗
  サブディビジョン、language tag 等)
- **NA**: 一般の Plane 14 cp (= GCB Other) → `gcb_wbtest.mbt`

## Alternatives Considered

- 案 A: 1 つの巨大テストファイルに全部寄せる
  - 不採用理由: 既に lib_wbtest.mbt が 2000 行を超えていて、ファイル単位の
    責務分離があるからこそ「どこを見ればよいか」が分かる。統合すると
    `just gen-tests` で再生成される `uax29_test.mbt` (8900 行) も巻き込まれ、
    生成器と非生成器が混在する。
- 案 B: 暗黙の責務分割を継続し、scope/NA banner を書かない
  - 不採用理由: 後続セッションが「漏れ」と「意図的な NA」を区別できない
    と、二重テスト追加 / 軸放置 / 「他のファイルを読み直す」探索コスト増を
    招く。明示するコストは数行 vs 認知コストの数十分、明示する方が安い。

## Consequences

- 新たに test ケースを追加する時、まず本 DR の表を読み、適切なファイルを
  選ぶ。
- 各 test ファイル先頭の banner には本 DR を cross-ref する 1 行を書く
  (例: `// scope/NA: DR-0007 参照`)。
- ファイル責務を変える PR は本 DR を更新する。

## 関連

- [DR-0003-uax29-corpus-coverage-strategy](./DR-0003-uax29-corpus-coverage-strategy.md)
- [DR-0004-segmenter-state-parity](./DR-0004-segmenter-state-parity.md)
- [DR-0005-plane14-tag-ordering](./DR-0005-plane14-tag-ordering.md)
- [DR-0006-lone-surrogate-policy](./DR-0006-lone-surrogate-policy.md)

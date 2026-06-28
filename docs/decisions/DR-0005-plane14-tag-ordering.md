# DR-0005: Plane 14 タグ範囲のカテゴリ判定順序

- Status: Active
- Date: 2026-06-28

## Context

Unicode の **Plane 14 (Supplementary Special-purpose Plane, U+E0000-U+EFFFF)**
には 2 つの異なる GCB カテゴリが混在している:

- **U+E0000-U+E001F** (Language Tag Code Points): GCB = `Control`
  (= grapheme cluster を切る)
- **U+E0020-U+E007F** (Tag characters, used in emoji subdivision flag
  sequences): GCB = `Extend` (= 直前 cluster に含める)
- **U+E0100-U+E01EF** (Variation Selectors 17-256): GCB = `Extend`
- **U+E01F0-U+E0FFF** および **U+E1000-U+EFFFF**: GCB = `Control`
  (= 上記 Extend 範囲以外の Plane 14 全域)

例として、絵文字の地域旗 (= 🏴󠁧󠁢󠁥󠁮󠁧󠁿 England flag) は
`BLACK FLAG (U+1F3F4) + TAG LATIN SMALL LETTER G (U+E0067) + ...
+ CANCEL TAG (U+E007F)` の連鎖で **単一 cluster** を形成する。これは
`U+E0067` 等が **Extend** として直前の BLACK FLAG に吸収されることに依存する。
もし判定順序を間違えて Plane 14 全域を Control 扱いにすると、地域旗の各
タグが独立 cluster になり、絵文字表示が崩れる。

GCB テーブル実装 (`src/gcb_table.mbt::gcb_category_plane14`) は **Extend
範囲を先に判定し、それ以外を Control にフォールバック**する分岐順序を採用。

```moonbit
fn gcb_category_plane14(cp : Int) -> GCBCategory {
  // E0020-E007F: tag chars (= Extend)
  if cp >= 0xE0020 && cp <= 0xE007F { return Extend }
  // E0100-E01EF: VS17-256 (= Extend)
  if cp >= 0xE0100 && cp <= 0xE01EF { return Extend }
  // それ以外の Plane 14: Control
  Control
}
```

この順序が崩れると、たとえば `cp >= 0xE0000 && cp <= 0xE0FFF { Control }`
を先に書くと E0020-E007F が Control 扱いに巻き込まれ、地域旗が壊れる。

## Decision

Plane 14 のカテゴリ判定は **Extend を先に、Control を後にフォールバック**
する順序を canonical 実装とする。テストでは:

- `src/gcb_wbtest.mbt`: 各境界点 (U+E0019, U+E001F, U+E0020, U+E007F,
  U+E0080, U+E00FF, U+E0100, U+E01EF, U+E01F0) の単体カテゴリ判定を pin
- `src/plane14_tags_test.mbt` (= 新規): 地域旗を含む実 cluster 列で
  end-to-end のセグメンテーションを pin
- いずれの test も「**ordering が逆だと壊れる**」ことが分かるよう、Extend
  範囲とその両隣の Control 範囲を必ず併記

## Alternatives Considered

- 案 A: 2 つの Extend 範囲を 1 つの `if cp in ranges` 構造体 lookup に統合
  - 不採用理由: 二段 lookup の packed Bytes 表現 (Plane 0-2) と異なり、
    Plane 14 は範囲が少ない (2 つ) ので素朴な分岐の方が読みやすい。Bytes
    化は領域効率より分かりやすさを優先。
- 案 B: ordering を関数コメントで述べるだけで test しない
  - 不採用理由: コメントは silent regression を検知できない。将来の refactor
    で順序を入れ替えた瞬間に絵文字旗が壊れる、その瞬間 CI で止める。

## Consequences

- `src/gcb_table.mbt::gcb_category_plane14` の分岐順序を変える PR は test 失敗
  で検知される。
- 新たに Plane 14 サブレンジが Unicode に追加された場合、本 DR の境界点リスト
  に追加し、対応する gcb_wbtest + plane14_tags_test を追加する。
- `gen_uax29_tests.py` で生成する `uax29_test.mbt` は公式コーパスベースだが、
  公式コーパスは絵文字旗 (タグ列) を全カバーしてはいないので、本 test ファイル
  が補完責任を持つ (= DR-0003 参照)。

## 関連

- [DR-0003-uax29-corpus-coverage-strategy](./DR-0003-uax29-corpus-coverage-strategy.md)
- UCD: GraphemeBreakProperty.txt (Plane 14 範囲定義)
- 実装: `src/gcb_table.mbt::gcb_category_plane14`
- Unicode: <https://www.unicode.org/charts/PDF/UE0000.pdf>

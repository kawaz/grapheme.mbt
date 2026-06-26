# リポジトリ物理構造

```
grapheme.mbt/
  README.md / README-ja.md      ユーザ向け窓口
  LICENSE                       MIT (Yoshiaki Kawazu)
  CHANGELOG.md                  リリース履歴 (Keep a Changelog)
  moon.mod                      MoonBit module 設定 (TOML-like 新形式)
  justfile                      task runner (canonical, docs-structure 参照)
  .unicode-version              生成元 Unicode のバージョン (gen-tables の入力)
  src/                          実装本体 (publish 対象)
    moon.pkg                    パッケージ設定
    lib.mbt                     GraphemeView / graphemes / grapheme_iter
    segmenter.mbt               UAX #29 状態機械 (check_boundary)
    gcb.mbt                     Grapheme_Cluster_Break 区分定義
    gcb_table.mbt               生成済みテーブル (2 段 lookup + InCB Bytes pack)
    pkg.generated.mbti          公開インタフェース (moon info で生成)
    lib_wbtest.mbt              white-box テスト
    gcb_wbtest.mbt              white-box テスト (GCB 区分)
    segmenter_wbtest.mbt        white-box テスト (state 遷移)
    lib_wbbench.mbt             bench
    uax29_test.mbt              UAX #29 GraphemeBreakTest.txt の網羅テスト (生成物)
  tools/                        生成スクリプト (publish 除外)
    gen_gcb_table.py            UCD → gcb_table.mbt
    gen_uax29_tests.py          UCD → uax29_test.mbt
    data/                       UCD キャッシュ (gitignore)
  docs/                         設計・運用・履歴
    DESIGN.md / DESIGN-ja.md    現実装の説明
    STRUCTURE.md                (このファイル)
    ROADMAP.md                  将来検討項目
    decisions/                  設計判断の記録 (DR)
      INDEX.md                  DR 一覧
      DR-NNNN-*.md              DR 本体
    journal/                    日々の生記録 (ハマり所 → 解決策)
  .github/workflows/            CI / publish
  .claude/                      個人 Claude 設定 (rules / settings.local.json)
```

## publish 対象の境界

`moon.mod` の `options(exclude: [...])` で以下を publish 除外:

- `docs/` `tools/` `.unicode-version` `justfile` `CHANGELOG.md`
- `**/*_test.mbt` `**/*_wbtest.mbt` `**/*_wbbench.mbt`

`src/` 配下の `lib.mbt` / `segmenter.mbt` / `gcb.mbt` / `gcb_table.mbt` /
`pkg.generated.mbti` だけが公開される。

## 生成ファイル

`src/gcb_table.mbt` と `src/uax29_test.mbt` は生成物。`.unicode-version` の
バージョンを bump したら `just gen` で再生成する。

## task runner

`justfile` が canonical。`just list` で recipe 一覧。`just ci` で
`fmt-check + check + info + test` を 1 発で回す。

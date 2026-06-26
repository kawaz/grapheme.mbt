# 2026-06-26: MoonBit 新文法 + docs-structure 整備

## 背景

`moon 0.1.20260618` で文法・config・deprecation が更新された。
`just check` (= `moon check --deny-warn`) が 92 件の warning で落ちる
状態だったので追従する。同時に docs-structure ルール (kawaz personal
canonical) に揃える。

## 着地点

- `moon check --deny-warn`: 0 warning / 0 error
- `moon test`: 1075 passed
- `moon fmt --check`: pass
- docs-structure: README / DESIGN の相互リンクヘッダを `>` blockquote +
  `./` 相対パス形式に統一、`docs/{decisions,journal}/` を新設、
  `STRUCTURE.md` / `ROADMAP.md` 追加

## ハマり所 → 解決策

### 1. `moon.mod.json` → `moon.mod` の自動移行

- 現象: `moon fmt` を初回実行した瞬間に `moon.mod.json` が消えて
  `moon.mod` (TOML-like) が生まれた。justfile が `jq -r '.version'
  moon.mod.json` に依存していて即死した。
- 解決: justfile を `awk -F'"' '/^version[[:space:]]*=/ { print $2;
  exit }' moon.mod` に書き換え。新形式は厳密 TOML ではないため
  `tomllib` でパース不可、awk の単純抽出が一番安定。

### 2. `impl ... with output()` → `impl ... with fn output()`

- 現象: `moon fmt --check` が `gcb_wbtest.mbt` / `segmenter_wbtest.mbt`
  で差分を出し続けた (= `fn` キーワード必須化)。`moon fmt` 一回では
  fmt 後に新文法に書き換わるが、`--check` だけ実行していると気付け
  ない。
- 解決: 一旦 `moon fmt` を実行して書き換えてもらう。`moon fmt --check`
  自体が `git --no-pager diff --color=always --no-index` に依存していて、
  bare git + worktree 環境では subprocess 起動コマンドが err 表示するが
  内容としては 0 warning / 0 errors なので無視できる (差分が無くなれば
  err 自体も出なくなる)。

### 3. `inspect(value, ...)` の Show→Debug deprecation

- 現象: 36 件の "Use Debug instead of Show for debugging purposes" warning。
  対象は全て composed value (`Array[String]`, `Array[(Int, Int)]` 等)。
- 解決: `moonbitlang/core/debug` を `src/moon.pkg` に `for "wbtest"`
  scope で import し、`inspect(...)` を `@debug.debug_inspect(...)` に
  置換。`for "test"` ではなく `for "wbtest"` であることに注意 (= 警告
  対象は `*_wbtest.mbt` 内、`*_test.mbt` の black-box テストとは category
  が違う)。`~/.moon/lib/core/bigint/moon.pkg` で実例確認。

### 4. `src/uax29_test.mbt` (自動生成) も deprecation の塊

- 現象: lib.mbt / lib_wbtest.mbt の 92 件を直し終えたあと、
  自動生成テスト 1391 件の `g[N].to_string()` warning が表に出てきた。
- 解決: 生成物を直接 `to_owned` に書き換え + `tools/gen_uax29_tests.py`
  の出力テンプレートも `to_owned` に修正。再生成 (`just gen-tests`)
  しても同じ結果になることを確認。

## 設定値 / コマンド

```bash
# 警告の場所と種類を一覧化 (gen 中の checklist として使った)
moon check --deny-warn 2>/tmp/moon-warnings.txt
awk '/╭─\[/ { match($0, /lib(_wbtest)?\.mbt:[0-9]+/); if (RSTART) loc=substr($0,RSTART,RLENGTH); else loc="" }
     /to_owned/ { print loc, "TO_OWNED" }
     /Use Debug/ { print loc, "USE_DEBUG" }' /tmp/moon-warnings.txt

# 最終チェック
moon fmt --check && moon check --deny-warn && moon test
```

## 関連

- [DR-0001-moonbit-new-syntax-migration](../decisions/DR-0001-moonbit-new-syntax-migration.md)

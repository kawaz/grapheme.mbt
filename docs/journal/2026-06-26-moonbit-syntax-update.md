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
- 解決: `bump-semver get` に `--define-rule` + `--version-regex` で
  カスタムソースを定義する経路があったのでそれを使用:
  ```
  bump-semver get moon.mod --define-rule moon.mod --format text \
    --version-regex 'version = "(.+)"' -qq
  ```
  awk 抽出も動くが、bump-semver 経由なら mismatch 検出 (= 将来 VERSION
  ファイルと併用するとき) も同じ仕組みに乗る。
- 上流フィードバック: `bump-semver` は `moon.mod` を basename 自動検出
  対象としていない (= 「unsupported file: moon.mod」hint が出る)。
  TOML-like だが厳密 TOML ではないため auto-detect には工夫要。
  kawaz/bump-semver に issue 起票候補。

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

## 続き: justfile / publish.yml を kawaz canonical pattern に置換 (DR-0002)

最初に書いた justfile は前リビジョンのカスタム release flow を引き継いで
`[confirm] release:` 形式 / `version :=` just 変数依存 / `jq -r '.version'
moon.mod.json` ベースで、kawaz/* リポ群の canonical pattern (bump-semver vcs
+ sync/promote/ensure-clean/check-on-default-branch/check-version-bumped/
`push` gate stack + `[hint] gh-monitor:watch-workflow ...`) から大きく逸脱
していた。kuu.mbt / timespec.mbt / bump-semver / claude-cmux-msg / claude-
plugin-reference / claude-push-guard / claude-nandakke / claude-gh-monitor
など 10 件横断で確認した canonical pattern に揃え直し。

主な差分:

- `default: list` (= `@just --list --unsorted`) で recipe 一覧を先頭に
- `[confirm] release:` 廃止 → `push:` gate stack で代替 (= `check-on-default-
  branch ci check-translations check-version-bumped` → `bump-semver vcs push
  --branch main --jj-bookmark-auto-advance` → `[hint] gh-monitor` echo)。
  tag は `publish.yml` が打つ (release-flow-awareness 準拠)
- just 変数撤廃 (= shell 内の `{{ }}` クオート問題回避、canonical でも禁則)
- `sync` / `promote` / `ensure-clean` / `check-on-default-branch` を追加 (DR-0038
  dogfood)
- `check-translation-freshness` / `_check-translation-headers` を追加 (README +
  docs/DESIGN を対象)
- `check-version-bumped` を `bump-semver vcs diff -q main@origin -- <paths>` +
  rc case 分岐 + `bump-semver compare gt` で実装 (テストファイルは exclude)
- `bump-version level="patch":` で moon.mod の version を直接 bump + Release
  commit (custom rule `--define-rule moon.mod --format text --version-regex
  'version = "(.+)"'` 経由)。`on-success-release` recipe 追加
- `publish.yml`: `on: push: tags: 'v*'` 廃止 → `on: push: branches:[main],
  paths:[moon.mod]` トリガに変更。workflow 内で moon.mod の version > 既存
  tag を bump-semver で verify → `moon publish` → `gh release create v${VERSION}`
  で tag + GH Release 自動作成。tag を人/AI が打つ経路を完全に閉じる
- `ci.yml`: lint matrix を `moon fmt --check` + `moon check --deny-warn` に集約、
  test matrix は `native / wasm-gc / wasm / js` の 4 target

### 上流フィードバック (= dogfooding-feedback-upstream)

- bump-semver: moon.mod (TOML-like 専用記法) を basename auto-detect 対象に
  追加してほしい (= `--define-rule` の長い呪文を justfile 4 箇所で繰り返す
  事態を避けたい)。kawaz/bump-semver に
  `docs/issue/2026-06-26-moon-mod-autodetect.md` 起票済み
- 設計判断記録は [DR-0002-justfile-canonical-alignment](../decisions/DR-0002-justfile-canonical-alignment.md)

## ふりかえり

最初に「awk で moon.mod 読めばいい」「bump-semver は moon.mod 未サポート」と
ヘルプを見ずに断定して、`bump-semver get --define-rule` の存在を見逃したのが
最大のミス。kawaz の指摘で `bump-semver get --help` → `bump-semver patch --help`
を確認して custom rule 経路が判明した。

その後 justfile を canonical pattern に揃え直す段でも、kawaz が「10 件くらい
見て回ってこい」と言うまで MoonBit リポ (kuu.mbt / timespec.mbt) しか参照
していなかった。それらは canonical 化が遅れている過渡期リポなので、もっと
成熟した kawaz リポ (bump-semver / claude-plugin-reference / claude-cmux-msg
等) を読まないと canonical pattern は掴めなかった。

教訓 (= 個人 rule に反映候補):

1. **CLI 機能の限界を語る前に、該当 subcommand のヘルプを必ず実行する**
2. **kawaz canonical pattern を取りに行くときは、特定言語の最新リポではなく、
   bump-semver canonical を中心に複数言語 (Go / TS / shell / MoonBit / Python)
   を横断的に読む**

## 続き 2: `?` sigil / die helper の試行と canonical 形への着地 (2026-06-27〜28)

DR-0002 で canonical 形に揃えた justfile を、`?` sigil と inline die helper で
更に簡素化できないか試行した経緯。最終的に die helper は撤回、`?` sigil は
維持、`no-historical-noise` rule に従い除外列挙を include 列挙に置き換え。

### `?` sigil による `_check-version-bumped` 簡素化 (採用)

just 1.47.0+ の `?` sigil (`set guards` + `set unstable` 必須、
<https://just.systems/man/en/sigils.html>) と bash の `!` 論理否定を組合せて
`? ! cmd` 構文を使うと、「`vcs diff -q` が rc=0 (no diff) なら早期 return、
rc=1 (diff) なら本体続行」を 2 行で書ける:

```just
[private]
_check-version-bumped *target_paths:
    ? ! bump-semver vcs diff -q main@origin -- {{ target_paths }}
    bump-semver compare gt moon.mod vcs:main@origin
```

`[script]` decorator + rc case 分岐の 22 行を 4 行に圧縮。仕様: `?` sigil は
exit 0 で本体続行、exit 1 で recipe を success として早期 return、それ以外は
予約済み (= 使うな)。bash の `!` は 0/1 反転なので `?` の予約に触れない。

### inline die helper の試行と撤回

`cmd || die "msg"` を Perl 風に書きたい誘惑から、`set shell` の `-c` 直後の
command string に die 関数を仕込む experiment を試した:

```just
# 試行 (= 後に撤回した形)
set shell := ["bash", "-c", 'exec bash -euo pipefail -c "die() { printf \"%s\n\" \"\$*\" >&2; return 1; }; line=\"\$1\"; shift 2; eval \"\$line\"" -- "$@"', "--"]
```

- 動作はする (= 全 recipe で `cmd || die "msg"` が使える)
- `set positional-arguments` 有効時の引数渡しが特殊 (= shell の場合
  `$1=recipe行, $2=recipe名, $3+=args`、script-interpreter は `$1=temp_file,
  $2+=args`)、自前 `-c <cmd>` を入れる代償として `shift` 回数を調整する必要

bump-semver / timespec の両 peer に提案 → **両 peer 不採用方向**:
- 利用側 justfile に汎用 helper を仕込むのは対症療法、根治は bump-semver
  subcommand 側の stderr 強化が筋
- canonical 見本効果 (= 「読み手が真似しやすい」) を escape 地獄が損なう
- `[script("bash")]` / shebang 自前指定 recipe で die が効かない carve-out が
  恣意的

kawaz が standalone な `die(1)` バイナリを公開 (= `kawaz/die`, `brew install
kawaz/tap/die`)、grapheme.mbt は inline 仕掛けを撤回して **外部コマンド `die
-- "msg"` を素朴に呼ぶ形**に転換。`set shell` は canonical 形
(`["bash", "-euo", "pipefail", "-c"]`) に戻り、bump-semver / kuu /
timespec と完全に揃った。

### no-historical-noise rule 反映 (= 除外列挙の禁止)

`_check-version-bumped` の `bump-semver vcs diff` で「test ファイルを除外」
していた `--excludes 'glob:src/**/*_wbtest.mbt'` 等の **除外列挙** を撤廃。
rule の「拾うべきものを網羅すれば、それ以外は自動的に拾われない (= 包含側で
書け)」に従い、publish 対象の include 列挙に切替:

```just
check-version-bumped: (_check-version-bumped \
    "src/lib.mbt" "src/segmenter.mbt" "src/gcb.mbt" "src/gcb_table.mbt" \
    "src/pkg.generated.mbti" "src/moon.pkg" "moon.mod")
```

### 教訓 (= 個人 rule への結晶化候補)

3. **対症療法 (= 利用側の boilerplate 追加) より根治 (= 上流コマンドの
   stderr 強化、独立 CLI 提供) を選ぶ**。今回は kawaz が `die(1)` を独立
   CLI 化することで「全 justfile で素朴に使える」を実現、利用側 justfile を
   汚さない解に着地した
4. **canonical pattern の試行段階は仮実装と revert を恐れずやる**。両 peer
   と 1〜3 ターンで提案 → 評価 → 撤回まで回せたのは cmux-msg の peer
   レビューがあったから。試行記録は journal に「採用 / 撤回 / 着地」の流れ
   で残す

## 関連

- [DR-0001-moonbit-new-syntax-migration](../decisions/DR-0001-moonbit-new-syntax-migration.md)
- [DR-0002-justfile-canonical-alignment](../decisions/DR-0002-justfile-canonical-alignment.md)
- 上流: <https://github.com/kawaz/die> — standalone `die(1)` バイナリ
- 上流: <https://just.systems/man/en/sigils.html> — `?` sigil 仕様
- 個人 rule: `no-historical-noise.md` — 除外列挙の禁止

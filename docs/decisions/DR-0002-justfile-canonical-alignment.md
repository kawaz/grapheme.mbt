# DR-0002: justfile と publish.yml を kawaz canonical pattern に揃える

- Status: Active
- Date: 2026-06-26

## Context

DR-0001 で MoonBit toolchain migration を行った際、付随作業として justfile も
新 `moon.mod` 形式に対応させた。しかしその justfile はリポジトリの旧構造
(`[confirm] release:` 形式 / `jq -r '.version' moon.mod.json` / `version :=`
just 変数依存) を引き継いだだけで、kawaz/* リポ群の canonical pattern とは
大きく乖離していた。

canonical pattern は kawaz/bump-semver の justfile を中心に、`bump-semver vcs`
サブコマンドへの委譲、DR-0038 dogfood (`sync` / `promote` / `check-on-default-
branch`)、`bump-semver vcs outdated` による翻訳鮮度検査、`vcs diff -q
main@origin -- <paths>` + `compare gt` による version bump 漏れ検出、push 末尾の
`[hint] gh-monitor:watch-workflow --on-success ...` echo といった統一構造を
持ち、kawaz/claude-cmux-msg / kawaz/claude-plugin-reference /
kawaz/claude-push-guard / kawaz/claude-nandakke / kawaz/claude-gh-monitor /
kawaz/kuu.mbt / kawaz/timespec.mbt など 10+ リポで共通化されている。

公開ライブラリの release flow についても release-flow-awareness ルールが
「tag は workflow が打つ、人/AI は打たない」と明示しており、grapheme.mbt の
旧 publish.yml (= `on: push: tags: 'v*'` の tag-trigger 型) は「仕組みの bug」
として書き換え対象。

## Decision

justfile を kawaz/bump-semver 由来の canonical pattern に揃え、publish.yml を
kuu.mbt/timespec.mbt 型 (= source-of-truth 行の paths trigger → bump-semver で
verify → workflow が tag + GH Release + mooncakes.io publish を作る) に書き
換える。

具体:

- justfile
  - `default: list` + `list: @just --list --unsorted`
  - just 変数を一切使わない。paths は recipe 引数 / リテラル、値は `$(...)` 直叩き
  - gate stack: `check-on-default-branch` → `ci` → `check-translations` →
    `check-version-bumped`
  - bump-trigger paths: `src/` + `moon.mod` + `src/moon.pkg`、テストファイル
    (`*_wbtest.mbt` / `*_wbbench.mbt` / `*_test.mbt`) は exclude
  - source-of-truth = `moon.mod` 1 個 (VERSION ファイル追加はせず、二重管理を
    避ける)
  - `bump-semver get/patch` に `--define-rule moon.mod --format text
    --version-regex 'version = "(.+)"'` を渡して moon.mod を直接扱う
  - 末尾 `[hint] gh-monitor:watch-workflow --on-success Publish 'just on-
    success-release' kawaz/grapheme.mbt` echo

- publish.yml
  - `on: push: branches:[main], paths:[moon.mod]` トリガ
  - check-version job が moon.mod の version > 既存最新 tag を bump-semver で
    verify。`MOD_VERSION` placeholder (0.0.0/empty) や既存 tag 未進展は changed=false
  - publish job が `moon publish` で mooncakes.io にアップロード
  - release job が `gh release create v${VERSION}` で tag + GH Release 作成

## Alternatives Considered

- 案 A: VERSION ファイルを正本にして moon.mod は sed で同期 (kuu.mbt /
  timespec.mbt パターン)
  - 不採用理由: MoonBit は moon.mod の version フィールドが native の
    source-of-truth で、Go 文化由来の VERSION ファイルを追加すると二重管理に
    なる。同期 sed もメンテコスト。kawaz の指摘どおり VERSION ファイルは
    「Go あたりの文化」で MoonBit には不要。
- 案 B: bump-semver の auto-detect 対応を待ってから canonical 化
  - 不採用理由: canonical 化を先送りすると、その間に追加の justfile 変更が
    旧構造で蓄積する。`--define-rule` は冗長だが今すぐ動くし、auto-detect
    対応されたら呪文を消すだけで移行できる (= 後方互換が壊れる方向ではない)。
- 案 C: tag-trigger publish のまま justfile だけ canonical 化
  - 不採用理由: release-flow-awareness が「標準型から外れた」と明示判定する
    型を残すと、AI が手で tag を打つ事故を招く穴が残る。仕組みで閉じる。

## Consequences

- `[confirm] release:` recipe を廃止。release は `just push` の gate stack
  通過後、publish.yml が自動でやる
- moon.mod の version 行を bump したらそれが release trigger になる。VERSION
  ファイルは作らない
- `bump-semver` の auto-detect 対応 (= kawaz/bump-semver
  `docs/issue/2026-06-26-moon-mod-autodetect.md`) が完了したら、justfile の
  `--define-rule ...` 呪文を削除可能 (= 単に `moon.mod` を渡すだけになる)
- canonical pattern との一貫性を維持するため、構造変更は kawaz/bump-semver
  の justfile を先に直してからこちらへ追従する

## 関連

- [DR-0001-moonbit-new-syntax-migration](./DR-0001-moonbit-new-syntax-migration.md)
- [journal/2026-06-26-moonbit-syntax-update](../journal/2026-06-26-moonbit-syntax-update.md)
- 個人 rule: `release-flow-awareness.md` (tag は workflow が打つ)
- 個人 rule: `dogfooding-feedback-upstream.md` (bump-semver upstream への issue)
- canonical 実装: kawaz/bump-semver/justfile、kawaz/claude-cmux-msg/justfile、
  kawaz/claude-plugin-reference/justfile、kawaz/kuu.mbt/.github/workflows/release.yml

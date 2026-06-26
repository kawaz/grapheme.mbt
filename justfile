# grapheme.mbt — MoonBit UAX #29 grapheme cluster library
#
# Canonical task runner (kawaz/bump-semver の justfile を MoonBit 用に薄く
# アレンジ)。VCS / 翻訳鮮度 / bump 系は bump-semver vcs にすべて委譲し、jj/git
# 分岐の手書きを撲滅する。release は moon.mod の version 行を trigger とする
# publish.yml が tag + GH Release + mooncakes.io publish を一括で行う
# (release-flow-awareness 準拠、tag は workflow が打つ — 人/AI は触らない)。
#
# 言語差分:
#   - lint/test = moon fmt --check / moon check --deny-warn / moon test
#   - source-of-truth = moon.mod (TOML-like 専用記法、bump-semver v0.41.0+ で
#     basename auto-detect 対応済み、`bump-semver get/patch moon.mod` で動く)
#   - bump-trigger = src/ + moon.mod + src/moon.pkg、テストファイルは除外

# `set guards` (= recipe 行頭の `?` sigil で「コマンドが exit 1 なら recipe 全体を
# success として早期 return」) を有効化するために必要な unstable flag。
# 詳細: https://just.systems/man/en/settings.html#unstable1310
set unstable

# recipe 行頭の `?` sigil を guard として有効化。`?! cmd` (= 直後に `! cmd`) で
# bash の論理否定と組み合わせ、「コマンドが成功なら early return / 失敗なら本体
# 続行」の逆向き guard が書ける (= `_check-version-bumped` 参照)。
# 詳細: https://just.systems/man/en/sigils.html
set guards

set shell := ["bash", "-euo", "pipefail", "-c"]

set script-interpreter := ["bash", "-euo", "pipefail"]

set positional-arguments

# default: lint + test (= 開発中 `just` 一発で回る、timespec.mbt 流儀)
default: lint test

# show the recipe list
list:
    @just --list --unsorted

# === Lint ===

# Format check + type check (warnings as errors) を 1 つに集約
lint: fmt-check check

# Format check only (no modification)
fmt-check:
    moon fmt --check

# Format code (auto-fix)
fmt:
    moon fmt

# Type check with warnings as errors
check:
    moon check --deny-warn

# === Test ===

# Run tests (native target)
test:
    moon test --target native

# Run tests on all targets
test-all:
    moon test --target all

# Update snapshot tests
test-update:
    moon test --update

# === Utilities ===

# Generate type definition files (.mbti)
info:
    moon info

# Clean build artifacts
clean:
    moon clean

# Run benchmarks
bench:
    moon bench

# === Coverage ===

# Coverage summary
coverage:
    moon coverage analyze -- -f summary

# Coverage HTML report
coverage-html:
    moon coverage analyze -- -f html

# === CI ===

# CI single entry: lint + test + info (mbti drift 検出含む)
ci: lint test info

# === Code generation ===

# Regenerate GCB tables from Unicode data
gen-tables:
    python3 tools/gen_gcb_table.py
    moon fmt

# Regenerate UAX #29 official tests
gen-tests:
    python3 tools/gen_uax29_tests.py
    moon fmt

# Regenerate all generated files
gen: gen-tables gen-tests

# === Push / Release flow (bump-semver canonical 模倣) ===

# --- gates (push の内部) ---

[private]
ensure-clean:
    bump-semver vcs is clean

[private]
[script]
check-on-default-branch:
    if ! bump-semver vcs is on-default-branch; then
        cur=$(bump-semver vcs get current-branch 2>/dev/null || echo "(ambiguous)")
        bn=$(bump-semver vcs get default-branch)
        printf >&2 "⚠ 現在 '%s' bookmark/branch にいます。%s に合流してから push してください\n  1. just sync         # %s@origin に rebase\n  2. just promote      # %s bookmark を current commit に forward\n  3. %s ワークスペースに移動して just push\n" "$cur" "$bn" "$bn" "$bn" "$bn"
        exit 1
    fi

sync:
    bump-semver vcs sync --onto $(bump-semver vcs get default-branch)@origin

promote:
    bump-semver vcs promote

# 翻訳ペア (README + docs/DESIGN の ja/en) の鮮度 + 相互リンクヘッダ整合
[private]
check-translations: ensure-clean check-translation-freshness (_check-translation-headers "README") (_check-translation-headers "docs/DESIGN")

[private]
check-translation-freshness:
    bump-semver vcs outdated 'glob:**/*-ja.md' '$1/$2.md'

[private]
_check-translation-headers name:
    ?test -f {{ name }}-ja.md
    test -f {{ name }}.md
    head -5 {{ name }}-ja.md | grep -qF "> [English](./{{ file_name(name) }}.md) | 日本語"
    head -5 {{ name }}.md    | grep -qF "> English | [日本語](./{{ file_name(name) }}-ja.md)"

# product code (src/ + moon.mod + src/moon.pkg) に変更があれば version bump 必須
check-version-bumped: (_check-version-bumped "src/" "moon.mod" "src/moon.pkg")

[private]
_check-version-bumped *target_paths:
    # `?` guard + `! cmd` (bash の論理否定) の組み合わせ:
    #   vcs diff -q が rc=0 (= no diff) → `! 0` = 1 → `?` で早期 return
    #   vcs diff -q が rc=1 (= diff)   → `! 1` = 0 → 本体続行 (= compare gt)
    # `?` と `!` の間にスペースを入れて「`?` だけが just sigil、`! cmd` は素朴
    # な bash 否定」と読める形にする。
    ? ! bump-semver vcs diff -q main@origin -- {{ target_paths }} --excludes 'glob:src/**/*_wbtest.mbt' --excludes 'glob:src/**/*_wbbench.mbt' --excludes 'glob:src/**/*_test.mbt'
    bump-semver compare gt moon.mod vcs:main@origin -qq || { echo 'ERROR: product code が変わってるが moon.mod の version が main@origin より上がっていません。"just bump-version" を実行してください' >&2; exit 1; }

# --- release flow ---

# moon.mod の version を bump (default: patch) して Release commit
[script]
bump-version level="patch": ensure-clean
    bump-semver "$1" moon.mod --write --quiet
    bump-semver vcs commit -m "Release v$(bump-semver get moon.mod --quiet)" moon.mod

# 現在の version を表示
version:
    @bump-semver get moon.mod --quiet

# push to origin/main with canonical gates
push: check-on-default-branch ci check-translations check-version-bumped
    bump-semver vcs push --branch main --jj-bookmark-auto-advance
    @echo "[hint] gh-monitor:watch-workflow --sha $(bump-semver vcs get commit-id --rev main) --on-success Publish 'just on-success-release' kawaz/grapheme.mbt"

# publish.yml が success になった時のフォローアクション
on-success-release:
    @echo "Released v$(bump-semver get moon.mod --quiet) to mooncakes.io"

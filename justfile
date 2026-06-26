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

set unstable

set guards

set shell := ["bash", "-euo", "pipefail", "-c"]

set script-interpreter := ["bash", "-euo", "pipefail"]

set positional-arguments

# default: list
default: list

# show the recipe list
list:
    @just --list --unsorted

# ---------- atomic (lint / test / coverage) ----------

# Format code (auto-fix)
fmt:
    moon fmt

# Format check only (no modification)
fmt-check:
    moon fmt --check

# Type check (warnings as errors)
check:
    moon check --deny-warn

# Run tests (native target)
test:
    moon test --target native

# Run tests on all targets
test-all:
    moon test --target all

# Update snapshot tests
test-update:
    moon test --update

# Generate type definition files (.mbti)
info:
    moon info

# Clean build artifacts
clean:
    moon clean

# Run benchmarks
bench:
    moon bench

# Coverage summary
coverage:
    moon coverage analyze -- -f summary

# Coverage HTML report
coverage-html:
    moon coverage analyze -- -f html

# CI single entry: fmt-check + check + info + test
ci: fmt-check check info test

# ---------- code generation ----------

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

# ---------- gates (push の内部) ----------

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
[script]
_check-version-bumped *target_paths:
    rc=0
    bump-semver vcs diff -q main@origin -- "$@" \
        --excludes 'glob:src/**/*_wbtest.mbt' \
        --excludes 'glob:src/**/*_wbbench.mbt' \
        --excludes 'glob:src/**/*_test.mbt' \
        || rc=$?
    case "$rc" in
      0) exit 0 ;;
      1) ;;
      *) echo "ERROR: bump-semver vcs diff failed (rc=$rc). main@origin が track されていない可能性。先に 'jj git fetch' を試してください" >&2; exit 1 ;;
    esac
    new=$(bump-semver get moon.mod -qq)
    old=$(bump-semver get 'vcs:main@origin:moon.mod' -qq 2>/dev/null || echo "0.0.0")
    bump-semver compare gt "$new" "$old" -qq && exit 0
    echo "ERROR: product code が変わってるが version 未 bump (now=${new} origin=${old})。\"just bump-version\" を実行してください" >&2
    exit 1

# ---------- release flow ----------

# moon.mod の version を bump (default: patch) して Release commit
[script]
bump-version level="patch": ensure-clean
    bump-semver "$1" moon.mod --write --quiet
    bump-semver vcs commit -m "Release v$(bump-semver get moon.mod -qq)" moon.mod

# 現在の version を表示
version:
    @bump-semver get moon.mod -qq

# push to origin/main with canonical gates
push: check-on-default-branch ci check-translations check-version-bumped
    bump-semver vcs push --branch main --jj-bookmark-auto-advance
    @echo "[hint] gh-monitor:watch-workflow --sha $(bump-semver vcs get commit-id --rev main) --on-success Publish 'just on-success-release' kawaz/grapheme.mbt"

# publish.yml が success になった時のフォローアクション
on-success-release:
    @echo "Released v$(bump-semver get moon.mod -qq) to mooncakes.io"

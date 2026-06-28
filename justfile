# grapheme.mbt — MoonBit UAX #29 grapheme cluster library
#
# Canonical task runner (kawaz/bump-semver の justfile を MoonBit 用に薄く
# アレンジ)。VCS / 翻訳鮮度 / bump 系は bump-semver vcs にすべて委譲し、jj/git
# 分岐の手書きを撲滅する。release は moon.mod の version 行を trigger とする
# publish.yml が tag + GH Release + mooncakes.io publish を一括で行う
# (release-flow-awareness 準拠、tag は workflow が打つ — 人/AI は触らない)。

# `set guards` (recipe 行頭の `?` sigil で「コマンドが exit 1 なら recipe 全体を
# success として早期 return」) を有効化するための unstable flag。
# 詳細: https://just.systems/man/en/settings.html#unstable1310
set unstable

# recipe 行頭の `?` sigil を guard として有効化。`? ! cmd` で bash の論理否定
# と組み合わせ、「コマンドが成功なら early return / 失敗なら本体続行」の
# 逆向き guard が書ける (= `_check-version-bumped` 参照)。
# 詳細: https://just.systems/man/en/sigils.html
set guards

set shell := ["bash", "-euo", "pipefail", "-c"]

set script-interpreter := ["bash", "-euo", "pipefail"]

set positional-arguments

# default: lint + test (= 開発中 `just` 一発で回る)
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
check-on-default-branch:
    bump-semver vcs is on-default-branch

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

# mooncakes.io publish される production code に diff があれば version bump が必須
check-version-bumped: (_check-version-bumped \
    "src/lib.mbt" \
    "src/segmenter.mbt" \
    "src/gcb.mbt" \
    "src/gcb_table.mbt" \
    "src/pkg.generated.mbti" \
    "src/moon.pkg")

[private]
_check-version-bumped *target_paths:
    # `?` sigil + `! cmd` で「diff なし = 早期 return、diff あり = 本体続行」。
    # 詳細: https://just.systems/man/en/sigils.html
    ? ! bump-semver vcs diff -q main@origin -- {{ target_paths }}
    bump-semver compare gt moon.mod vcs:main@origin

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

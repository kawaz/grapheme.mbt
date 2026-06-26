# MoonBit Project Commands
#
# Canonical task runner. Mirrors the shape of kawaz/bump-semver:
# `default` aliases `list`, atomic recipes first, release flow at the bottom.

set shell := ["bash", "-euo", "pipefail", "-c"]

set script-interpreter := ["bash", "-euo", "pipefail"]

set positional-arguments

# Read `version = "x.y.z"` line from MoonBit moon.mod (new TOML-like format)
version := `awk -F'"' '/^version[[:space:]]*=/ { print $2; exit }' moon.mod`
tag := "v" + version
repo_git := `git rev-parse --git-common-dir`

# default behaviour: alias for `list`
default: list

# show the recipe list
list:
    @just --list --unsorted

# ---------- atomic (lint / test / build) ----------

# Format code
fmt:
    moon fmt

# Check formatting (no changes applied)
fmt-check:
    moon fmt --check

# Type check (warnings are errors)
check:
    moon check --deny-warn

# Run tests
test:
    moon test

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

# Coverage summary (runs tests with instrumentation internally)
coverage:
    moon coverage analyze -- -f summary

# Coverage HTML report (runs tests with instrumentation internally)
coverage-html:
    moon coverage analyze -- -f html

# CI entry point: fmt-check + check + info + test
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

# ---------- release flow ----------

# Pre-release check (back-compat alias of `ci`)
release-check: ci

# Release: tag and push to trigger CI publish
[confirm]
release: ci _release-preflight _release-push _release-tag
    @echo ""
    @echo "==> {{ tag }} released! CI will publish to mooncakes.io."
    @echo "[hint] gh-monitor:watch-workflow --sha $(jj log -r main -T 'commit_id' --no-graph) publish.yml '' kawaz/grapheme.mbt"

_release-preflight: _release-fetch _release-check-changelog _release-check-no-tag _release-check-clean

_release-fetch:
    @jj git fetch

_release-check-changelog:
    @grep -qF '## [{{ version }}]' CHANGELOG.md || { echo "ERROR: CHANGELOG.md has no entry for [{{ version }}]"; exit 1; }

_release-check-no-tag:
    @git --git-dir="{{ repo_git }}" rev-parse "refs/tags/{{ tag }}" >/dev/null 2>&1 && { echo "ERROR: Tag {{ tag }} already exists"; exit 1; } || true

_release-check-clean:
    @test "$(jj log -r @ --no-graph -T 'if(empty, "true", "false")')" = "true" || { echo "ERROR: @ has changes. Run 'jj describe -m \"...\" && jj new' first."; exit 1; }
    @test "$(jj log -r @ --no-graph -T 'if(description.first_line().len() > 0, "true", "false")')" = "false" || { echo "ERROR: @ has a description. Run 'jj new' to cut, or 'jj describe -m \"\"' to clear."; exit 1; }
    @echo "NOTE: Ensure README.md and docs/DESIGN.md are synced from their -ja.md originals."
    @echo "==> Release target for {{ tag }}:"
    @jj log -r '@-'

_release-push:
    jj bookmark set main -r @-
    jj git push --bookmark main

_release-tag:
    jj tag set "{{ tag }}" -r @-
    jj git export
    LEFTHOOK=0 GIT_WORK_TREE="{{ justfile_directory() }}" git --git-dir="{{ repo_git }}" push origin "{{ tag }}"

# MoonBit Project Commands

# Default: check + test
default: check test

# Format code
fmt:
    moon fmt

# Check formatting (no changes applied)
fmt-check:
    moon fmt --check

# Type check
check:
    moon check --deny-warn

# Run tests
test:
    moon test

# Update snapshot tests
test-update:
    moon test --update

# Generate type definition files (.mbti)
info:
    moon info

# Clean build artifacts
clean:
    moon clean

# Run tests on all targets
test-all:
    moon test --target all

# Run benchmarks
bench:
    moon bench

# Coverage summary (runs tests with instrumentation internally)
coverage:
    moon coverage analyze -- -f summary

# Coverage HTML report (runs tests with instrumentation internally)
coverage-html:
    moon coverage analyze -- -f html

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

# Pre-release check
release-check: fmt-check check info test

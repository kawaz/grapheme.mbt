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

# Pre-release check
release-check: fmt-check check info test

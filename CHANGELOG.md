# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- GitHub Actions CI workflow (`moon check`, `moon test` on wasm-gc/js/native, `moon fmt --check`)
- `justfile` with build/test/coverage/bench/gen recipes
- CHANGELOG.md
- `grapheme_iter()`/`graphemes()` content equivalence test (11 input patterns)
- GB5 Any÷LF/CR, emoji state reset, InCB state extend unit tests
- Gen scripts now emit `///|` block separators

### Changed
- README: badges, catchphrase, 3-layer table, NFC/NFD note, enriched Usage examples
- Docstrings: `grapheme_indices()` offset terminology, `Eq` normalization note, `iter2()` index clarification
- `release-check` recipe order fixed (fmt-check → check → info → test)

## [0.8.0] - 2026-03-20

### Added
- Unicode 17.0.0 support (upgraded from 16.0.0)
- Myanmar InCB properties (Consonant, Linker, Extend) per Unicode 17.0.0

### Changed
- GCB tables regenerated from Unicode 17.0.0 UCD data (1618 entries)
- Official test suite updated to Unicode 17.0.0 (766 tests)
- README API section replaced with mooncakes.io link
- Copyright year updated to 1991-2025 in generated tables

## [0.7.1] - 2026-03-19

### Fixed
- Repository URL in moon.mod.json

## [0.5.0] - 2026-03-18

### Added
- `grapheme_indices()` API with UTF-16 code unit offsets
- `Hash` trait for `GraphemeView`
- `grapheme_iter()` lazy iterator (64x faster for early-break)
- 105 abnormal/boundary/special Unicode tests
- Publish size optimization (exclude test/bench files)

## [0.1.0] - 2026-03-16

### Added
- Initial release on mooncakes.io
- UAX #29 compliant grapheme cluster segmentation (Unicode 16.0.0)
- `graphemes()` and `GraphemeView` with full API
- ASCII fast path optimization
- `Show`/`Eq` traits, `get`/`is_empty`/`to_string`
- Slice operations (`op_as_view`)
- `rev_iter`, `iter2`
- 1,093 official UAX #29 test cases passing

[Unreleased]: https://github.com/kawaz/unicodegrapheme.mbt/compare/v0.8.0...HEAD
[0.8.0]: https://github.com/kawaz/unicodegrapheme.mbt/compare/v0.7.1...v0.8.0
[0.7.1]: https://github.com/kawaz/unicodegrapheme.mbt/compare/v0.5.0...v0.7.1
[0.5.0]: https://github.com/kawaz/unicodegrapheme.mbt/compare/v0.1.0...v0.5.0
[0.1.0]: https://github.com/kawaz/unicodegrapheme.mbt/releases/tag/v0.1.0

English | [日本語](README-ja.md)

# grapheme

[![CI](https://github.com/kawaz/grapheme.mbt/actions/workflows/ci.yml/badge.svg)](https://github.com/kawaz/grapheme.mbt/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Unicode 17.0.0](https://img.shields.io/badge/Unicode-17.0.0-blue.svg)](https://unicode.org/versions/Unicode17.0.0/)
[![UAX #29 compliant](https://img.shields.io/badge/UAX%20%2329-compliant-brightgreen.svg)](https://unicode.org/reports/tr29/)

`"👨‍👩‍👧‍👦".length()` returns 11 in MoonBit — this library makes it return 1.

## Overview

MoonBit's String uses UTF-16 internal representation, so `length()` and `str[i]` operate at the UTF-16 code unit level.
This library provides APIs for safely manipulating strings at the grapheme cluster level (the unit humans perceive as a single "character"), based on the **default extended grapheme cluster** rules in [UAX #29](https://unicode.org/reports/tr29/) (Unicode Text Segmentation). Locale-specific tailored rules are not supported.

- Zero dependencies
- Backends: wasm-gc, js, native
- Bundle size: wasm-gc ~25 KB / js ~59 KB / native ~56 KB
- Random access and slicing (unique among grapheme segmentation libraries)

| Layer | Problem | Solution |
|-------|---------|----------|
| L1: UTF-16 encoding | `str[i]` operates at code unit level | MoonBit core `iter()` |
| **L2: Grapheme cluster** | Composite emoji span multiple code points | **This library** |
| L3: Display width | Full-width / half-width display widths | `rami3l/unicodewidth` |

All GB rules (GB3-GB13, GB999) from Unicode 17.0.0 are implemented as a state machine, passing all 766 official test cases.

## Install

```
moon add kawaz/grapheme
```

Add the dependency to your package's `moon.pkg`:

```
import {
  "kawaz/grapheme",
}
```

<details>
<summary>JSON format (moon.pkg.json)</summary>

```json
{
  "import": ["kawaz/grapheme"]
}
```

</details>

## Usage

```moonbit
// Correct grapheme cluster counting
let family = @grapheme.graphemes("👨‍👩‍👧‍👦")
println(family.length())  // 1

// Split, access, and slice
let view = @grapheme.graphemes("Hello🇯🇵World")
println(view.length())  // 11 (H,e,l,l,o,🇯🇵,W,o,r,l,d)
println(view[5].to_string())  // "🇯🇵"
println(view[1:3].to_string())  // "el" (slice)

// Iteration
for cluster in view {
  println(cluster)
}

// Lazy evaluation: fast when you only need the first few clusters
let first = @grapheme.grapheme_iter("very long text...").head()
```

`graphemes()` pre-scans the entire string to provide random access and slicing. O(n) full scan + O(k) memory (k = cluster count).

`grapheme_iter()` starts in O(1) with no pre-scan. Use it when you only need the first N clusters.

## API

[API Documentation](https://mooncakes.io/docs/kawaz/grapheme)

> **Note:** `==` comparison is based on code point sequences. Unicode normalization (NFC/NFD) is not considered, so precomposed and decomposed forms of the same character are treated as different GraphemeViews.

## Features

- UAX #29 Grapheme Cluster Break state machine implementation
- `Extended_Pictographic` property support
- Composite emoji support (ZWJ sequences, flags, skin tone modifiers)
- Published on mooncakes.io
- Two-level lookup table for O(1) property determination
- Safe access (`get`), `Show`/`Eq`/`Hash` traits, `is_empty`, `to_string`
- Slice operations (`view[1:3]`)
- Extended iteration (`rev_iter`, `iter2`, `grapheme_indices`)
- Lazy iterator `grapheme_iter()` — up to 64x faster for early-break use cases

## Unicode Version

Target: Unicode 17.0.0

## License

MIT License - Yoshiaki Kawazu (@kawaz)

English | [日本語](README-ja.md)

# unicodegrapheme

[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Unicode 17.0.0](https://img.shields.io/badge/Unicode-17.0.0-blue.svg)](https://unicode.org/versions/Unicode17.0.0/)
[![UAX #29 compliant](https://img.shields.io/badge/UAX%20%2329-compliant-brightgreen.svg)](https://unicode.org/reports/tr29/)

`"👨‍👩‍👧‍👦".length()` returns 11 in MoonBit — this library makes it return 1.

## Overview

MoonBit's String uses UTF-16 internal representation, so `length()` and `str[i]` operate at the UTF-16 code unit level.
This library provides APIs for safely manipulating strings at the grapheme cluster level (the unit humans perceive as a single "character"), based on [UAX #29](https://unicode.org/reports/tr29/) (Unicode Text Segmentation).

| Layer | Problem | Solution |
|-------|---------|----------|
| L1: UTF-16 encoding | `str[i]` operates at code unit level | MoonBit core `iter()` |
| **L2: Grapheme cluster** | Composite emoji span multiple code points | **This library** |
| L3: Display width | Full-width / half-width display widths | `rami3l/unicodewidth` |

All GB rules (GB3-GB13, GB999) from Unicode 17.0.0 are implemented as a state machine, passing all 766 official test cases.

## Install

```
moon add kawaz/unicodegrapheme
```

## Usage

```moonbit
// Basic: split and access by grapheme cluster
let view = @unicodegrapheme.graphemes("Hello🇯🇵World")
println(view.length())  // 11 (number of grapheme clusters)
println(view[5].to_string())  // "🇯🇵"
println(view[1:3].to_string())  // "el" (slice)

// Iteration
for cluster in view {
  println(cluster)
}

// Lazy evaluation: fast when you only need the first few clusters
let first = @unicodegrapheme.grapheme_iter("very long text...").head()
```

## API

[API Documentation](https://mooncakes.io/docs/kawaz/unicodegrapheme)

## Roadmap

- [x] UAX #29 Grapheme Cluster Break state machine implementation
- [x] `Extended_Pictographic` property support
- [x] Composite emoji support (ZWJ sequences, flags, skin tone modifiers)
- [x] Publish to mooncakes.io
- [x] ASCII fast path optimization
- [x] Safe access (`get`), `Show`/`Eq`/`Hash` traits, `is_empty`, `to_string`
- [x] Slice operations (`view[1:3]`)
- [x] Extended iteration (`rev_iter`, `iter2`, `grapheme_indices`)
- [x] Lazy iterator `grapheme_iter()` — up to 64x faster for early-break use cases

## Unicode Version

Target: Unicode 17.0.0

## License

MIT License - Yoshiaki Kawazu (@kawaz)

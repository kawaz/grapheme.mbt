English | [日本語](README-ja.md)

# unicodegrapheme

Unicode grapheme cluster segmentation library for MoonBit.

## Overview

MoonBit's String uses UTF-16 internal representation, so `length()` and `str[i]` operate at the UTF-16 code unit level.
This library provides APIs for safely manipulating strings at the grapheme cluster level, based on UAX #29 (Unicode Text Segmentation).

## Status

**UAX #29 compliant grapheme cluster segmentation is fully implemented**. All GB rules (GB3-GB13, GB999) from Unicode 16.0.0 are implemented as a state machine, passing all 1,093 official test cases.

## Install

```
moon add kawaz/unicodegrapheme
```

## Usage

```moonbit
let view = @unicodegrapheme.graphemes("Hello🇯🇵World")
println(view.length())  // number of grapheme clusters
println(view[5].to_string())  // "🇯🇵"

for cluster in view.iter() {
  println(cluster)
}
```

## API

### `graphemes(s: String) -> GraphemeView`

Returns a `GraphemeView` that splits the string into grapheme cluster units.

### `GraphemeView::length() -> Int`

Returns the number of grapheme clusters.

### `GraphemeView::op_get(i: Int) -> StringView`

Returns the i-th grapheme cluster as a `StringView`. Zero-copy.

### `GraphemeView::iter() -> Iter[StringView]`

Iterates over grapheme clusters in order.

## Roadmap

- [x] UAX #29 Grapheme Cluster Break state machine implementation
- [x] `Extended_Pictographic` property support
- [x] Composite emoji support (ZWJ sequences, flags, skin tone modifiers)
- [ ] Slice operations (`view[1:3]`)
- [ ] Publish to mooncakes.io

## Unicode Version

Target: Unicode 16.0.0

## License

MIT License - Yoshiaki Kawazu (@kawaz)

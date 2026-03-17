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

### `GraphemeView::get(i: Int) -> StringView?`

Safe access to the i-th grapheme cluster. Returns `None` if out of range.

### `GraphemeView::iter() -> Iter[StringView]`

Iterates over grapheme clusters in order. Supports `for cluster in view { ... }`.

### `GraphemeView::is_empty() -> Bool`

Returns `true` if there are no grapheme clusters.

### `GraphemeView::op_as_view(start?: Int, end?: Int) -> GraphemeView`

Slice operation. Supports `view[1:3]` syntax. Returns a new `GraphemeView` for the specified range.

### `GraphemeView::iter2() -> Iter2[Int, StringView]`

Indexed iteration. Supports `for (i, cluster) in view { ... }`.

### `GraphemeView::rev_iter() -> Iter[StringView]`

Reverse iteration over grapheme clusters.

### `GraphemeView::to_string() -> String`

Returns the original source string.

### `GraphemeView::grapheme_indices() -> Iter[(Int, Int, StringView)]`

Iterates over grapheme clusters with their UTF-16 byte offsets. Yields `(start_offset, end_offset, cluster)`.

### `impl Eq for GraphemeView`

Equality comparison. Two `GraphemeView`s are equal if they have the same number of clusters and each corresponding cluster has the same string content. Supports `==` operator.

### `impl Hash for GraphemeView`

Hash support. Equal `GraphemeView`s produce equal hashes. Can be used as `HashMap` keys via `to_string()`.

## Roadmap

- [x] UAX #29 Grapheme Cluster Break state machine implementation
- [x] `Extended_Pictographic` property support
- [x] Composite emoji support (ZWJ sequences, flags, skin tone modifiers)
- [x] Publish to mooncakes.io
- [x] ASCII fast path optimization
- [x] Safe access (`get`), `Show` trait, `is_empty`, `to_string`
- [x] Slice operations (`view[1:3]`)

## Unicode Version

Target: Unicode 16.0.0

## License

MIT License - Yoshiaki Kawazu (@kawaz)

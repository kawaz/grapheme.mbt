///|
/// A view type that holds Unicode grapheme cluster boundary information.
/// Each grapheme cluster can be accessed as a zero-copy slice of the original String.
pub struct GraphemeView {
  priv source : String
  priv boundaries : Array[Int] // start offset of each cluster (last element is the string end)
}

///|
/// Returns a GraphemeView that splits the string into grapheme cluster units.
/// Implements UAX #29 GB rules as a state machine.
pub fn graphemes(s : String) -> GraphemeView {
  let boundaries : Array[Int] = []
  let mut offset = 0
  let mut prev_gcb : GCBCategory? = None
  let mut ri_count = 0
  let mut emoji_state : EmojiState = ES_None
  let mut incb_state : InCBState = IC_None
  for ch in s {
    let cp = ch.to_int()
    let cur_gcb = gcb_category(cp)
    // GB1: sot ÷ Any -- first code point is unconditionally a boundary
    let is_boundary = match prev_gcb {
      None => true
      Some(prev) => check_boundary(prev, cur_gcb, ri_count, emoji_state, incb_state)
    }
    if is_boundary {
      boundaries.push(offset)
    }
    // State updates
    ri_count = if cur_gcb == Regional_Indicator { ri_count + 1 } else { 0 }
    emoji_state = next_emoji_state(emoji_state, cur_gcb)
    incb_state = next_incb_state(incb_state, cur_gcb, cp)
    // Update prev_gcb
    prev_gcb = Some(cur_gcb)
    // Design rationale: MoonBit's String uses UTF-16 encoding internally.
    // BMP (U+0000..U+FFFF) uses 1 code unit, above that uses surrogate pairs (2 code units).
    offset = offset + (if cp >= 0x10000 { 2 } else { 1 })
  }
  // GB2: Any ÷ eot -- end of string
  if boundaries.length() > 0 {
    boundaries.push(offset)
  }
  { source: s, boundaries }
}

///|
/// Returns the number of grapheme clusters.
pub fn GraphemeView::length(self : GraphemeView) -> Int {
  if self.boundaries.length() <= 1 {
    0
  } else {
    self.boundaries.length() - 1
  }
}

///|
/// Returns the i-th grapheme cluster as a StringView.
/// Panics if i is not in the range 0 <= i < length().
pub fn GraphemeView::op_get(
  self : GraphemeView,
  i : Int
) -> StringView {
  let start = self.boundaries[i]
  let end = self.boundaries[i + 1]
  self.source.view(start_offset=start, end_offset=end)
}

///|
/// Iterates over grapheme clusters in order.
pub fn GraphemeView::iter(self : GraphemeView) -> Iter[StringView] {
  let len = self.length()
  let mut i = 0
  Iter::new(fn() {
    if i >= len {
      None
    } else {
      let result = self[i]
      i += 1
      Some(result)
    }
  })
}

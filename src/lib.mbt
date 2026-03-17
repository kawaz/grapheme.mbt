///|
/// A view type that holds Unicode grapheme cluster boundary information.
/// Each grapheme cluster can be accessed as a zero-copy slice of the original String.
/// Supports slicing via `cluster_start` and `cluster_end` indices into the boundaries array.
pub struct GraphemeView {
  priv source : String
  priv boundaries : Array[Int] // start offset of each cluster (last element is the string end)
  priv cluster_start : Int // index into boundaries for the first cluster (inclusive)
  priv cluster_end : Int // index into boundaries for the end cluster (exclusive)
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
      Some(prev) =>
        check_boundary(prev, cur_gcb, ri_count, emoji_state, incb_state)
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
  let cluster_end = if boundaries.length() > 1 {
    boundaries.length() - 1
  } else {
    0
  }
  { source: s, boundaries, cluster_start: 0, cluster_end }
}

///|
/// Returns the number of grapheme clusters.
pub fn GraphemeView::length(self : GraphemeView) -> Int {
  self.cluster_end - self.cluster_start
}

///|
/// Returns the i-th grapheme cluster as a StringView.
/// Panics if i is not in the range 0 <= i < length().
pub fn GraphemeView::op_get(self : GraphemeView, i : Int) -> StringView {
  let start = self.boundaries[self.cluster_start + i]
  let end = self.boundaries[self.cluster_start + i + 1]
  self.source.view(start_offset=start, end_offset=end)
}

///|
/// Returns the i-th grapheme cluster as an Option, or None if out of range.
pub fn GraphemeView::get(self : GraphemeView, i : Int) -> StringView? {
  if i < 0 || i >= self.length() {
    None
  } else {
    Some(self[i])
  }
}

///|
/// Returns true if there are no grapheme clusters.
pub fn GraphemeView::is_empty(self : GraphemeView) -> Bool {
  self.length() == 0
}

///|
/// Returns the string content of this view (may be a substring if sliced).
pub fn GraphemeView::to_string(self : GraphemeView) -> String {
  if self.length() == 0 {
    ""
  } else {
    self.source
    .view(
      start_offset=self.boundaries[self.cluster_start],
      end_offset=self.boundaries[self.cluster_end],
    )
    .to_string()
  }
}

///|
/// Implements Show trait for GraphemeView.
/// Output format: GraphemeView(["cluster1", "cluster2", ...])
pub impl Show for GraphemeView with output(self, logger) {
  logger.write_string("GraphemeView([")
  let len = self.length()
  for i = 0; i < len; i = i + 1 {
    if i > 0 {
      logger.write_string(", ")
    }
    logger.write_string("\"")
    logger.write_string(self[i].to_string())
    logger.write_string("\"")
  }
  logger.write_string("])")
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

///|
/// Returns a sliced GraphemeView. Enables `view[start:end]` syntax.
pub fn GraphemeView::op_as_view(
  self : GraphemeView,
  start? : Int,
  end? : Int,
) -> GraphemeView {
  let len = self.length()
  let s = match start {
    None => 0
    Some(v) => if v < 0 { 0 } else if v > len { len } else { v }
  }
  let e = match end {
    None => len
    Some(v) => if v < s { s } else if v > len { len } else { v }
  }
  {
    source: self.source,
    boundaries: self.boundaries,
    cluster_start: self.cluster_start + s,
    cluster_end: self.cluster_start + e,
  }
}

///|
/// Iterates over grapheme clusters with their indices.
pub fn GraphemeView::iter2(self : GraphemeView) -> Iter2[Int, StringView] {
  let len = self.length()
  let mut i = 0
  Iter2::new(fn() {
    if i >= len {
      None
    } else {
      let idx = i
      let cluster = self[idx]
      i += 1
      Some((idx, cluster))
    }
  })
}

///|
/// Two GraphemeViews are equal if they have the same number of clusters
/// and each corresponding cluster has the same string content.
pub impl Eq for GraphemeView with equal(self, other) {
  let len = self.length()
  if len != other.length() {
    return false
  }
  for i = 0; i < len; i = i + 1 {
    if self[i].to_string() != other[i].to_string() {
      return false
    }
  }
  true
}

///|
/// Implements Hash trait for GraphemeView.
/// Uses the string content of the view as the hash source, consistent with Eq.
pub impl Hash for GraphemeView with hash_combine(self, hasher) {
  hasher.combine_string(self.to_string())
}

///|
/// Iterates over grapheme clusters with their UTF-16 byte offsets.
/// Yields (start_offset, end_offset, cluster) for each grapheme cluster.
/// Note: For sliced GraphemeViews, offsets refer to positions in the original source string.
pub fn GraphemeView::grapheme_indices(
  self : GraphemeView,
) -> Iter[(Int, Int, StringView)] {
  let len = self.length()
  let mut i = 0
  Iter::new(fn() {
    if i >= len {
      None
    } else {
      let start = self.boundaries[self.cluster_start + i]
      let end = self.boundaries[self.cluster_start + i + 1]
      let cluster = self.source.view(start_offset=start, end_offset=end)
      i += 1
      Some((start, end, cluster))
    }
  })
}

///|
/// Iterates over grapheme clusters in reverse order.
pub fn GraphemeView::rev_iter(self : GraphemeView) -> Iter[StringView] {
  let mut i = self.length() - 1
  Iter::new(fn() {
    if i < 0 {
      None
    } else {
      let result = self[i]
      i -= 1
      Some(result)
    }
  })
}

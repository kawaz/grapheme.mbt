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
/// Note: This function scans the entire string upfront (O(n) preprocessing).
/// For lazy evaluation, use grapheme_iter() instead.
pub fn graphemes(s : String) -> GraphemeView {
  let boundaries : Array[Int] = []
  let state = SegmenterState::new()
  let mut offset = 0
  for ch in s {
    let cp = ch.to_int()
    if state.next(cp) {
      boundaries.push(offset)
    }
    // MoonBit's String uses UTF-16: BMP = 1 code unit, non-BMP = 2 (surrogate pair)
    offset = offset + (if cp >= 0x10000 { 2 } else { 1 })
  }
  // GB2: Any ÷ eot
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
/// Returns a lazy iterator that yields grapheme clusters one at a time
/// without preprocessing the entire string.
/// Use this when you only need the first few clusters of a long string.
/// For random access or repeated iteration, use graphemes() instead.
pub fn grapheme_iter(s : String) -> Iter[StringView] {
  let len = s.length() // UTF-16 code unit count
  let mut offset = 0
  let state = SegmenterState::new()
  let mut cluster_start = 0
  let mut started = false
  let mut done = false
  Iter::new(fn() {
    if done {
      return None
    }
    while offset < len {
      // Decode one code point from UTF-16
      let unit = s.at(offset).to_int()
      let (cp, cp_len) = if unit >= 0xD800 &&
        unit <= 0xDBFF &&
        offset + 1 < len {
        let lo = s.at(offset + 1).to_int()
        if lo >= 0xDC00 && lo <= 0xDFFF {
          ((unit - 0xD800) * 0x400 + (lo - 0xDC00) + 0x10000, 2)
        } else {
          (unit, 1) // lone high surrogate
        }
      } else {
        (unit, 1)
      }
      let is_boundary = state.next(cp)
      if is_boundary && started {
        let view = s.view(start_offset=cluster_start, end_offset=offset)
        cluster_start = offset
        offset = offset + cp_len
        return Some(view)
      }
      if is_boundary {
        cluster_start = offset
        started = true
      }
      offset = offset + cp_len
    }
    if started {
      done = true
      Some(s.view(start_offset=cluster_start, end_offset=offset))
    } else {
      None
    }
  })
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
/// Negative start is clamped to 0. End beyond length is clamped to length.
/// If end < start, an empty view is returned.
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
/// Iterates over grapheme clusters with their 0-based cluster indices (not byte offsets).
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
/// Compares by code point sequence, not Unicode canonical equivalence (NFC/NFD).
pub impl Eq for GraphemeView with equal(self, other) {
  let len = self.length()
  if len != other.length() {
    return false
  }
  for i = 0; i < len; i = i + 1 {
    if self[i] != other[i] {
      return false
    }
  }
  true
}

///|
/// Implements Hash trait for GraphemeView.
/// Hashes character content directly without String allocation, consistent with Eq.
pub impl Hash for GraphemeView with hash_combine(self, hasher) {
  if self.length() > 0 {
    let view = self.source.view(
      start_offset=self.boundaries[self.cluster_start],
      end_offset=self.boundaries[self.cluster_end],
    )
    for ch in view {
      hasher.combine_int(ch.to_int())
    }
  }
}

///|
/// Iterates over grapheme clusters with their UTF-16 code unit offsets.
/// Yields (start_offset, end_offset, cluster) for each grapheme cluster.
/// Offsets are compatible with `String` indexing methods.
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
  let len = self.length()
  let mut i = len
  Iter::new(fn() {
    if i <= 0 {
      None
    } else {
      i -= 1
      Some(self[i])
    }
  })
}

///|
/// Unicode UAX #29 Grapheme Cluster Break (GCB) category.
/// Assigned to each code point and used for grapheme cluster boundary determination.
priv enum GCBCategory {
  Other
  CR
  LF
  Control
  Extend
  ZWJ
  Regional_Indicator
  Prepend
  SpacingMark
  L // Hangul Leading Jamo
  V // Hangul Vowel Jamo
  T // Hangul Trailing Jamo
  LV // Hangul LV Syllable
  LVT // Hangul LVT Syllable
  Extended_Pictographic
  InCB_Consonant
} derive(Eq, Show)

///|
/// Returns the GCB category for a code point (returns Other if not in the table).
fn gcb_category(cp : Int) -> GCBCategory {
  // ASCII fast path: 0x20..0x7E are all Other (printable ASCII range).
  // This avoids binary search for the most common code points in typical text.
  if cp >= 0x20 && cp <= 0x7E {
    return Other
  }
  let mut lo = 0
  let mut hi = gcb_table.length() - 1
  while lo <= hi {
    let mid = (lo + hi) / 2
    let (start, end, cat) = gcb_table[mid]
    if cp < start {
      hi = mid - 1
    } else if cp > end {
      lo = mid + 1
    } else {
      return cat
    }
  }
  Other
}

///|
/// Returns whether the code point is InCB=Linker.
fn is_incb_linker(cp : Int) -> Bool {
  let mut lo = 0
  let mut hi = incb_linker_table.length() - 1
  while lo <= hi {
    let mid = (lo + hi) / 2
    let v = incb_linker_table[mid]
    if cp < v {
      hi = mid - 1
    } else if cp > v {
      lo = mid + 1
    } else {
      return true
    }
  }
  false
}

///|
/// Returns whether the code point is InCB=Extend.
fn is_incb_extend(cp : Int) -> Bool {
  let mut lo = 0
  let mut hi = incb_extend_table.length() - 1
  while lo <= hi {
    let mid = (lo + hi) / 2
    let (start, end) = incb_extend_table[mid]
    if cp < start {
      hi = mid - 1
    } else if cp > end {
      lo = mid + 1
    } else {
      return true
    }
  }
  false
}

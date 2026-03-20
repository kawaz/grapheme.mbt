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
} derive(Eq)

///|
/// Returns the GCB category for a code point using two-stage table lookup.
/// O(1) constant time — two array accesses + bit operations.
///
/// The two-stage table covers Plane 0-2 (U+0000..U+02FFFF).
/// Plane 14 Tags are handled by branch logic:
///   E0000-E001F, E0080-E00FF, E01F0-E0FFF: Control
///   E0020-E007F, E0100-E01EF: Extend
/// Planes 3-13 and 15-16 are all Other.
fn gcb_category(cp : Int) -> GCBCategory {
  if cp <= 0x02FFFF {
    // Plane 0-2: two-stage table lookup
    let block_idx = gcb_stage1[cp >> 8]
    let offset = cp & 0xFF
    let byte_val = gcb_stage2[block_idx.to_int() * 128 + (offset >> 1)]
    let nibble = if (offset & 1) == 0 {
      byte_val.to_int() >> 4
    } else {
      byte_val.to_int() & 0xF
    }
    match nibble {
      1 => CR
      2 => LF
      3 => Control
      4 => Extend
      5 => ZWJ
      6 => Regional_Indicator
      7 => Prepend
      8 => SpacingMark
      9 => L
      10 => V
      11 => T
      12 => LV
      13 => LVT
      14 => Extended_Pictographic
      15 => InCB_Consonant
      _ => Other
    }
  } else if cp >= 0xE0020 && cp <= 0xE007F {
    Extend // Tag characters (emoji tag sequences)
  } else if cp >= 0xE0100 && cp <= 0xE01EF {
    Extend // Variation selectors supplement
  } else if cp >= 0xE0000 && cp <= 0xE0FFF {
    Control // Other Plane 14 Tags (E0000-E001F, E0080-E00FF, E01F0-E0FFF)
  } else {
    Other // Planes 3-13, 15-16
  }
}

///|
/// Returns whether the code point is InCB=Linker.
/// Uses packed Bytes table (3 bytes per codepoint, big-endian, binary search).
fn is_incb_linker(cp : Int) -> Bool {
  let entry_size = 3
  let count = incb_linker_packed.length() / entry_size
  let mut lo = 0
  let mut hi = count - 1
  while lo <= hi {
    let mid = (lo + hi) / 2
    let base = mid * entry_size
    let val = (incb_linker_packed[base].to_int() << 16) |
      (incb_linker_packed[base + 1].to_int() << 8) |
      incb_linker_packed[base + 2].to_int()
    if cp < val {
      hi = mid - 1
    } else if cp > val {
      lo = mid + 1
    } else {
      return true
    }
  }
  false
}

///|
/// Returns whether the code point is InCB=Extend.
/// Uses packed Bytes table (6 bytes per range: start 3B + end 3B, big-endian, binary search).
fn is_incb_extend(cp : Int) -> Bool {
  let entry_size = 6
  let count = incb_extend_packed.length() / entry_size
  let mut lo = 0
  let mut hi = count - 1
  while lo <= hi {
    let mid = (lo + hi) / 2
    let base = mid * entry_size
    let start = (incb_extend_packed[base].to_int() << 16) |
      (incb_extend_packed[base + 1].to_int() << 8) |
      incb_extend_packed[base + 2].to_int()
    let end = (incb_extend_packed[base + 3].to_int() << 16) |
      (incb_extend_packed[base + 4].to_int() << 8) |
      incb_extend_packed[base + 5].to_int()
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

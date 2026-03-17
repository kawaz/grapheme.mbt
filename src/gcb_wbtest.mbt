test "gcb_category: ASCII letter -> Other" {
  inspect(gcb_category(0x41), content="Other")  // 'A'
}

test "gcb_category: LF -> LF" {
  inspect(gcb_category(0x0A), content="LF")
}

test "gcb_category: CR -> CR" {
  inspect(gcb_category(0x0D), content="CR")
}

test "gcb_category: Control (NUL) -> Control" {
  inspect(gcb_category(0x00), content="Control")
}

test "gcb_category: Combining Grave Accent -> Extend" {
  inspect(gcb_category(0x0300), content="Extend")
}

test "gcb_category: ZWJ -> ZWJ" {
  inspect(gcb_category(0x200D), content="ZWJ")
}

test "gcb_category: Regional Indicator A -> Regional_Indicator" {
  inspect(gcb_category(0x1F1E6), content="Regional_Indicator")
}

test "gcb_category: Grinning Face -> Extended_Pictographic" {
  inspect(gcb_category(0x1F600), content="Extended_Pictographic")
}

test "gcb_category: Hangul L -> L" {
  inspect(gcb_category(0x1100), content="L")
}

test "gcb_category: Hangul V -> V" {
  inspect(gcb_category(0x1161), content="V")
}

test "gcb_category: Hangul T -> T" {
  inspect(gcb_category(0x11A8), content="T")
}

test "gcb_category: Hangul LV syllable -> LV" {
  inspect(gcb_category(0xAC00), content="LV")
}

test "gcb_category: Hangul LVT syllable -> LVT" {
  inspect(gcb_category(0xAC01), content="LVT")
}

test "gcb_category: Prepend (Arabic Number Sign) -> Prepend" {
  inspect(gcb_category(0x0600), content="Prepend")
}

test "gcb_category: SpacingMark (Devanagari AA) -> SpacingMark" {
  inspect(gcb_category(0x093E), content="SpacingMark")
}

test "gcb_category: InCB_Consonant (Devanagari Ka) -> InCB_Consonant" {
  inspect(gcb_category(0x0915), content="InCB_Consonant")
}

// Edge cases
test "gcb_category: range boundary start (first Control range)" {
  inspect(gcb_category(0x00), content="Control")
}

test "gcb_category: range boundary end" {
  inspect(gcb_category(0x09), content="Control")
}

test "gcb_category: just above range (space)" {
  inspect(gcb_category(0x20), content="Other")
}

test "gcb_category: max codepoint" {
  // 0x10FFFF is beyond gcb_table's last entry (0xe0fff), so Other
  inspect(gcb_category(0x10FFFF), content="Other")
}

// InCB auxiliary table tests
test "is_incb_linker: Devanagari Virama" {
  inspect(is_incb_linker(0x094D), content="true")
}

test "is_incb_linker: non-linker" {
  inspect(is_incb_linker(0x0041), content="false")
}

test "is_incb_extend: Devanagari extending mark" {
  // 0x0900 is within incb_extend_table range (0x8e3, 0x902)
  inspect(is_incb_extend(0x0900), content="true")
}

test "is_incb_extend: non-extend" {
  inspect(is_incb_extend(0x0041), content="false")
}

// ============================================================
// ASCII fast path tests
// ============================================================

test "gcb_category: ASCII fast path space" {
  inspect(gcb_category(0x20), content="Other")
}

test "gcb_category: ASCII fast path tilde" {
  inspect(gcb_category(0x7E), content="Other")
}

test "gcb_category: ASCII fast path 0x7F is Control" {
  inspect(gcb_category(0x7F), content="Control")
}

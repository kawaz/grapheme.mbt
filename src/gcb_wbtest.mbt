// ============================================================================
// Scope of this test file (white-box tests for GCB category classification)
// ============================================================================
//
// In scope:
//   - gcb_category(cp) at boundary code points: plane boundaries, the two-stage
//     stage1 transition points, and neighbor code points straddling adjacent
//     GCB categories. The goal is to pin down where one category ends and the
//     next begins so off-by-one errors in the stage1/stage2 tables surface
//     immediately.
//   - is_incb_consonant / is_incb_linker / is_incb_extend: the packed-Bytes
//     binary-search bounds (first entry, last entry, the gap between adjacent
//     entries, and the code points just outside the search range). These cases
//     guard the hand-rolled binary search against off-by-one bugs.
//   - Plane 14 ordering boundary code points: the cp ordering used by the
//     Plane 14 tag-sequence classifier is fragile, so its boundaries get
//     dedicated coverage here.
//
// Not applicable (covered elsewhere):
//   - GB1..GB999 segmentation rule behaviour: lives in segmenter_wbtest.mbt
//     (white-box state-machine coverage) and src/uax29_test.mbt (the generated
//     UAX #29 conformance corpus).
//   - Public API surface (iterators, factory helpers, exported types): lives
//     in lib_wbtest.mbt.
//   - End-to-end Plane 14 cluster cases (full tag_base + tag_spec + term
//     sequences as observed at the cluster level): lives in
//     plane14_tags_test.mbt.
//
// DR-0007 — test-scope split rationale.
// ============================================================================

// Show impl for GCBCategory (test-only, mirrors derive(Show) output)

///|
impl Show for GCBCategory with fn output(self, logger) {
  logger.write_string(
    match self {
      Other => "Other"
      CR => "CR"
      LF => "LF"
      Control => "Control"
      Extend => "Extend"
      ZWJ => "ZWJ"
      Regional_Indicator => "Regional_Indicator"
      Prepend => "Prepend"
      SpacingMark => "SpacingMark"
      L => "L"
      V => "V"
      T => "T"
      LV => "LV"
      LVT => "LVT"
      Extended_Pictographic => "Extended_Pictographic"
      InCB_Consonant => "InCB_Consonant"
    },
  )
}

///|
test "gcb_category: ASCII letter -> Other" {
  inspect(gcb_category(0x41), content="Other") // 'A'
}

///|
test "gcb_category: LF -> LF" {
  inspect(gcb_category(0x0A), content="LF")
}

///|
test "gcb_category: CR -> CR" {
  inspect(gcb_category(0x0D), content="CR")
}

///|
test "gcb_category: Control (NUL) -> Control" {
  inspect(gcb_category(0x00), content="Control")
}

///|
test "gcb_category: Combining Grave Accent -> Extend" {
  inspect(gcb_category(0x0300), content="Extend")
}

///|
test "gcb_category: ZWJ -> ZWJ" {
  inspect(gcb_category(0x200D), content="ZWJ")
}

///|
test "gcb_category: Regional Indicator A -> Regional_Indicator" {
  inspect(gcb_category(0x1F1E6), content="Regional_Indicator")
}

///|
test "gcb_category: Grinning Face -> Extended_Pictographic" {
  inspect(gcb_category(0x1F600), content="Extended_Pictographic")
}

///|
test "gcb_category: Hangul L -> L" {
  inspect(gcb_category(0x1100), content="L")
}

///|
test "gcb_category: Hangul V -> V" {
  inspect(gcb_category(0x1161), content="V")
}

///|
test "gcb_category: Hangul T -> T" {
  inspect(gcb_category(0x11A8), content="T")
}

///|
test "gcb_category: Hangul LV syllable -> LV" {
  inspect(gcb_category(0xAC00), content="LV")
}

///|
test "gcb_category: Hangul LVT syllable -> LVT" {
  inspect(gcb_category(0xAC01), content="LVT")
}

///|
test "gcb_category: Prepend (Arabic Number Sign) -> Prepend" {
  inspect(gcb_category(0x0600), content="Prepend")
}

///|
test "gcb_category: SpacingMark (Devanagari AA) -> SpacingMark" {
  inspect(gcb_category(0x093E), content="SpacingMark")
}

///|
test "gcb_category: InCB_Consonant (Devanagari Ka) -> InCB_Consonant" {
  inspect(gcb_category(0x0915), content="InCB_Consonant")
}

// Edge cases

///|
test "gcb_category: range boundary start (first Control range)" {
  inspect(gcb_category(0x00), content="Control")
}

///|
test "gcb_category: range boundary end" {
  inspect(gcb_category(0x09), content="Control")
}

///|
test "gcb_category: just above range (space)" {
  inspect(gcb_category(0x20), content="Other")
}

///|
test "gcb_category: max codepoint" {
  // 0x10FFFF is beyond gcb_table's last entry (0xe0fff), so Other
  inspect(gcb_category(0x10FFFF), content="Other")
}

// InCB auxiliary table tests

///|
test "is_incb_linker: Devanagari Virama" {
  inspect(is_incb_linker(0x094D), content="true")
}

///|
test "is_incb_linker: non-linker" {
  inspect(is_incb_linker(0x0041), content="false")
}

///|
test "is_incb_extend: Devanagari extending mark" {
  // 0x0900 is within incb_extend_table range (0x8e3, 0x902)
  inspect(is_incb_extend(0x0900), content="true")
}

///|
test "is_incb_extend: non-extend" {
  inspect(is_incb_extend(0x0041), content="false")
}

// ============================================================
// ASCII range tests
// ============================================================

///|
test "gcb_category: ASCII space" {
  inspect(gcb_category(0x20), content="Other")
}

///|
test "gcb_category: ASCII tilde" {
  inspect(gcb_category(0x7E), content="Other")
}

///|
test "gcb_category: 0x7F is Control" {
  inspect(gcb_category(0x7F), content="Control")
}

// ============================================================
// Special Unicode code point GCB category tests
// ============================================================

///|
test "gcb_category: U+FFFD (REPLACEMENT CHARACTER) -> Other" {
  inspect(gcb_category(0xFFFD), content="Other")
}

///|
test "gcb_category: U+FEFF (BOM / ZWNBSP) -> Control" {
  inspect(gcb_category(0xFEFF), content="Control")
}

///|
test "gcb_category: U+E000 (Private Use Area start) -> Other" {
  inspect(gcb_category(0xE000), content="Other")
}

///|
test "gcb_category: U+F8FF (Private Use Area end) -> Other" {
  inspect(gcb_category(0xF8FF), content="Other")
}

///|
test "gcb_category: U+FFFF (noncharacter) -> Other" {
  inspect(gcb_category(0xFFFF), content="Other")
}

///|
test "gcb_category: U+FFFE (noncharacter) -> Other" {
  inspect(gcb_category(0xFFFE), content="Other")
}

///|
test "gcb_category: U+FDD0 (noncharacter range start) -> Other" {
  inspect(gcb_category(0xFDD0), content="Other")
}

///|
test "gcb_category: U+FDEF (noncharacter range end) -> Other" {
  inspect(gcb_category(0xFDEF), content="Other")
}

///|
test "gcb_category: U+1FFFE (noncharacter in SMP) -> Other" {
  inspect(gcb_category(0x1FFFE), content="Other")
}

///|
test "gcb_category: U+1FFFF (noncharacter in SMP) -> Other" {
  inspect(gcb_category(0x1FFFF), content="Other")
}

///|
test "gcb_category: U+FFF0 -> Control" {
  inspect(gcb_category(0xFFF0), content="Control")
}

///|
test "gcb_category: U+FFFB -> Control" {
  inspect(gcb_category(0xFFFB), content="Control")
}

///|
test "gcb_category: U+FFFC (OBJECT REPLACEMENT CHARACTER) -> Other" {
  // U+FFFC is between U+FFFB (Control) and U+FFFD, not in gcb_table
  inspect(gcb_category(0xFFFC), content="Other")
}

// ============================================================
// Plane 14 branch boundary tests
// ============================================================

///|
test "gcb_category: U+E0000 -> Control (Plane 14 fallback)" {
  inspect(gcb_category(0xE0000), content="Control")
}

///|
test "gcb_category: U+E0001 -> Control" {
  inspect(gcb_category(0xE0001), content="Control")
}

///|
test "gcb_category: U+E001F -> Control (just before tag range)" {
  inspect(gcb_category(0xE001F), content="Control")
}

///|
test "gcb_category: U+E0020 -> Extend (tag range start)" {
  inspect(gcb_category(0xE0020), content="Extend")
}

///|
test "gcb_category: U+E007F -> Extend (tag range end)" {
  inspect(gcb_category(0xE007F), content="Extend")
}

///|
test "gcb_category: U+E0080 -> Control (after tag range)" {
  inspect(gcb_category(0xE0080), content="Control")
}

///|
test "gcb_category: U+E00FF -> Control (before variation selectors)" {
  inspect(gcb_category(0xE00FF), content="Control")
}

///|
test "gcb_category: U+E0100 -> Extend (variation selectors start)" {
  inspect(gcb_category(0xE0100), content="Extend")
}

///|
test "gcb_category: U+E01EF -> Extend (variation selectors end)" {
  inspect(gcb_category(0xE01EF), content="Extend")
}

///|
test "gcb_category: U+E01F0 -> Control (after variation selectors)" {
  inspect(gcb_category(0xE01F0), content="Control")
}

///|
test "gcb_category: U+E0FFF -> Control (Plane 14 end)" {
  inspect(gcb_category(0xE0FFF), content="Control")
}

///|
test "gcb_category: U+E1000 -> Other (beyond Plane 14 block)" {
  inspect(gcb_category(0xE1000), content="Other")
}

// ============================================================
// Plane 3+ fallthrough tests
// ============================================================

///|
test "gcb_category: U+30000 (Plane 3) -> Other" {
  inspect(gcb_category(0x30000), content="Other")
}

///|
test "gcb_category: U+F0000 (Plane 15, Supplementary PUA-A) -> Other" {
  inspect(gcb_category(0xF0000), content="Other")
}

// === Two-stage table & InCB packed-Bytes edge probes (DR-0007 scope) ===
//
// These probes pin down the exact code-point boundaries where the two-stage
// gcb_category table hands off (Plane 0 -> 1 -> 2 -> Plane 14 branch logic ->
// Other fallthrough), and the binary-search bounds for the InCB packed-Bytes
// tables (is_incb_linker / is_incb_extend). A regression on either end of a
// range can silently mis-classify whole planes or whole InCB ranges without
// failing the conformance corpus, so each cp below is chosen to expose one
// specific kind of off-by-one (table boundary, branch fallthrough, or
// binary-search lo/hi/equality bug).

// --- Two-stage table plane transitions ---

///|
// U+FFFF = Other (NOT A CHARACTER, Specials block in BMP).
// 0xFFFF is the last BMP code point. Verifies the Plane 0 stage1 entry for
// block 0xFF00..0xFFFF is reached and yields Other; a stage1-length off-by-one
// would either misclassify it or fall through to the Plane 14 / Other branch.
test "gcb_category: U+FFFF (last BMP cp) -> Other" {
  inspect(gcb_category(0xFFFF), content="Other")
}

///|
// U+10000 = Other (LINEAR B SYLLABLE B008 A, first cp of Plane 1).
// First cp past the BMP. Pinpoints the BMP -> Plane 1 transition: if stage1
// indexing wraps or the table stops at 0xFFFF, this lookup would either crash
// or return the wrong category.
test "gcb_category: U+10000 (first cp of Plane 1) -> Other" {
  inspect(gcb_category(0x10000), content="Other")
}

///|
// U+1FFFF = Other (unassigned, last cp of Plane 1).
// Last cp of Plane 1. Locks the upper end of Plane 1's stage1 coverage so a
// truncation at e.g. 0x1FF00 would surface here.
test "gcb_category: U+1FFFF (last cp of Plane 1) -> Other" {
  inspect(gcb_category(0x1FFFF), content="Other")
}

///|
// U+20000 = Other (CJK UNIFIED IDEOGRAPH-20000, first cp of Plane 2).
// First cp of Plane 2. Pinpoints the Plane 1 -> Plane 2 transition in the
// two-stage table.
test "gcb_category: U+20000 (first cp of Plane 2) -> Other" {
  inspect(gcb_category(0x20000), content="Other")
}

///|
// U+2FFFF = Other (unassigned, last cp covered by the two-stage table).
// Last cp inside the two-stage table's coverage window (Plane 0-2). Anything
// strictly above this falls through to the Plane 14 branch / default Other
// path, so a regression that extends the table's claimed range too far would
// land here first.
test "gcb_category: U+2FFFF (last cp in two-stage table) -> Other" {
  inspect(gcb_category(0x2FFFF), content="Other")
}

// --- Plane 3-16 fallthrough probes (Plane 14 branch / default Other) ---

///|
// U+30000 = Other (CJK UNIFIED IDEOGRAPH-30000, first cp of Plane 3).
// Pinpoints the Plane 3 fallthrough: above the two-stage table window but
// below the Plane 14 branch range, so it must hit the default Other arm of
// gcb_category. A miscoded `else if cp >= 0x30000` guard would surface here.
test "gcb_category: U+30000 (Plane 3 fallthrough) -> Other" {
  inspect(gcb_category(0x30000), content="Other")
}

///|
// U+F0000 = Other (first cp of Plane 15, Supplementary Private Use Area-A).
// Sits between the Plane 14 branch (E0000-E0FFF) and the upper PUA planes.
// Verifies Plane 14's branch logic does NOT bleed past 0xE0FFF into Plane 15;
// a `cp <= 0xF0FFF` typo on the Plane 14 guard would misclassify this.
test "gcb_category: U+F0000 (Plane 15 fallthrough) -> Other" {
  inspect(gcb_category(0xF0000), content="Other")
}

///|
// U+100000 = Other (first cp of Plane 16, Supplementary Private Use Area-B).
// Pinpoints the Plane 16 fallthrough. Combined with the Plane 15 case above,
// this locks both PUA planes into the default Other arm.
test "gcb_category: U+100000 (Plane 16 fallthrough) -> Other" {
  inspect(gcb_category(0x100000), content="Other")
}

// --- ZWJ vs ZWNJ neighbor (locks off-by-one between adjacent categories) ---

///|
// U+200C = Extend (ZERO WIDTH NON-JOINER).
// ZWNJ is Extend per UAX #29, immediately adjacent to ZWJ at U+200D. The
// audit flagged this neighbor pair as under-asserted: a stage2 lookup that
// shifted by one cp would swap these two classifications without breaking
// most cluster tests, so the pair is asserted explicitly here.
test "gcb_category: U+200C (ZWNJ) -> Extend" {
  inspect(gcb_category(0x200C), content="Extend")
}

///|
// U+200D = ZWJ (ZERO WIDTH JOINER).
// The cp immediately above ZWNJ. ZWJ has its own GCB category (drives the
// emoji ZWJ sequence rule GB11), so a one-cp drift between this and U+200C
// would corrupt every emoji ZWJ cluster - this assert nails the boundary.
test "gcb_category: U+200D (ZWJ) -> ZWJ" {
  inspect(gcb_category(0x200D), content="ZWJ")
}

// --- is_incb_linker packed-Bytes binary-search bounds ---

///|
// U+094D = InCB=Linker (DEVANAGARI SIGN VIRAMA).
// First entry of the is_incb_linker packed table. A regression in the binary
// search lower bound (e.g. starting lo at 1 instead of 0) would silently
// miss this entry, breaking every Devanagari Indic conjunct boundary.
test "is_incb_linker: U+094D first entry of packed table" {
  inspect(is_incb_linker(0x094D), content="true")
}

///|
// U+11F42 = InCB=Linker (DIVES AKURU SIGN HALANTA).
// Last entry of the is_incb_linker packed table. A regression in the upper
// bound (e.g. hi initialized to count-2) would silently miss this entry,
// breaking Dives Akuru Indic conjunct boundaries.
test "is_incb_linker: U+11F42 last entry of packed table" {
  inspect(is_incb_linker(0x11F42), content="true")
}

///|
// U+0ACD = InCB=Linker (GUJARATI SIGN VIRAMA).
// A cp that exactly equals an interior entry (not at either end). Exercises
// the binary-search equality branch in the middle of the table, distinct
// from the lo/hi edge probes above.
test "is_incb_linker: U+0ACD interior exact match" {
  inspect(is_incb_linker(0x0ACD), content="true")
}

///|
// U+094E = Other (DEVANAGARI VOWEL SIGN PRISHTHAMATRA E).
// Sits in the gap between adjacent linker entries U+094D and U+09CD. A
// binary-search bug that returned true for `cp > entry` on the wrong side
// would falsely classify this neighbor as a linker.
test "is_incb_linker: U+094E between entries -> false" {
  inspect(is_incb_linker(0x094E), content="false")
}

///|
// U+200000 = Other (far above the highest linker entry U+11F42).
// A high cp that must return false by exiting the search via `lo > hi`. If
// the loop termination condition were off (e.g. `lo < hi`), this could
// dereference past the table or return a stale result.
test "is_incb_linker: U+200000 above all entries -> false" {
  inspect(is_incb_linker(0x200000), content="false")
}

// --- is_incb_extend packed-Bytes binary-search bounds ---

///|
// U+0300 = InCB=Extend (COMBINING GRAVE ACCENT).
// First range start of the is_incb_extend packed table (range 0x0300..0x036F,
// Combining Diacritical Marks). A regression in the binary search lower
// bound silently misses this whole range, breaking every Latin combining
// mark cluster.
test "is_incb_extend: U+0300 first-range start" {
  inspect(is_incb_extend(0x0300), content="true")
}

///|
// U+036F = InCB=Extend (COMBINING LATIN SMALL LETTER X).
// Last cp of the FIRST extend range (0x0300..0x036F). Verifies the
// inclusive-end comparison (`cp <= end`) on the binary-search hit path; a
// `cp < end` typo would falsely classify the range endpoint as Other.
test "is_incb_extend: U+036F first-range inclusive end" {
  inspect(is_incb_extend(0x036F), content="true")
}

///|
// U+E01EF = InCB=Extend (VARIATION SELECTOR-256).
// Last range end of the entire is_incb_extend packed table
// (range 0xE0100..0xE01EF, Variation Selectors Supplement). Locks the upper
// search bound; a hi off-by-one would silently miss the final range.
test "is_incb_extend: U+E01EF last-range end" {
  inspect(is_incb_extend(0xE01EF), content="true")
}

///|
// U+0400 = Other (CYRILLIC CAPITAL LETTER IE WITH GRAVE).
// Sits in the gap between two adjacent extend ranges (after the first range
// ending at 0x036F and before the next range starting at 0x0483). A range
// boundary off-by-one would falsely include this cp in the extend set.
test "is_incb_extend: U+0400 between ranges -> false" {
  inspect(is_incb_extend(0x0400), content="false")
}

///|
// U+FFFFF = Other (unassigned, last cp of Plane 15).
// A high cp above every extend range. Exercises the `lo > hi` exit path of
// the binary search; a termination bug here could over-run the packed table
// or return stale data.
test "is_incb_extend: U+FFFFF above all ranges -> false" {
  inspect(is_incb_extend(0xFFFFF), content="false")
}

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
// U+0041 'A' (LATIN CAPITAL LETTER A) carries no GCB property in
// GraphemeBreakProperty.txt, so it must fall through to the implicit Other
// category. ASCII letters are the most common Other-class input; this case
// pins the default arm of gcb_category so a regression that began returning
// Extend / SpacingMark for plain letters would surface immediately.
test "gcb_category: ASCII letter -> Other" {
  inspect(gcb_category(0x41), content="Other") // 'A'
}

///|
// U+000A (LINE FEED) is the sole cp with GCB=LF per GraphemeBreakProperty.txt.
// LF has its own category so GB3 (CR x LF) and GB4 (Control / CR / LF ÷) can
// distinguish it from the surrounding C0 controls; this case pins the lookup
// at the single LF cp.
test "gcb_category: LF -> LF" {
  inspect(gcb_category(0x0A), content="LF")
}

///|
// U+000D (CARRIAGE RETURN) is the sole cp with GCB=CR per
// GraphemeBreakProperty.txt. CR is split out from the surrounding C0 controls
// specifically so GB3 (CR x LF, no break inside CRLF) can fire; this case
// pins the lookup at the single CR cp.
test "gcb_category: CR -> CR" {
  inspect(gcb_category(0x0D), content="CR")
}

///|
// U+0000 (NULL) is classified GCB=Control per GraphemeBreakProperty.txt and
// is the lowest cp in the Control range. Pins the bottom of the C0 Control
// span; a stage-table off-by-one at cp 0 would otherwise be invisible
// because cp 0 cannot be reached by under-shooting.
test "gcb_category: Control (NUL) -> Control" {
  inspect(gcb_category(0x00), content="Control")
}

///|
// U+0300 (COMBINING GRAVE ACCENT) is the first cp of the Combining
// Diacritical Marks block (U+0300..U+036F) and is GCB=Extend per
// GraphemeBreakProperty.txt. Pins a canonical Extend representative so any
// table change that misclassified combining marks as Other would break
// every Latin-with-diacritic cluster.
test "gcb_category: Combining Grave Accent -> Extend" {
  inspect(gcb_category(0x0300), content="Extend")
}

///|
// U+200D (ZERO WIDTH JOINER) is the sole cp with GCB=ZWJ per
// GraphemeBreakProperty.txt. ZWJ has its own category because GB11 (Extended
// Pictographic x (Extend* ZWJ) x Extended Pictographic) treats it
// specially; pinning this single cp keeps the emoji-ZWJ cluster rule alive.
test "gcb_category: ZWJ -> ZWJ" {
  inspect(gcb_category(0x200D), content="ZWJ")
}

///|
// U+1F1E6 (REGIONAL INDICATOR SYMBOL LETTER A) is the first cp of the
// Regional_Indicator range U+1F1E6..U+1F1FF per GraphemeBreakProperty.txt.
// Pinning the low end of the RI block locks GB12/GB13 (the RI parity rule
// that keeps flag pairs together) at the boundary where flag sequences
// begin.
test "gcb_category: Regional Indicator A -> Regional_Indicator" {
  inspect(gcb_category(0x1F1E6), content="Regional_Indicator")
}

///|
// U+1F600 (GRINNING FACE) has Extended_Pictographic=Yes in
// emoji-data.txt, so gcb_category must return Extended_Pictographic for it.
// This category drives GB11 (the emoji-ZWJ sequence rule); pinning a
// canonical emoji cp protects that rule's input.
test "gcb_category: Grinning Face -> Extended_Pictographic" {
  inspect(gcb_category(0x1F600), content="Extended_Pictographic")
}

///|
// U+1100 (HANGUL CHOSEONG KIYEOK) is the first cp of the L (leading
// consonant) jamo range per GraphemeBreakProperty.txt. Hangul syllable
// composition (GB6 / GB7 / GB8) depends on L / V / T / LV / LVT being
// distinguished; pins the low edge of L so the L-driven joins survive.
test "gcb_category: Hangul L -> L" {
  inspect(gcb_category(0x1100), content="L")
}

///|
// U+1161 (HANGUL JUNGSEONG A) is the first cp of the V (vowel) jamo range
// per GraphemeBreakProperty.txt. GB6 says L x (V|LV|LVT); this case fixes
// the V representative so any regression breaking L x V joins shows up.
test "gcb_category: Hangul V -> V" {
  inspect(gcb_category(0x1161), content="V")
}

///|
// U+11A8 (HANGUL JONGSEONG KIYEOK) is the first cp of the T (trailing
// consonant) jamo range per GraphemeBreakProperty.txt. GB8 says
// (LVT|T) x T; this case fixes the T representative.
test "gcb_category: Hangul T -> T" {
  inspect(gcb_category(0x11A8), content="T")
}

///|
// U+AC00 (HANGUL SYLLABLE GA) is the first precomposed Hangul syllable and
// has GCB=LV per GraphemeBreakProperty.txt (it ends in no trailing jamo, so
// further T can attach via GB7/GB8). Pins the LV entry at the very start of
// the precomposed syllable block.
test "gcb_category: Hangul LV syllable -> LV" {
  inspect(gcb_category(0xAC00), content="LV")
}

///|
// U+AC01 (HANGUL SYLLABLE GAG) is the immediate neighbor of U+AC00 and has
// GCB=LVT (it already contains a trailing jamo) per
// GraphemeBreakProperty.txt. The LV/LVT alternation across the precomposed
// Hangul block is fragile (it depends on the cp's trailing-jamo bit); this
// case pins LVT right next to the LV case above so a regression flattening
// the two into one category would surface.
test "gcb_category: Hangul LVT syllable -> LVT" {
  inspect(gcb_category(0xAC01), content="LVT")
}

///|
// U+0600 (ARABIC NUMBER SIGN) is GCB=Prepend per GraphemeBreakProperty.txt
// and lives in the Arabic block. Prepend drives GB9b (Prepend x .), which
// fuses the sign with the following cluster; pinning a canonical Prepend cp
// protects that join.
test "gcb_category: Prepend (Arabic Number Sign) -> Prepend" {
  inspect(gcb_category(0x0600), content="Prepend")
}

///|
// U+093E (DEVANAGARI VOWEL SIGN AA) is GCB=SpacingMark per
// GraphemeBreakProperty.txt. SpacingMark drives GB9a (x SpacingMark), which
// attaches the dependent vowel sign to the preceding consonant; pinning
// this canonical Indic SpacingMark protects the rule.
test "gcb_category: SpacingMark (Devanagari AA) -> SpacingMark" {
  inspect(gcb_category(0x093E), content="SpacingMark")
}

///|
// U+0915 (DEVANAGARI LETTER KA) is the first cp of the Devanagari InCB=
// Consonant range per DerivedCoreProperties.txt. gcb_category re-uses
// InCB_Consonant as a GCB category to drive GB9c (the Indic conjunct break
// rule, Consonant Linker Extend* Consonant). Pinning the lowest cp of the
// Devanagari InCB_Consonant range locks the low end of the consonant span
// so any regression that demoted these letters to Other would break Indic
// conjunct boundaries.
test "gcb_category: InCB_Consonant (Devanagari Ka) -> InCB_Consonant" {
  inspect(gcb_category(0x0915), content="InCB_Consonant")
}

// Edge cases

///|
// U+0000 is the lowest cp of the C0 Control range (U+0000..U+001F minus
// the CR/LF special-cases) per GraphemeBreakProperty.txt. Re-pins the
// bottom of the Control span as a deliberate edge probe; cp 0 cannot be
// hit by under-shooting, so this guards the very first stage1 cell.
test "gcb_category: range boundary start (first Control range)" {
  inspect(gcb_category(0x00), content="Control")
}

///|
// U+0009 (CHARACTER TABULATION) is the last cp of the contiguous C0
// Control prefix U+0000..U+0009 before U+000A (LF) takes over with its
// own GCB=LF category. Pins the high edge of the pre-LF Control span so a
// stage table that bled LF's classification into U+0009 would surface.
test "gcb_category: range boundary end" {
  inspect(gcb_category(0x09), content="Control")
}

///|
// U+0020 (SPACE) carries no GCB property per GraphemeBreakProperty.txt
// and must fall through to Other. It sits just above the C0 Control block
// (U+0000..U+001F); this case pins the first cp beyond Control so a
// stage1 range that over-extended into U+0020 would be caught.
test "gcb_category: just above range (space)" {
  inspect(gcb_category(0x20), content="Other")
}

///|
// U+10FFFF is the maximum Unicode scalar value. It is unassigned in the
// UCD and carries no GCB property, so it must return the implicit Other
// category. Pins the absolute upper end of the cp domain so any lookup
// that overflowed past the last table entry would crash or misclassify
// here first.
test "gcb_category: max codepoint" {
  inspect(gcb_category(0x10FFFF), content="Other")
}

// InCB auxiliary table tests

///|
// U+094D (DEVANAGARI SIGN VIRAMA) has InCB=Linker per
// DerivedCoreProperties.txt. The virama is the canonical Indic conjunct
// joiner that drives GB9c; pins is_incb_linker at a canonical linker cp so
// a regression that dropped the Devanagari linker would silently break
// every Devanagari conjunct cluster.
test "is_incb_linker: Devanagari Virama" {
  inspect(is_incb_linker(0x094D), content="true")
}

///|
// U+0041 'A' has no InCB property in DerivedCoreProperties.txt, so
// is_incb_linker must return false. A canonical ASCII letter is chosen as
// the negative case because it is the most common non-linker input; a
// regression that defaulted is_incb_linker to true would surface here.
test "is_incb_linker: non-linker" {
  inspect(is_incb_linker(0x0041), content="false")
}

///|
// U+0900 (DEVANAGARI SIGN INVERTED CANDRABINDU) has InCB=Extend per
// DerivedCoreProperties.txt - it is one of the Devanagari signs that
// continues an Indic conjunct cluster through GB9c (Consonant Linker
// Extend* Consonant). Pins is_incb_extend at a canonical Devanagari
// extending mark so a regression dropping the Devanagari InCB=Extend
// entries would surface here, breaking every Indic conjunct with a
// nasal / bindu in the middle.
test "is_incb_extend: Devanagari extending mark" {
  inspect(is_incb_extend(0x0900), content="true")
}

///|
// U+0041 'A' has no InCB property in DerivedCoreProperties.txt, so
// is_incb_extend must return false. ASCII letter is chosen as the negative
// case for symmetry with the is_incb_linker negative; a regression that
// defaulted is_incb_extend to true would surface here.
test "is_incb_extend: non-extend" {
  inspect(is_incb_extend(0x0041), content="false")
}

// ============================================================
// ASCII range tests
// ============================================================

///|
// U+0020 (SPACE) is the lowest printable ASCII cp and has no GCB property
// per GraphemeBreakProperty.txt, so it must return Other. Pins the bottom
// of the printable-ASCII range as a representative Other cp.
test "gcb_category: ASCII space" {
  inspect(gcb_category(0x20), content="Other")
}

///|
// U+007E '~' (TILDE) is the highest printable ASCII cp and has no GCB
// property per GraphemeBreakProperty.txt. Pins the top of the printable-
// ASCII range; together with U+0020 these bracket the printable ASCII
// span so the entire run is locked to Other.
test "gcb_category: ASCII tilde" {
  inspect(gcb_category(0x7E), content="Other")
}

///|
// U+007F (DELETE) is the first cp of the second contiguous Control span
// (U+007F..U+009F) per GraphemeBreakProperty.txt - the C1 control prefix
// rejoins GCB=Control immediately after printable ASCII ends. Pins the
// transition from printable ASCII back into Control at the DEL cp; an
// off-by-one that left U+007F as Other would surface here.
test "gcb_category: 0x7F is Control" {
  inspect(gcb_category(0x7F), content="Control")
}

// ============================================================
// Special Unicode code point GCB category tests
// ============================================================

///|
// U+FFFD (REPLACEMENT CHARACTER) is the canonical fallback character used
// when decoding invalid byte sequences. It has no GCB property in
// GraphemeBreakProperty.txt and must return Other. Pins this cp so
// decoded-replacement runs cluster like ordinary text rather than as
// controls.
test "gcb_category: U+FFFD (REPLACEMENT CHARACTER) -> Other" {
  inspect(gcb_category(0xFFFD), content="Other")
}

///|
// U+FEFF (ZERO WIDTH NO-BREAK SPACE / BOM) is GCB=Control per
// GraphemeBreakProperty.txt (it lives in the Cf format-character bucket).
// Pinning the BOM cp ensures a stray BOM in input does not get absorbed
// into a surrounding cluster.
test "gcb_category: U+FEFF (BOM / ZWNBSP) -> Control" {
  inspect(gcb_category(0xFEFF), content="Control")
}

///|
// U+E000 is the first cp of the BMP Private Use Area (U+E000..U+F8FF) per
// the Unicode Character Database. PUA cps carry no GCB property and must
// return Other so user-defined glyphs cluster like ordinary characters.
test "gcb_category: U+E000 (Private Use Area start) -> Other" {
  inspect(gcb_category(0xE000), content="Other")
}

///|
// U+F8FF is the last cp of the BMP Private Use Area (U+E000..U+F8FF) per
// the Unicode Character Database. Pinning the high end together with
// U+E000 brackets the whole PUA range into Other; a stage table that
// truncated the PUA early would surface here.
test "gcb_category: U+F8FF (Private Use Area end) -> Other" {
  inspect(gcb_category(0xF8FF), content="Other")
}

///|
// U+FFFF is a Unicode noncharacter (one of the two BMP noncharacters
// reserved at the end of every plane). It has no GCB property and must
// return Other. Pins the highest BMP cp so a stage1 length off-by-one
// would surface here.
test "gcb_category: U+FFFF (noncharacter) -> Other" {
  inspect(gcb_category(0xFFFF), content="Other")
}

///|
// U+FFFE is the second BMP noncharacter (paired with U+FFFF). Carries no
// GCB property, so it must return Other; pinning the neighbor just below
// U+FFFF guards against a single-cp drift at the BMP ceiling.
test "gcb_category: U+FFFE (noncharacter) -> Other" {
  inspect(gcb_category(0xFFFE), content="Other")
}

///|
// U+FDD0 is the first cp of the contiguous noncharacter range
// U+FDD0..U+FDEF reserved by the Unicode Character Database. Noncharacters
// carry no GCB property, so this cp must return Other; pins the low edge
// of the FDD0..FDEF gap.
test "gcb_category: U+FDD0 (noncharacter range start) -> Other" {
  inspect(gcb_category(0xFDD0), content="Other")
}

///|
// U+FDEF is the last cp of the noncharacter range U+FDD0..U+FDEF. Pins
// the high edge of that gap so a stage table that re-classified
// noncharacters as Control would surface either at this cp or at U+FDD0.
test "gcb_category: U+FDEF (noncharacter range end) -> Other" {
  inspect(gcb_category(0xFDEF), content="Other")
}

///|
// U+1FFFE is the lower of the two Plane-1 noncharacters at the end of the
// Supplementary Multilingual Plane. Carries no GCB property and must
// return Other; pins the Plane-1 ceiling pair.
test "gcb_category: U+1FFFE (noncharacter in SMP) -> Other" {
  inspect(gcb_category(0x1FFFE), content="Other")
}

///|
// U+1FFFF is the upper of the two Plane-1 noncharacters and the last cp
// of Plane 1. Must return Other; pins the absolute end of Plane 1 so a
// stage1 wrap into Plane 2 would surface here.
test "gcb_category: U+1FFFF (noncharacter in SMP) -> Other" {
  inspect(gcb_category(0x1FFFF), content="Other")
}

///|
// U+FFF0 is GCB=Control per GraphemeBreakProperty.txt (it lives in the
// U+FFF0..U+FFF8 reserved/format-control region of the Specials block).
// Pins the low edge of that Specials Control run.
test "gcb_category: U+FFF0 -> Control" {
  inspect(gcb_category(0xFFF0), content="Control")
}

///|
// U+FFFB (INTERLINEAR ANNOTATION TERMINATOR) is GCB=Control per
// GraphemeBreakProperty.txt - it is the last cp of the interlinear-
// annotation Control trio (U+FFF9..U+FFFB) at the top of the Specials
// block. Pins the high edge of the Specials Control region.
test "gcb_category: U+FFFB -> Control" {
  inspect(gcb_category(0xFFFB), content="Control")
}

///|
// U+FFFC (OBJECT REPLACEMENT CHARACTER) sits between the Control run
// ending at U+FFFB and the Other-classified U+FFFD just above it. It
// carries no GCB property per GraphemeBreakProperty.txt and must return
// Other; this is the singleton gap inside the Specials block, so a stage
// table that merged the Control range upward would misclassify exactly
// this cp.
test "gcb_category: U+FFFC (OBJECT REPLACEMENT CHARACTER) -> Other" {
  inspect(gcb_category(0xFFFC), content="Other")
}

// ============================================================
// Plane 14 branch boundary tests
// ============================================================

///|
// U+E0000 (LANGUAGE TAG) is GCB=Control per GraphemeBreakProperty.txt -
// it sits in the Language Tag range U+E0000..U+E001F that classifies as
// Control, just below the tag-character range that classifies as Extend.
// Pins the absolute floor of Plane 14 so the Extend-first / Control-
// fallthrough branch order does not accidentally hand U+E0000 to the
// Extend arm. (DR-0005 — Plane 14 ordering)
test "gcb_category: U+E0000 -> Control (Plane 14 fallback)" {
  inspect(gcb_category(0xE0000), content="Control")
}

///|
// U+E0001 (LANGUAGE TAG) is GCB=Control per GraphemeBreakProperty.txt and
// is the canonical language-tag introducer. Pins an interior cp of the
// Language Tag Control range so an off-by-one that started the Extend
// branch one cp early would surface here. (DR-0005 — Plane 14 ordering)
test "gcb_category: U+E0001 -> Control" {
  inspect(gcb_category(0xE0001), content="Control")
}

///|
// U+E001F is the last cp of the Language Tag Control range
// U+E0000..U+E001F per GraphemeBreakProperty.txt - the cp immediately
// before the GCB=Extend tag-character range begins at U+E0020. Pins the
// last-Control cp so a 1-cp underflow of the Extend range would surface
// here as a regression. (DR-0005 — Plane 14 ordering)
test "gcb_category: U+E001F -> Control (just before tag range)" {
  inspect(gcb_category(0xE001F), content="Control")
}

///|
// U+E0020 (TAG SPACE) is the first cp of the GCB=Extend tag-character
// range U+E0020..U+E007F per GraphemeBreakProperty.txt. This is the cp
// that begins emoji-flag subdivision tag sequences (the regional-flag
// "tag-base + tag-spec + cancel-tag" pattern). Pins the low edge of the
// Extend range; a regression in the Extend-first branch order would
// reclassify this cp as Control and shatter emoji flag clusters.
// (DR-0005 — Plane 14 ordering)
test "gcb_category: U+E0020 -> Extend (tag range start)" {
  inspect(gcb_category(0xE0020), content="Extend")
}

///|
// U+E007F (CANCEL TAG) is the last cp of the GCB=Extend tag-character
// range per GraphemeBreakProperty.txt. It is the terminator used in
// regional-flag tag sequences. Pins the high edge of the Extend range so
// a 1-cp overflow of the Control branch would surface here.
// (DR-0005 — Plane 14 ordering)
test "gcb_category: U+E007F -> Extend (tag range end)" {
  inspect(gcb_category(0xE007F), content="Extend")
}

///|
// U+E0080 is the first cp above the tag-character Extend range; it has
// GCB=Control per GraphemeBreakProperty.txt. Pins the immediate
// post-Extend Control cp so a 1-cp overflow of the Extend branch into the
// gap region would surface here. (DR-0005 — Plane 14 ordering)
test "gcb_category: U+E0080 -> Control (after tag range)" {
  inspect(gcb_category(0xE0080), content="Control")
}

///|
// U+E00FF is the last cp of the gap between the tag-character Extend
// range and the Variation Selectors Supplement Extend range; it has
// GCB=Control per GraphemeBreakProperty.txt. Pins the last-Control cp
// before VS17 begins; together with U+E0100 this nails the lower edge of
// the second Extend range. (DR-0005 — Plane 14 ordering)
test "gcb_category: U+E00FF -> Control (before variation selectors)" {
  inspect(gcb_category(0xE00FF), content="Control")
}

///|
// U+E0100 (VARIATION SELECTOR-17) is the first cp of the GCB=Extend
// Variation Selectors Supplement range U+E0100..U+E01EF per
// GraphemeBreakProperty.txt. VS17..VS256 attach to the preceding
// character to select glyph variants; pins the low edge of that range so
// a Plane 14 branch that missed this range entirely would break every
// emoji variation selector. (DR-0005 — Plane 14 ordering)
test "gcb_category: U+E0100 -> Extend (variation selectors start)" {
  inspect(gcb_category(0xE0100), content="Extend")
}

///|
// U+E01EF (VARIATION SELECTOR-256) is the last cp of the GCB=Extend
// Variation Selectors Supplement range per GraphemeBreakProperty.txt.
// Pins the high edge of the second Plane-14 Extend range so a 1-cp
// overflow of the Control branch would surface here.
// (DR-0005 — Plane 14 ordering)
test "gcb_category: U+E01EF -> Extend (variation selectors end)" {
  inspect(gcb_category(0xE01EF), content="Extend")
}

///|
// U+E01F0 is the first cp above the Variation Selectors Supplement
// Extend range; per GraphemeBreakProperty.txt the rest of Plane 14 above
// VS256 falls back to GCB=Control. Pins the immediate post-Extend
// Control cp so a 1-cp overflow of the Extend branch past U+E01EF would
// surface here. (DR-0005 — Plane 14 ordering)
test "gcb_category: U+E01F0 -> Control (after variation selectors)" {
  inspect(gcb_category(0xE01F0), content="Control")
}

///|
// U+E0FFF is the last cp of the Plane 14 Control region that the
// gcb_category_plane14 branch covers (Plane 14 = U+E0000..U+EFFFF, but
// Unicode currently assigns no GCB-relevant cps above U+E0FFF). Pins the
// ceiling of the Plane 14 Control fallthrough so the branch's upper
// bound stays correct. (DR-0005 — Plane 14 ordering)
test "gcb_category: U+E0FFF -> Control (Plane 14 end)" {
  inspect(gcb_category(0xE0FFF), content="Control")
}

///|
// U+E1000 sits above the Plane 14 special-purpose block that
// gcb_category_plane14 covers. Plane 14 above U+E0FFF carries no GCB
// property in GraphemeBreakProperty.txt, so this cp must drop out of the
// Plane 14 branch and return the implicit Other. Pins the cp just past
// the Plane 14 branch's upper bound; a Plane-14 guard typo that extended
// the Control range past U+E0FFF would surface here.
// (DR-0005 — Plane 14 ordering)
test "gcb_category: U+E1000 -> Other (beyond Plane 14 block)" {
  inspect(gcb_category(0xE1000), content="Other")
}

// ============================================================
// Plane 3+ fallthrough tests
// ============================================================

///|
// U+30000 is the first cp of Plane 3 (Tertiary Ideographic Plane). It
// carries no GCB property in GraphemeBreakProperty.txt, so it must
// return Other via the default fallthrough arm. Pins the Plane 3 floor;
// the segmenter-table NA delegation (CJK clustering lives in the
// uax29_test.mbt conformance corpus, not here) means this is the only
// place that locks Plane 3's lookup result.
// (DR-0007 — scope split)
test "gcb_category: U+30000 (Plane 3) -> Other" {
  inspect(gcb_category(0x30000), content="Other")
}

///|
// U+F0000 is the first cp of Plane 15 (Supplementary Private Use Area-A).
// PUA cps carry no GCB property in GraphemeBreakProperty.txt and must
// return Other. Pins Plane 15's floor and acts as a sentinel that the
// Plane 14 branch (which guards U+E0000..U+E0FFF) does not bleed up into
// Plane 15. (DR-0005 — Plane 14 ordering)
test "gcb_category: U+F0000 (Plane 15, Supplementary PUA-A) -> Other" {
  inspect(gcb_category(0xF0000), content="Other")
}

// === Edge probes — UCD plane boundaries and InCB property edges ===
//
// These probes pin down code points where the UCD-defined GCB / InCB property
// regions transition. A regression on either end of a range can silently
// mis-classify whole planes or whole InCB property ranges without failing the
// conformance corpus, so each cp is chosen because it is a UCD boundary (a
// plane end / start, a property-range endpoint, or a property-range gap) -
// not because of any implementation-internal encoding.
// (DR-0007 — scope split)

// --- BMP / Plane 1 / Plane 2 plane endpoints ---

///|
// U+FFFF is the last cp of the BMP (Plane 0). It is a noncharacter per the
// UCD and carries no GCB property in GraphemeBreakProperty.txt, so the
// lookup must return Other. Pins the absolute top of Plane 0; a regression
// that truncated Plane 0 short of U+FFFF (e.g. stopping at U+FEFF) would
// surface here, as would one that wrapped into Plane 1 at the BMP ceiling.
test "gcb_category: U+FFFF (last BMP cp) -> Other" {
  inspect(gcb_category(0xFFFF), content="Other")
}

///|
// U+10000 (LINEAR B SYLLABLE B008 A) is the first assigned cp of Plane 1
// (Supplementary Multilingual Plane) per the UCD. Linear B syllables have no
// GCB property, so the lookup must return Other. Pins the BMP -> Plane 1
// transition: any cp-domain regression at the Plane 0 ceiling would either
// misclassify or fail to reach this cp.
test "gcb_category: U+10000 (first cp of Plane 1) -> Other" {
  inspect(gcb_category(0x10000), content="Other")
}

///|
// U+1FFFF is the last cp of Plane 1 - it is a noncharacter per the UCD and
// has no GCB property, so the lookup must return Other. Pins the Plane 1
// ceiling; a regression that truncated Plane 1 coverage early (e.g. at
// U+1FF00) would surface here.
test "gcb_category: U+1FFFF (last cp of Plane 1) -> Other" {
  inspect(gcb_category(0x1FFFF), content="Other")
}

///|
// U+20000 (CJK UNIFIED IDEOGRAPH-20000) is the first assigned cp of Plane 2
// (Supplementary Ideographic Plane) per the UCD. CJK ideographs have no GCB
// property, so the lookup must return Other. Pins the Plane 1 -> Plane 2
// transition.
test "gcb_category: U+20000 (first cp of Plane 2) -> Other" {
  inspect(gcb_category(0x20000), content="Other")
}

///|
// U+2FFFF is the last cp of Plane 2 - it is a noncharacter per the UCD and
// has no GCB property, so the lookup must return Other. Pins the Plane 2
// ceiling; this is the highest cp in the range of planes that actually
// carry GCB property assignments (Planes 0-2), and Plane 3+ are entirely
// Other (Plane 14 is the lone exception, handled by its own branch).
test "gcb_category: U+2FFFF (last cp in two-stage table) -> Other" {
  inspect(gcb_category(0x2FFFF), content="Other")
}

// --- Plane 3-16 fallthrough probes (Plane 14 branch / default Other) ---

///|
// U+30000 (CJK UNIFIED IDEOGRAPH-30000) is the first assigned cp of Plane 3
// (Tertiary Ideographic Plane) per the UCD. Plane 3 carries no GCB
// property, so the lookup must return Other. Pins the Plane 3 floor; sits
// above the GCB-bearing planes (0-2) and below the Plane 14 special-purpose
// branch (E0000-E0FFF), so it must hit the default Other arm.
// (DR-0005 — Plane 14 ordering)
test "gcb_category: U+30000 (Plane 3 fallthrough) -> Other" {
  inspect(gcb_category(0x30000), content="Other")
}

///|
// U+F0000 is the first cp of Plane 15 (Supplementary Private Use Area-A)
// per the UCD. PUA cps carry no GCB property, so the lookup must return
// Other. Pins the Plane 15 floor and acts as a sentinel that the Plane 14
// branch (which guards U+E0000..U+E0FFF) does not bleed past U+E0FFF into
// Plane 15. (DR-0005 — Plane 14 ordering)
test "gcb_category: U+F0000 (Plane 15 fallthrough) -> Other" {
  inspect(gcb_category(0xF0000), content="Other")
}

///|
// U+100000 is the first cp of Plane 16 (Supplementary Private Use Area-B)
// per the UCD. PUA cps carry no GCB property, so the lookup must return
// Other. Pins the Plane 16 floor; together with U+F0000 above this locks
// both supplementary PUA planes into the default Other arm.
test "gcb_category: U+100000 (Plane 16 fallthrough) -> Other" {
  inspect(gcb_category(0x100000), content="Other")
}

// --- ZWJ vs ZWNJ neighbor (locks UCD-adjacent categories) ---

///|
// U+200C (ZERO WIDTH NON-JOINER) is GCB=Extend per GraphemeBreakProperty.txt
// and sits immediately below the sole GCB=ZWJ cp at U+200D. The two cps are
// classified differently by the UCD even though they share the same general
// category (Cf, format character); the audit flagged this neighbor pair as
// under-asserted because a 1-cp drift between adjacent UCD property values
// would swap these two classifications without breaking most cluster tests.
test "gcb_category: U+200C (ZWNJ) -> Extend" {
  inspect(gcb_category(0x200C), content="Extend")
}

///|
// U+200D (ZERO WIDTH JOINER) is the sole cp with GCB=ZWJ per
// GraphemeBreakProperty.txt. It is the immediate upper neighbor of the
// GCB=Extend cp U+200C; ZWJ has its own category because GB11 (Extended
// Pictographic x (Extend* ZWJ) x Extended Pictographic) treats it
// specially. Pinning U+200D against U+200C nails the property-value
// boundary between these adjacent UCD entries.
test "gcb_category: U+200D (ZWJ) -> ZWJ" {
  inspect(gcb_category(0x200D), content="ZWJ")
}

// --- is_incb_linker UCD property-range edges ---

///|
// U+094D (DEVANAGARI SIGN VIRAMA) is the lowest cp with InCB=Linker in
// DerivedCoreProperties.txt - it is the first Indic conjunct linker assigned
// in code-point order. Pins the lookup at the lowest cp of the InCB_Linker
// property range; a regression that excluded the Devanagari virama would
// silently break every Devanagari Indic conjunct boundary (GB9c needs
// is_incb_linker to fire here).
test "is_incb_linker: U+094D first entry of packed table" {
  inspect(is_incb_linker(0x094D), content="true")
}

///|
// U+11F42 (DIVES AKURU SIGN HALANTA) is the highest cp with InCB=Linker in
// DerivedCoreProperties.txt - the last Indic conjunct linker assigned in
// code-point order. Pins the lookup at the highest cp of the InCB_Linker
// property range; a regression that excluded the Dives Akuru halanta would
// silently break Dives Akuru conjunct boundaries.
test "is_incb_linker: U+11F42 last entry of packed table" {
  inspect(is_incb_linker(0x11F42), content="true")
}

///|
// U+0ACD (GUJARATI SIGN VIRAMA) has InCB=Linker per
// DerivedCoreProperties.txt and sits in the interior of the InCB_Linker
// range (not at either end). Pins a canonical interior InCB=Linker cp;
// together with the U+094D and U+11F42 endpoint probes above, this covers
// "low edge / interior / high edge" of the InCB_Linker property range.
test "is_incb_linker: U+0ACD interior exact match" {
  inspect(is_incb_linker(0x0ACD), content="true")
}

///|
// U+094E (DEVANAGARI VOWEL SIGN PRISHTHAMATRA E) has no InCB property in
// DerivedCoreProperties.txt - it is the cp immediately above the
// Devanagari virama U+094D, but it is a vowel sign rather than a linker.
// is_incb_linker must return false. Pins the immediate post-Linker
// neighbor; a 1-cp overflow of the linker range would surface here.
test "is_incb_linker: U+094E between entries -> false" {
  inspect(is_incb_linker(0x094E), content="false")
}

///|
// U+200000 is above the highest possible Unicode cp (U+10FFFF) and so
// trivially carries no UCD property, including no InCB property. The
// lookup must return false. Pins a far-out-of-range cp that is also above
// every linker assignment (the highest linker is U+11F42 from the Dives
// Akuru block), as a sentinel against a lookup that fails to short-circuit
// for cps past the InCB_Linker property range.
test "is_incb_linker: U+200000 above all entries -> false" {
  inspect(is_incb_linker(0x200000), content="false")
}

// --- is_incb_extend UCD property-range edges ---

///|
// U+0300 (COMBINING GRAVE ACCENT) is the lowest cp with InCB=Extend in
// DerivedCoreProperties.txt - it begins the Combining Diacritical Marks
// block (U+0300..U+036F), the lowest InCB_Extend range in cp order. Pins
// the lookup at the lowest cp of the InCB_Extend property; a regression
// that excluded the Combining Diacritical Marks would silently break every
// Indic conjunct that runs through a combining mark in the middle.
test "is_incb_extend: U+0300 first-range start" {
  inspect(is_incb_extend(0x0300), content="true")
}

///|
// U+036F (COMBINING LATIN SMALL LETTER X) is the highest cp of the first
// InCB=Extend range U+0300..U+036F (Combining Diacritical Marks) per
// DerivedCoreProperties.txt. Pins the inclusive top of the first
// InCB_Extend range; a regression treating the range endpoint as exclusive
// would falsely classify this canonical combining mark as Other.
test "is_incb_extend: U+036F first-range inclusive end" {
  inspect(is_incb_extend(0x036F), content="true")
}

///|
// U+E01EF (VARIATION SELECTOR-256) is the highest cp with InCB=Extend in
// DerivedCoreProperties.txt - the top of the Variation Selectors Supplement
// range U+E0100..U+E01EF, which is the highest InCB_Extend range in cp
// order. Pins the absolute top of the InCB_Extend property; a regression
// that excluded VS17-256 would silently break variation-selector usage
// inside Indic conjunct clusters.
test "is_incb_extend: U+E01EF last-range end" {
  inspect(is_incb_extend(0xE01EF), content="true")
}

///|
// U+0400 (CYRILLIC CAPITAL LETTER IE WITH GRAVE) has no InCB property in
// DerivedCoreProperties.txt - it is a Cyrillic letter, not an extending
// mark. It sits in the gap between the first InCB=Extend range ending at
// U+036F and the next InCB=Extend range that begins later in cp order.
// is_incb_extend must return false. Pins an inter-range gap cp; a
// regression that merged adjacent InCB_Extend ranges would falsely
// include this Cyrillic letter in the extend set.
test "is_incb_extend: U+0400 between ranges -> false" {
  inspect(is_incb_extend(0x0400), content="false")
}

///|
// U+FFFFF is the last cp of Plane 15 (a noncharacter per the UCD), well
// above every InCB=Extend range. It carries no InCB property, so
// is_incb_extend must return false. Pins a high cp above every UCD
// InCB_Extend range; a lookup that fails to short-circuit for cps past
// the InCB_Extend property range would surface here.
test "is_incb_extend: U+FFFFF above all ranges -> false" {
  inspect(is_incb_extend(0xFFFFF), content="false")
}

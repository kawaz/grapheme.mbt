// ============================================================================
// File scope (segmenter_wbtest.mbt) — UAX #29 segmenter internals, white-box.
//
// In scope:
//   - check_boundary(prev, cur, ri_count, emoji_state, incb_state) cell
//     coverage: every GB rule that the lookup table encodes is exercised by
//     name, so a wrong cell flip surfaces here rather than at the corpus.
//   - next_emoji_state: the state x input transition matrix for the
//     Extended_Pictographic / ZWJ tracker, including every reset edge.
//   - next_incb_state: the state x input transition matrix for the
//     Indic_Conjunct_Break tracker (Consonant / Linker / Extend), including
//     every reset edge.
//   - ri_count parity invariant: the counter only changes the boundary
//     decision when both sides of the join are Regional_Indicator; all other
//     contexts must be insensitive to its value.
//
// Not in scope (= covered elsewhere, do not duplicate here):
//   - gcb_category lookup (codepoint -> GCB class) — see gcb_wbtest.mbt.
//   - Public API surface (iterators, boundary helpers) — see lib_wbtest.mbt.
//   - UCD corpus parity (GraphemeBreakTest.txt conformance) — see
//     uax29_test.mbt and uax29_iter_test.mbt.
//
// DR-0007 — test scope split (white-box internals vs. corpus parity).
// ============================================================================

// Show impls for test-only types (mirrors derive(Show) output)

///|
impl Show for EmojiState with fn output(self, logger) {
  logger.write_string(
    match self {
      ES_None => "ES_None"
      ES_EP_Seen => "ES_EP_Seen"
      ES_EP_Extend_ZWJ => "ES_EP_Extend_ZWJ"
    },
  )
}

///|
impl Show for InCBState with fn output(self, logger) {
  logger.write_string(
    match self {
      IC_None => "IC_None"
      IC_Consonant_Seen => "IC_Consonant_Seen"
      IC_Consonant_Linker_Seen => "IC_Consonant_Linker_Seen"
    },
  )
}

// Individual GB rule tests for check_boundary()
// State-dependent parameters use default values (ri_count=0, ES_None, IC_None)

// GB3: CR × LF

///|
// Input: prev=CR, cur=LF with all state defaults.
// Expected: false (no boundary).
// Why: UAX #29 GB3 keeps CR LF as a single grapheme — a CRLF newline pair must
// not split, otherwise text rendering would treat the two halves of a Windows
// line ending as separate clusters.
test "check_boundary: GB3 CR×LF" {
  inspect(check_boundary(CR, LF, 0, ES_None, IC_None), content="false")
}

// GB4: (Control|CR|LF) ÷

///|
// Input: prev=Control, cur=Other with all state defaults.
// Expected: true (boundary).
// Why: UAX #29 GB4 breaks after any Control/CR/LF — control characters never
// glue to whatever follows, so the next character starts a new cluster.
test "check_boundary: GB4 Control÷Any" {
  inspect(check_boundary(Control, Other, 0, ES_None, IC_None), content="true")
}

///|
// Input: prev=CR, cur=Other (anything that is NOT LF) with all state defaults.
// Expected: true (boundary).
// Why: UAX #29 GB4 breaks after CR unless GB3 already absorbed an immediately
// following LF. A bare CR (no LF after) must split from the next character.
test "check_boundary: GB4 CR÷Any(not LF)" {
  inspect(check_boundary(CR, Other, 0, ES_None, IC_None), content="true")
}

// GB5: ÷ (Control|CR|LF)

///|
// Input: prev=Other, cur=Control with all state defaults.
// Expected: true (boundary).
// Why: UAX #29 GB5 breaks before any Control/CR/LF — a control character
// always starts a fresh cluster regardless of what preceded it.
test "check_boundary: GB5 Any÷Control" {
  inspect(check_boundary(Other, Control, 0, ES_None, IC_None), content="true")
}

// GB6: L × (L|V|LV|LVT)

///|
// Input: prev=L, cur=L with all state defaults.
// Expected: false (no boundary).
// Why: UAX #29 GB6 keeps a leading Hangul jamo (L) glued to a following
// leading jamo — successive choseong characters form one syllable cluster.
test "check_boundary: GB6 L×L" {
  inspect(check_boundary(L, L, 0, ES_None, IC_None), content="false")
}

///|
// Input: prev=L, cur=V with all state defaults.
// Expected: false (no boundary).
// Why: UAX #29 GB6 keeps a leading jamo (L) glued to a following vowel jamo
// (V) — this is the canonical L+V Hangul syllable join.
test "check_boundary: GB6 L×V" {
  inspect(check_boundary(L, V, 0, ES_None, IC_None), content="false")
}

///|
// Input: prev=L, cur=LV with all state defaults.
// Expected: false (no boundary).
// Why: UAX #29 GB6 keeps a leading jamo (L) glued to a precomposed LV
// Hangul syllable so the chosung does not detach from the syllable block.
test "check_boundary: GB6 L×LV" {
  inspect(check_boundary(L, LV, 0, ES_None, IC_None), content="false")
}

///|
// Input: prev=L, cur=LVT with all state defaults.
// Expected: false (no boundary).
// Why: UAX #29 GB6 keeps a leading jamo (L) glued to a precomposed LVT
// Hangul syllable; same join rule as L×LV with a trailing jamo present.
test "check_boundary: GB6 L×LVT" {
  inspect(check_boundary(L, LVT, 0, ES_None, IC_None), content="false")
}

// GB7: (LV|V) × (V|T)

///|
// Input: prev=LV, cur=V with all state defaults.
// Expected: false (no boundary).
// Why: UAX #29 GB7 keeps an LV syllable glued to a following vowel jamo (V)
// — additional vowels still belong to the same Hangul syllable cluster.
test "check_boundary: GB7 LV×V" {
  inspect(check_boundary(LV, V, 0, ES_None, IC_None), content="false")
}

///|
// Input: prev=V, cur=T with all state defaults.
// Expected: false (no boundary).
// Why: UAX #29 GB7 keeps a vowel jamo (V) glued to a following trailing
// jamo (T) — V+T continues building one Hangul syllable.
test "check_boundary: GB7 V×T" {
  inspect(check_boundary(V, T, 0, ES_None, IC_None), content="false")
}

// GB8: (LVT|T) × T

///|
// Input: prev=LVT, cur=T with all state defaults.
// Expected: false (no boundary).
// Why: UAX #29 GB8 keeps an LVT syllable glued to a following trailing jamo
// (T) — extra trailing jamos still belong to the same syllable block.
test "check_boundary: GB8 LVT×T" {
  inspect(check_boundary(LVT, T, 0, ES_None, IC_None), content="false")
}

///|
// Input: prev=T, cur=T with all state defaults.
// Expected: false (no boundary).
// Why: UAX #29 GB8 keeps a trailing jamo (T) glued to a following trailing
// jamo (T) — chains of T jamos remain in one Hangul syllable cluster.
test "check_boundary: GB8 T×T" {
  inspect(check_boundary(T, T, 0, ES_None, IC_None), content="false")
}

// GB9: × (Extend|ZWJ)

///|
// Input: prev=Other, cur=Extend with all state defaults.
// Expected: false (no boundary).
// Why: UAX #29 GB9 forbids breaking before Extend — combining marks and
// other Extend code points always attach to the preceding base character.
test "check_boundary: GB9 Any×Extend" {
  inspect(check_boundary(Other, Extend, 0, ES_None, IC_None), content="false")
}

///|
// Input: prev=Other, cur=ZWJ with all state defaults.
// Expected: false (no boundary).
// Why: UAX #29 GB9 also forbids breaking before ZWJ — the zero width joiner
// must stick to whatever precedes it so emoji-ZWJ sequences can form later.
test "check_boundary: GB9 Any×ZWJ" {
  inspect(check_boundary(Other, ZWJ, 0, ES_None, IC_None), content="false")
}

// GB9a: × SpacingMark

///|
// Input: prev=Other, cur=SpacingMark with all state defaults.
// Expected: false (no boundary).
// Why: UAX #29 GB9a forbids breaking before SpacingMark — Indic/Brahmic
// spacing combining marks attach to the preceding base character.
test "check_boundary: GB9a Any×SpacingMark" {
  inspect(
    check_boundary(Other, SpacingMark, 0, ES_None, IC_None),
    content="false",
  )
}

// GB9b: Prepend ×

///|
// Input: prev=Prepend, cur=Other with all state defaults.
// Expected: false (no boundary).
// Why: UAX #29 GB9b forbids breaking after Prepend — prepended formatting
// marks (e.g. Indic prepended concatenation marks) glue forward to the
// next base character.
test "check_boundary: GB9b Prepend×Any" {
  inspect(check_boundary(Prepend, Other, 0, ES_None, IC_None), content="false")
}

// GB999: Any ÷ Any

///|
// Input: prev=Other, cur=Other with all state defaults.
// Expected: true (boundary).
// Why: UAX #29 GB999 is the fall-through rule — when no earlier rule
// suppresses a break, two adjacent "Other" code points are split.
test "check_boundary: GB999 Other÷Other" {
  inspect(check_boundary(Other, Other, 0, ES_None, IC_None), content="true")
}

// --- State-dependent rule tests ---

// GB9c: InCB Consonant + [Extend|Linker]* Linker [Extend|Linker]* × InCB_Consonant

///|
// Input: prev=Extend, cur=InCB_Consonant, incb_state=IC_Consonant_Linker_Seen.
// Expected: false (no boundary).
// Why: UAX #29 GB9c suppresses the break before an InCB Consonant when the
// state machine has already observed Consonant + (Extend|Linker)* Linker —
// the Indic conjunct chain joins through the virama. The state being
// IC_Consonant_Linker_Seen here encodes exactly that history.
// (DR-0004 — segmenter state parity)
test "check_boundary: GB9c Consonant_Linker_Seen × InCB_Consonant" {
  inspect(
    check_boundary(Extend, InCB_Consonant, 0, ES_None, IC_Consonant_Linker_Seen),
    content="false",
  )
}

///|
// Input: prev=Extend, cur=InCB_Consonant, incb_state=IC_Consonant_Seen (no
// linker observed yet).
// Expected: true (boundary).
// Why: GB9c only fires when a Linker has been seen since the last Consonant.
// Without the linker, the InCB chain is not eligible, so the default GB999
// fall-through applies and the boundary fires.
// (DR-0004 — segmenter state parity)
test "check_boundary: GB9c without linker -> boundary" {
  inspect(
    check_boundary(Extend, InCB_Consonant, 0, ES_None, IC_Consonant_Seen),
    content="true",
  )
}

// GB11: Extended_Pictographic Extend* ZWJ × Extended_Pictographic

///|
// Input: prev=ZWJ, cur=Extended_Pictographic, emoji_state=ES_EP_Extend_ZWJ.
// Expected: false (no boundary).
// Why: UAX #29 GB11 suppresses the break inside an emoji ZWJ sequence
// (Extended_Pictographic Extend* ZWJ × Extended_Pictographic). The state
// ES_EP_Extend_ZWJ encodes that an EP followed by zero or more Extend then
// ZWJ has been seen, so the next EP joins as a single emoji cluster.
// (DR-0004 — segmenter state parity)
test "check_boundary: GB11 EP_Extend_ZWJ × EP" {
  inspect(
    check_boundary(ZWJ, Extended_Pictographic, 0, ES_EP_Extend_ZWJ, IC_None),
    content="false",
  )
}

///|
// Input: prev=ZWJ, cur=Extended_Pictographic, emoji_state=ES_None.
// Expected: true (boundary).
// Why: GB11 requires the EP-Extend*-ZWJ prefix; a stray ZWJ without that
// history does not qualify. The state being ES_None means no EP preceded
// the ZWJ, so the default boundary applies.
// (DR-0004 — segmenter state parity)
test "check_boundary: GB11 without EP state -> boundary" {
  inspect(
    check_boundary(ZWJ, Extended_Pictographic, 0, ES_None, IC_None),
    content="true",
  )
}

// GB12/13: RI × RI (odd count -> no break, even count -> break)

///|
// Input: prev=Regional_Indicator, cur=Regional_Indicator, ri_count=1.
// Expected: false (no boundary).
// Why: UAX #29 GB12/GB13 keep an even-numbered pair of RIs together to form
// one flag emoji. ri_count=1 means one RI has already been absorbed before
// cur — odd parity — so cur is the second RI of the pair and must NOT break.
// (DR-0004 — segmenter state parity)
test "check_boundary: GB12/13 RI×RI odd count -> no break" {
  inspect(
    check_boundary(Regional_Indicator, Regional_Indicator, 1, ES_None, IC_None),
    content="false",
  )
}

///|
// Input: prev=Regional_Indicator, cur=Regional_Indicator, ri_count=2.
// Expected: true (boundary).
// Why: With two RIs already absorbed (a complete flag), parity is even, so
// the next RI starts a fresh flag pair and must break before cur.
// (DR-0004 — segmenter state parity)
test "check_boundary: GB12/13 RI×RI even count -> break" {
  inspect(
    check_boundary(Regional_Indicator, Regional_Indicator, 2, ES_None, IC_None),
    content="true",
  )
}

// GB4: LF ÷ Any

///|
// Input: prev=LF, cur=Other with all state defaults.
// Expected: true (boundary).
// Why: UAX #29 GB4 also breaks after LF — once LF has terminated (or stood
// alone as) a line, the next character starts a new cluster.
test "check_boundary: GB4 LF÷Any" {
  inspect(check_boundary(LF, Other, 0, ES_None, IC_None), content="true")
}

// GB9b (Prepend x) vs GB5 (÷ Control) -> GB5 takes priority

///|
// Input: prev=Prepend, cur=Control with all state defaults.
// Expected: true (boundary).
// Why: GB9b suppresses a break after Prepend, but UAX #29 rule order makes
// GB5 (break before Control/CR/LF) win when the next character is a Control
// — a Prepend cannot drag a control into its cluster.
test "check_boundary: Prepend÷Control (GB5 wins over GB9b)" {
  inspect(check_boundary(Prepend, Control, 0, ES_None, IC_None), content="true")
}

///|
// Input: prev=Prepend, cur=CR with all state defaults.
// Expected: true (boundary).
// Why: Same priority interaction as Prepend÷Control — GB5 forces a break
// before CR even though GB9b would otherwise suppress it after Prepend.
test "check_boundary: Prepend÷CR (GB5 wins over GB9b)" {
  inspect(check_boundary(Prepend, CR, 0, ES_None, IC_None), content="true")
}

// next_emoji_state transition tests

///|
// Input: state=ES_None, cur=Extended_Pictographic.
// Expected: ES_EP_Seen.
// Why: GB11 starts the emoji-ZWJ tracker when an Extended_Pictographic is
// observed; the idle state transitions to "EP seen" so a later ZWJ can be
// recognised as joining.
// (DR-0004 — segmenter state parity)
test "next_emoji_state: EP -> ES_EP_Seen" {
  inspect(
    next_emoji_state(ES_None, Extended_Pictographic),
    content="ES_EP_Seen",
  )
}

///|
// Input: state=ES_EP_Seen, cur=Extend.
// Expected: ES_EP_Seen (stays).
// Why: GB11's pattern is EP Extend* ZWJ × EP; any number of Extends after
// the initial EP keeps the tracker armed without advancing past the ZWJ slot.
// (DR-0004 — segmenter state parity)
test "next_emoji_state: ES_EP_Seen + Extend -> ES_EP_Seen" {
  inspect(next_emoji_state(ES_EP_Seen, Extend), content="ES_EP_Seen")
}

///|
// Input: state=ES_EP_Seen, cur=ZWJ.
// Expected: ES_EP_Extend_ZWJ.
// Why: ZWJ after EP (and optional Extends) advances the GB11 state machine
// to the "waiting for the joined EP" slot. Boundary suppression then fires
// only if the next character is another Extended_Pictographic.
// (DR-0004 — segmenter state parity)
test "next_emoji_state: ES_EP_Seen + ZWJ -> ES_EP_Extend_ZWJ" {
  inspect(next_emoji_state(ES_EP_Seen, ZWJ), content="ES_EP_Extend_ZWJ")
}

///|
// Input: state=ES_EP_Seen, cur=Other (anything not Extend/ZWJ/EP).
// Expected: ES_None (reset).
// Why: An EP followed by an unrelated character breaks the GB11 pattern;
// the tracker must reset so a later EP starts a fresh chain.
// (DR-0004 — segmenter state parity)
test "next_emoji_state: ES_EP_Seen + Other -> ES_None" {
  inspect(next_emoji_state(ES_EP_Seen, Other), content="ES_None")
}

///|
// Input: state=ES_EP_Extend_ZWJ, cur=Extended_Pictographic.
// Expected: ES_EP_Seen.
// Why: When the joined EP arrives, GB11 has matched once; the state machine
// re-enters ES_EP_Seen so a further Extend*-ZWJ-EP can chain (emoji ZWJ
// sequences support multiple joins like family-of-four).
// (DR-0004 — segmenter state parity)
test "next_emoji_state: ES_EP_Extend_ZWJ + EP -> ES_EP_Seen (chain restart)" {
  inspect(
    next_emoji_state(ES_EP_Extend_ZWJ, Extended_Pictographic),
    content="ES_EP_Seen",
  )
}

// next_incb_state transition tests

///|
// Input: state=IC_None, cur=InCB_Consonant, cp=U+0915 (DEVANAGARI LETTER KA;
// gc=Lo, InCB=Consonant — a canonical Indic Conjunct Break consonant).
// Expected: IC_Consonant_Seen.
// Why: GB9c needs to remember when a Consonant has been observed so a later
// Linker can mark the chain as eligible for boundary suppression.
// (DR-0004 — segmenter state parity)
test "next_incb_state: InCB_Consonant -> IC_Consonant_Seen" {
  inspect(
    next_incb_state(IC_None, InCB_Consonant, 0x0915), // U+0915 = InCB Consonant (Devanagari Letter Ka)
    content="IC_Consonant_Seen",
  )
}

///|
// Input: state=IC_Consonant_Seen, cur=Extend, cp=U+094D (DEVANAGARI SIGN
// VIRAMA; gc=Mn, InCB=Linker — the virama is the canonical Indic linker).
// Expected: IC_Consonant_Linker_Seen.
// Why: A Linker after a Consonant advances the GB9c chain to the
// "Linker observed" state, which makes a following InCB_Consonant join
// without a break.
// (DR-0004 — segmenter state parity)
test "next_incb_state: IC_Consonant_Seen + Linker -> IC_Consonant_Linker_Seen" {
  inspect(
    next_incb_state(IC_Consonant_Seen, Extend, 0x094D), // U+094D = InCB Linker (Devanagari Sign Virama)
    content="IC_Consonant_Linker_Seen",
  )
}

///|
// Input: state=IC_Consonant_Seen, cur=Other, cp=U+0041 (LATIN CAPITAL
// LETTER A; gc=Lu, NOT an InCB property — used here as a clearly non-Indic
// code point that drops out of the conjunct chain).
// Expected: IC_None (reset).
// Why: A non-Indic character after a Consonant breaks the GB9c pattern
// before any Linker arrives; the tracker resets so a stale Consonant_Seen
// state does not accidentally suppress a later boundary.
// (DR-0004 — segmenter state parity)
test "next_incb_state: IC_Consonant_Seen + Other -> IC_None" {
  inspect(
    next_incb_state(IC_Consonant_Seen, Other, 0x0041), // U+0041 = non-InCB (Latin Capital Letter A)
    content="IC_None",
  )
}

///|
// Input: state=IC_Consonant_Linker_Seen, cur=InCB_Consonant, cp=U+0915
// (DEVANAGARI LETTER KA; gc=Lo, InCB=Consonant).
// Expected: IC_Consonant_Seen.
// Why: Once a Consonant + Linker + Consonant has been observed, the chain
// has completed one join and may continue. The state returns to
// IC_Consonant_Seen so the new Consonant becomes the head of a possible
// next Consonant+Linker+Consonant join (e.g. क्ष्म-style multi-link clusters).
// (DR-0004 — segmenter state parity)
test "next_incb_state: IC_Consonant_Linker_Seen + InCB_Consonant -> IC_Consonant_Seen" {
  inspect(
    next_incb_state(IC_Consonant_Linker_Seen, InCB_Consonant, 0x0915), // U+0915 = InCB Consonant (Devanagari Letter Ka)
    content="IC_Consonant_Seen",
  )
}

///|
// Input: prev=Other, cur=LF with all state defaults.
// Expected: true (boundary).
// Why: UAX #29 GB5 breaks before LF — covered by GB3 only when CR precedes.
// Pinned explicitly so a refactor of GB5 that omits LF (and only retains
// "Control") would surface here rather than via corpus rows.
test "check_boundary: GB5 Any÷LF" {
  inspect(check_boundary(Other, LF, 0, ES_None, IC_None), content="true")
}

///|
// Input: prev=Other, cur=CR with all state defaults.
// Expected: true (boundary).
// Why: UAX #29 GB5 also breaks before CR. Pinned distinct from Any÷Control
// so a CR-specific oversight (e.g. forgetting CR in the GB5 set) is caught.
test "check_boundary: GB5 Any÷CR" {
  inspect(check_boundary(Other, CR, 0, ES_None, IC_None), content="true")
}

///|
// Input: state=ES_EP_Extend_ZWJ, cur=Other (non-EP, non-Extend).
// Expected: ES_None (reset).
// Why: GB11 only matches when the character after ZWJ is another
// Extended_Pictographic. Any other category aborts the match and the
// tracker must reset so a later EP starts a fresh chain.
// (DR-0004 — segmenter state parity)
test "next_emoji_state: ES_EP_Extend_ZWJ + Other -> ES_None" {
  inspect(next_emoji_state(ES_EP_Extend_ZWJ, Other), content="ES_None")
}

///|
// Input: state=IC_Consonant_Linker_Seen, cur=Extend, cp=U+0900 (DEVANAGARI
// SIGN INVERTED CANDRABINDU; gc=Mn, InCB=Extend — counted as part of the
// Indic conjunct extend set per DerivedCoreProperties).
// Expected: IC_Consonant_Linker_Seen (state maintained).
// Why: GB9c allows Extend/Linker characters between the Linker and the
// following Consonant. An InCB=Extend code point keeps the chain alive
// without advancing or resetting the state.
// (DR-0004 — segmenter state parity)
test "next_incb_state: IC_Consonant_Linker_Seen + Extend (InCB Extend) -> IC_Consonant_Linker_Seen" {
  inspect(
    next_incb_state(IC_Consonant_Linker_Seen, Extend, 0x0900), // U+0900 = InCB Extend (Devanagari Sign Inverted Candrabindu)
    content="IC_Consonant_Linker_Seen",
  )
}

// === State machine cell completions (DR-0007 scope) ===

///|
// Input: prev=LV, cur=T with all state defaults.
// Expected: false (no boundary).
// Why: GB7 says (LV|V) × (V|T) — LV×V is already pinned above, but the LV×T
// half of the same cell was missing. A wrong table flip on LV×T would slip
// past the corpus only on rare LV+T sequences. Pin it explicitly.
// (DR-0007 — test scope split)
test "check_boundary: GB7 LV×T" {
  inspect(check_boundary(LV, T, 0, ES_None, IC_None), content="false")
}

///|
// Input: prev=V, cur=V with all state defaults.
// Expected: false (no boundary).
// Why: GB7 also covers V×V (two vocalic Hangul jamos in a row). V×T is pinned
// above; V×V was missing. Pin it so the GB7 row of the table is fully locked.
// (DR-0007 — test scope split)
test "check_boundary: GB7 V×V" {
  inspect(check_boundary(V, V, 0, ES_None, IC_None), content="false")
}

///|
// Input: prev=T, cur=T with all state defaults.
// Expected: false (no boundary).
// Why: GB8 says (LVT|T) × T — trailing jamos chain. The original T×T test
// near the top of this file pins the same cell; this entry re-states the
// "Hangul trailing jamos chain" intent alongside LVT×T in the completions
// section so the GB8 row is read as a pair. Kept distinct via suffix.
// (DR-0007 — test scope split)
test "check_boundary: GB8 T×T (trailing jamo chain, completion)" {
  inspect(check_boundary(T, T, 0, ES_None, IC_None), content="false")
}

///|
// Input: prev=LVT, cur=T with all state defaults.
// Expected: false (no boundary).
// Why: GB8 LVT×T half of the cell. The original LVT×T test at the top of
// this file pins the same cell; this duplicate-named property check exists
// in the completions section so the GB8 row is read as a coherent pair
// alongside T×T. Kept distinct via the "(completion)" suffix.
// (DR-0007 — test scope split)
test "check_boundary: GB8 LVT×T (completion)" {
  inspect(check_boundary(LVT, T, 0, ES_None, IC_None), content="false")
}

///|
// Input: prev=RI, cur=RI, ri_count=0 (= no prior RI accumulated before this
// cur — the previous RI was the start of a fresh run).
// Expected: true (boundary — break BEFORE cur).
// Why: ri_count is the count of RIs already absorbed before cur (segmenter
// passes it in before incrementing). At count=0, parity is even, so the
// pair has NOT been joined yet and the boundary fires. This pins the even
// branch at the edge value 0, distinct from the count=2 even case above.
// (DR-0004 — segmenter state parity)
test "check_boundary: GB12/13 RI×RI count=0 -> break (even parity edge)" {
  inspect(
    check_boundary(Regional_Indicator, Regional_Indicator, 0, ES_None, IC_None),
    content="true",
  )
}

///|
// Input: prev=RI, cur=RI, ri_count=3 (= three RIs already absorbed before
// this cur — so cur is the 4th RI in the run).
// Expected: false (no boundary — odd parity joins cur into the 2nd flag).
// Why: Pins the parity rule as a property, not just two samples. Combined
// with ri_count=1 (odd, no break) and ri_count=2 (even, break) above, this
// extends the sample to four points across both parities so a hard-coded
// "ri_count == 1" instead of "ri_count % 2 == 1" type bug surfaces here.
// (DR-0004 — segmenter state parity)
test "check_boundary: GB12/13 RI×RI count=3 -> no break (odd parity, 4th RI)" {
  inspect(
    check_boundary(Regional_Indicator, Regional_Indicator, 3, ES_None, IC_None),
    content="false",
  )
}

///|
// Input: two boundary checks with prev=Other, cur=Other and ri_count=5 vs 0.
// Expected: both equal (= true; GB999 boundary regardless of ri_count).
// Why: Pins the invariant that ri_count is only consulted when both sides
// are Regional_Indicator. Without this, a stray "ri_count > 0" branch in a
// non-RI rule would not be caught by either the RI parity tests or the
// GB999 sample alone.
// (DR-0004 — segmenter state parity)
test "check_boundary: ri_count irrelevant for non-RI (Other×Other invariant)" {
  let with_count = check_boundary(Other, Other, 5, ES_None, IC_None)
  let without_count = check_boundary(Other, Other, 0, ES_None, IC_None)
  assert_eq(with_count, without_count)
  inspect(with_count, content="true")
}

///|
// Input: state=IC_Consonant_Linker_Seen, cur=Extend, cp=U+200C.
// U+200C = Zero Width Non-Joiner (Cf; GCB=Extend but NOT InCB=Extend per
// DerivedCoreProperties.txt — ZWNJ is excluded from the Indic conjunct
// extend set).
// Expected: IC_None (Linker chain broken — the Extend is not Indic-relevant).
// Why: The existing test pins the "stays in Linker_Seen" branch using an
// InCB=Extend code point (U+0900). The other half — Extend that is *not*
// InCB=Extend — must reset the chain so a later InCB_Consonant does not
// suppress its boundary. Without this, swapping is_incb_extend for an
// always-true would still pass the kept-state test.
// (DR-0004 — segmenter state parity)
test "next_incb_state: IC_Consonant_Linker_Seen + non-InCB Extend -> IC_None (chain reset)" {
  inspect(
    next_incb_state(IC_Consonant_Linker_Seen, Extend, 0x200C),
    content="IC_None",
  )
}

///|
// Input: state=ES_None, cur=Other (any non-Extended_Pictographic).
// Expected: ES_None (stays).
// Why: Pins the "idle stays idle" cell of the emoji state matrix. Currently
// only the ES_None -> ES_EP_Seen edge (on EP) is pinned; the no-op edge on
// non-EP was implicit. A bug that accidentally promoted ES_None on Other
// would slip past the existing tests.
// (DR-0004 — segmenter state parity)
test "next_emoji_state: ES_None + Other -> ES_None (idle stays idle)" {
  inspect(next_emoji_state(ES_None, Other), content="ES_None")
}

///|
// Input: state=ES_EP_Extend_ZWJ, cur=Extend.
// Expected: ES_None.
// Why: After EP-Extend*-ZWJ, the only valid continuation is another
// Extended_Pictographic (which restarts the chain to ES_EP_Seen, pinned
// above). A bare Extend at this state does NOT match any branch in
// next_emoji_state and must fall through to ES_None. Pin this edge so a
// future refactor adding "ES_EP_Extend_ZWJ + Extend stays" (incorrect per
// GB11) is caught.
// (DR-0004 — segmenter state parity)
test "next_emoji_state: ES_EP_Extend_ZWJ + Extend -> ES_None" {
  inspect(next_emoji_state(ES_EP_Extend_ZWJ, Extend), content="ES_None")
}

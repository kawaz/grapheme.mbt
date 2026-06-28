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
test "check_boundary: GB3 CR×LF" {
  inspect(check_boundary(CR, LF, 0, ES_None, IC_None), content="false")
}

// GB4: (Control|CR|LF) ÷

///|
test "check_boundary: GB4 Control÷Any" {
  inspect(check_boundary(Control, Other, 0, ES_None, IC_None), content="true")
}

///|
test "check_boundary: GB4 CR÷Any(not LF)" {
  inspect(check_boundary(CR, Other, 0, ES_None, IC_None), content="true")
}

// GB5: ÷ (Control|CR|LF)

///|
test "check_boundary: GB5 Any÷Control" {
  inspect(check_boundary(Other, Control, 0, ES_None, IC_None), content="true")
}

// GB6: L × (L|V|LV|LVT)

///|
test "check_boundary: GB6 L×L" {
  inspect(check_boundary(L, L, 0, ES_None, IC_None), content="false")
}

///|
test "check_boundary: GB6 L×V" {
  inspect(check_boundary(L, V, 0, ES_None, IC_None), content="false")
}

///|
test "check_boundary: GB6 L×LV" {
  inspect(check_boundary(L, LV, 0, ES_None, IC_None), content="false")
}

///|
test "check_boundary: GB6 L×LVT" {
  inspect(check_boundary(L, LVT, 0, ES_None, IC_None), content="false")
}

// GB7: (LV|V) × (V|T)

///|
test "check_boundary: GB7 LV×V" {
  inspect(check_boundary(LV, V, 0, ES_None, IC_None), content="false")
}

///|
test "check_boundary: GB7 V×T" {
  inspect(check_boundary(V, T, 0, ES_None, IC_None), content="false")
}

// GB8: (LVT|T) × T

///|
test "check_boundary: GB8 LVT×T" {
  inspect(check_boundary(LVT, T, 0, ES_None, IC_None), content="false")
}

///|
test "check_boundary: GB8 T×T" {
  inspect(check_boundary(T, T, 0, ES_None, IC_None), content="false")
}

// GB9: × (Extend|ZWJ)

///|
test "check_boundary: GB9 Any×Extend" {
  inspect(check_boundary(Other, Extend, 0, ES_None, IC_None), content="false")
}

///|
test "check_boundary: GB9 Any×ZWJ" {
  inspect(check_boundary(Other, ZWJ, 0, ES_None, IC_None), content="false")
}

// GB9a: × SpacingMark

///|
test "check_boundary: GB9a Any×SpacingMark" {
  inspect(
    check_boundary(Other, SpacingMark, 0, ES_None, IC_None),
    content="false",
  )
}

// GB9b: Prepend ×

///|
test "check_boundary: GB9b Prepend×Any" {
  inspect(check_boundary(Prepend, Other, 0, ES_None, IC_None), content="false")
}

// GB999: Any ÷ Any

///|
test "check_boundary: GB999 Other÷Other" {
  inspect(check_boundary(Other, Other, 0, ES_None, IC_None), content="true")
}

// --- State-dependent rule tests ---

// GB9c: InCB Consonant + [Extend|Linker]* Linker [Extend|Linker]* × InCB_Consonant

///|
test "check_boundary: GB9c Consonant_Linker_Seen × InCB_Consonant" {
  inspect(
    check_boundary(Extend, InCB_Consonant, 0, ES_None, IC_Consonant_Linker_Seen),
    content="false",
  )
}

///|
test "check_boundary: GB9c without linker -> boundary" {
  inspect(
    check_boundary(Extend, InCB_Consonant, 0, ES_None, IC_Consonant_Seen),
    content="true",
  )
}

// GB11: Extended_Pictographic Extend* ZWJ × Extended_Pictographic

///|
test "check_boundary: GB11 EP_Extend_ZWJ × EP" {
  inspect(
    check_boundary(ZWJ, Extended_Pictographic, 0, ES_EP_Extend_ZWJ, IC_None),
    content="false",
  )
}

///|
test "check_boundary: GB11 without EP state -> boundary" {
  inspect(
    check_boundary(ZWJ, Extended_Pictographic, 0, ES_None, IC_None),
    content="true",
  )
}

// GB12/13: RI × RI (odd count -> no break, even count -> break)

///|
test "check_boundary: GB12/13 RI×RI odd count -> no break" {
  inspect(
    check_boundary(Regional_Indicator, Regional_Indicator, 1, ES_None, IC_None),
    content="false",
  )
}

///|
test "check_boundary: GB12/13 RI×RI even count -> break" {
  inspect(
    check_boundary(Regional_Indicator, Regional_Indicator, 2, ES_None, IC_None),
    content="true",
  )
}

// GB4: LF ÷ Any

///|
test "check_boundary: GB4 LF÷Any" {
  inspect(check_boundary(LF, Other, 0, ES_None, IC_None), content="true")
}

// GB9b (Prepend x) vs GB5 (÷ Control) -> GB5 takes priority

///|
test "check_boundary: Prepend÷Control (GB5 wins over GB9b)" {
  inspect(check_boundary(Prepend, Control, 0, ES_None, IC_None), content="true")
}

///|
test "check_boundary: Prepend÷CR (GB5 wins over GB9b)" {
  inspect(check_boundary(Prepend, CR, 0, ES_None, IC_None), content="true")
}

// next_emoji_state transition tests

///|
test "next_emoji_state: EP -> ES_EP_Seen" {
  inspect(
    next_emoji_state(ES_None, Extended_Pictographic),
    content="ES_EP_Seen",
  )
}

///|
test "next_emoji_state: ES_EP_Seen + Extend -> ES_EP_Seen" {
  inspect(next_emoji_state(ES_EP_Seen, Extend), content="ES_EP_Seen")
}

///|
test "next_emoji_state: ES_EP_Seen + ZWJ -> ES_EP_Extend_ZWJ" {
  inspect(next_emoji_state(ES_EP_Seen, ZWJ), content="ES_EP_Extend_ZWJ")
}

///|
test "next_emoji_state: ES_EP_Seen + Other -> ES_None" {
  inspect(next_emoji_state(ES_EP_Seen, Other), content="ES_None")
}

///|
test "next_emoji_state: ES_EP_Extend_ZWJ + EP -> ES_EP_Seen (chain restart)" {
  inspect(
    next_emoji_state(ES_EP_Extend_ZWJ, Extended_Pictographic),
    content="ES_EP_Seen",
  )
}

// next_incb_state transition tests

///|
test "next_incb_state: InCB_Consonant -> IC_Consonant_Seen" {
  inspect(
    next_incb_state(IC_None, InCB_Consonant, 0x0915),
    content="IC_Consonant_Seen",
  )
}

///|
test "next_incb_state: IC_Consonant_Seen + Linker -> IC_Consonant_Linker_Seen" {
  inspect(
    next_incb_state(IC_Consonant_Seen, Extend, 0x094D),
    content="IC_Consonant_Linker_Seen",
  )
}

///|
test "next_incb_state: IC_Consonant_Seen + Other -> IC_None" {
  inspect(next_incb_state(IC_Consonant_Seen, Other, 0x0041), content="IC_None")
}

///|
test "next_incb_state: IC_Consonant_Linker_Seen + InCB_Consonant -> IC_Consonant_Seen" {
  inspect(
    next_incb_state(IC_Consonant_Linker_Seen, InCB_Consonant, 0x0915),
    content="IC_Consonant_Seen",
  )
}

///|
// GB5: Any ÷ LF (explicit test for LF, not just Control)
test "check_boundary: GB5 Any÷LF" {
  inspect(check_boundary(Other, LF, 0, ES_None, IC_None), content="true")
}

///|
// GB5: Any ÷ CR
test "check_boundary: GB5 Any÷CR" {
  inspect(check_boundary(Other, CR, 0, ES_None, IC_None), content="true")
}

///|
// ES_EP_Extend_ZWJ + non-EP → ES_None (reset)
test "next_emoji_state: ES_EP_Extend_ZWJ + Other -> ES_None" {
  inspect(next_emoji_state(ES_EP_Extend_ZWJ, Other), content="ES_None")
}

///|
// IC_Consonant_Linker_Seen + Extend → state maintained
test "next_incb_state: IC_Consonant_Linker_Seen + Extend (InCB Extend) -> IC_Consonant_Linker_Seen" {
  // U+0900 = InCB Extend (Devanagari sign inverted candrabindu)
  inspect(
    next_incb_state(IC_Consonant_Linker_Seen, Extend, 0x0900),
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
test "check_boundary: GB7 LV×T" {
  inspect(check_boundary(LV, T, 0, ES_None, IC_None), content="false")
}

///|
// Input: prev=V, cur=V with all state defaults.
// Expected: false (no boundary).
// Why: GB7 also covers V×V (two vocalic Hangul jamos in a row). V×T is pinned
// above; V×V was missing. Pin it so the GB7 row of the table is fully locked.
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
test "next_emoji_state: ES_EP_Extend_ZWJ + Extend -> ES_None" {
  inspect(next_emoji_state(ES_EP_Extend_ZWJ, Extend), content="ES_None")
}

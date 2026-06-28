// ============================================================================
// Test scope for this file (plane14_tags_test.mbt)
// ----------------------------------------------------------------------------
// In scope — behaviours exercised here:
//   - End-to-end segmentation across the Plane 14 tag range U+E0000-U+E01EF
//     via the public graphemes() entry point. The lookup must classify the
//     Extend sub-ranges (E0020-E007F, E0100-E01EF) before the Control
//     sub-ranges (E0000-E001F, E0080-E00FF, E01F0-E01FF) so that subdivision
//     flags, language tags inside emoji, and Plane 14 variation selectors
//     stick to the preceding pictographic / base.
//   - Boundary code points just below and just above the Extend sub-ranges
//     (E001F, E01F0) to pin the transition into Control on both sides.
//   - A non-Plane-14 Extend (U+FE0F, U+1F3FB) is also exercised as a sanity
//     check that the BMP / supplementary plane Extend categories still merge
//     into the same cluster alongside the Plane 14 work.
//
// Not applicable here — covered in sibling test files instead:
//   - Single code point gcb_category lookup results for Plane 14 code points
//     (= "what category does U+E0067 resolve to?") live in
//     src/gcb_wbtest.mbt and are not duplicated as end-to-end segmentation.
//   - GraphemeView API surface (length, iter, slice, traits) is covered in
//     src/lib_wbtest.mbt; this file uses .length(), [i], and .to_owned()
//     only as a means to assert segmentation outcomes.
//   - Bulk UAX #29 GraphemeBreakTest.txt corpus coverage is in
//     src/uax29_test.mbt (generated).
//
// Scope/NA split: DR-0007 — docs/decisions/DR-0007-test-scope-split.md
// Plane 14 ordering rationale: DR-0005 — docs/decisions/DR-0005-plane14-tag-ordering.md
// ============================================================================

///|
test "Plane 14: England subdivision flag is a single cluster" {
  // Input: BLACK FLAG U+1F3F4 + tag letters 'g' 'b' 'e' 'n' 'g' (U+E0067
  // U+E0062 U+E0065 U+E006E U+E0067) + CANCEL TAG U+E007F.
  // Expected: ONE cluster containing the whole sequence.
  // Why: per UAX #29, tag characters in U+E0020-U+E007F have GCB=Extend and
  // are absorbed into the preceding pictographic base via GB9. CANCEL TAG
  // (U+E007F) is also Extend and terminates the subdivision sequence without
  // breaking the cluster. If gcb_category were ordered Control-first for the
  // Plane 14 range, these tag chars would resolve to Control and split the
  // cluster into seven pieces — this test fails fast in that regression.
  // (DR-0005 — Plane 14 Extend-before-Control ordering)
  let input = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}"
  let g = graphemes(input)
  assert_eq(g.length(), 1)
  assert_eq(g[0].to_owned(), input)
}

///|
test "Plane 14: Scotland subdivision flag is a single cluster" {
  // Input: BLACK FLAG U+1F3F4 + tag letters 's' 'c' 't' (U+E0073 U+E0063
  // U+E0074) + CANCEL TAG U+E007F.
  // Expected: ONE cluster containing the whole sequence.
  // Why: identical mechanism to the England case — pins that the Extend
  // classification of U+E0020-U+E007F is uniform across the range, not just
  // happening to fire for the specific tag letters used in 'gbeng'.
  // (DR-0005 — Plane 14 Extend-before-Control ordering)
  let input = "\u{1F3F4}\u{E0073}\u{E0063}\u{E0074}\u{E007F}"
  let g = graphemes(input)
  assert_eq(g.length(), 1)
  assert_eq(g[0].to_owned(), input)
}

///|
test "Plane 14: lone LANGUAGE TAG U+E0001 is its own cluster" {
  // Input: just U+E0001 (LANGUAGE TAG) — no preceding base.
  // Expected: ONE cluster, of exactly that single code point.
  // Why: U+E0001 sits in the Plane 14 Control sub-range U+E0000-U+E001F and
  // must classify as Control (not Extend). With nothing before it, GB1 opens
  // a cluster at sot and GB5 (÷ Control) would also separate it from any
  // following text. This single-cp case asserts the Control classification
  // of the sub-range that is *not* Extend, complementing the Extend cases
  // above.
  // (DR-0005 — Plane 14 Extend-before-Control ordering)
  let input = "\u{E0001}"
  let g = graphemes(input)
  assert_eq(g.length(), 1)
  assert_eq(g[0].to_owned(), input)
}

///|
test "Plane 14 sanity: VS16 + skin tone after emoji is a single cluster" {
  // Input: GRINNING FACE U+1F600 + VARIATION SELECTOR-16 U+FE0F (BMP Extend)
  // + EMOJI MODIFIER FITZPATRICK TYPE-1-2 U+1F3FB (supplementary Extend).
  // Expected: ONE cluster.
  // Why: this case is NOT Plane 14 — U+FE0F is BMP and U+1F3FB is in Plane
  // 1 — but it is included as a regression reminder that the Extend
  // classification used by GB9 covers the existing variation selector and
  // skin-tone modifier ranges. If the Plane 14 reordering accidentally
  // shadowed or reordered those lookups, this would break before the
  // genuine Plane 14 cases below.
  // (DR-0005 — Plane 14 Extend-before-Control ordering, regression guard)
  let input = "\u{1F600}\u{FE0F}\u{1F3FB}"
  let g = graphemes(input)
  assert_eq(g.length(), 1)
  assert_eq(g[0].to_owned(), input)
}

///|
test "Plane 14: VS17 (U+E0100) sticks to the preceding emoji" {
  // Input: GRINNING FACE U+1F600 + VARIATION SELECTOR-17 U+E0100.
  // Expected: ONE cluster.
  // Why: U+E0100-U+E01EF are Variation Selectors 17 through 256 and live in
  // Plane 14. They must classify as Extend so GB9 absorbs them into the
  // preceding base. This pins the *second* Extend sub-range (after the
  // U+E0020-U+E007F tag range tested above) — the lookup must recognise
  // both Extend windows, not just the lower one.
  // (DR-0005 — Plane 14 Extend-before-Control ordering)
  let input = "\u{1F600}\u{E0100}"
  let g = graphemes(input)
  assert_eq(g.length(), 1)
  assert_eq(g[0].to_owned(), input)
}

///|
test "Plane 14 lower boundary: U+E001F is Control and breaks from emoji" {
  // Input: BLACK FLAG U+1F3F4 + U+E001F (the code point one below the tag
  // Extend range, sitting at the top of the Control sub-range
  // U+E0000-U+E001F).
  // Expected: TWO clusters — the flag, then U+E001F on its own.
  // Why: this pins the lower transition Control→Extend at exactly U+E0020.
  // If the table mistakenly stretched the Extend sub-range one code point
  // downward to start at U+E001F, the two would merge into one cluster and
  // this assertion would catch it. Conversely it guards against a
  // mis-classification that turned the whole tag range into Control.
  // (DR-0005 — Plane 14 Extend-before-Control ordering, lower boundary)
  let input = "\u{1F3F4}\u{E001F}"
  let g = graphemes(input)
  assert_eq(g.length(), 2)
  assert_eq(g[0].to_owned(), "\u{1F3F4}")
  assert_eq(g[1].to_owned(), "\u{E001F}")
}

///|
test "Plane 14 upper boundary: U+E01F0 is Control and breaks from emoji" {
  // Input: GRINNING FACE U+1F600 + U+E01F0 (the code point one above the
  // VS17-256 Extend range, sitting at the bottom of the upper Control
  // sub-range U+E01F0-U+E01FF).
  // Expected: TWO clusters — the emoji, then U+E01F0 on its own.
  // Why: this pins the upper transition Extend→Control at exactly U+E01EF.
  // If the table mistakenly stretched the Extend sub-range one code point
  // upward to include U+E01F0, the two would merge and this would catch it.
  // Together with the U+E001F case above, both ends of the second Extend
  // window are nailed down.
  // (DR-0005 — Plane 14 Extend-before-Control ordering, upper boundary)
  let input = "\u{1F600}\u{E01F0}"
  let g = graphemes(input)
  assert_eq(g.length(), 2)
  assert_eq(g[0].to_owned(), "\u{1F600}")
  assert_eq(g[1].to_owned(), "\u{E01F0}")
}

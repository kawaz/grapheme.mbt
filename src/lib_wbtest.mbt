// ============================================================================
// Test scope for this file (lib_wbtest.mbt)
// ----------------------------------------------------------------------------
// In scope — behaviours exercised here:
//   - GraphemeView public API surface: length, op_get, get, is_empty,
//     to_string, op_as_view, iter, iter2, rev_iter, grapheme_indices.
//   - Trait behaviours implemented on GraphemeView: Eq, Hash, Show.
//   - grapheme_iter() API — the lazy iterator path, including its boundary
//     and termination behaviour without materialising the full view.
//   - GraphemeView invariants: boundary indices are monotonic and aligned to
//     cluster_start/cluster_end, slicing by index returns the expected
//     cluster as a StringView.
//   - Lone surrogate handling at the public API level (input strings that
//     contain unpaired UTF-16 surrogate code units must be segmented without
//     panicking, following the policy fixed for this crate).
//
// Not applicable here — covered in sibling test files instead:
//   - UAX #29 GB1-GB13 grapheme cluster boundary rule coverage is exercised
//     against the official Unicode corpus and via the iterator entry points
//     in src/uax29_test.mbt and src/uax29_iter_test.mbt; do not duplicate
//     rule-by-rule cases here.
//   - Internal segmenter cell coverage (check_boundary, next_emoji_state,
//     next_incb_state state transitions) lives in src/segmenter_wbtest.mbt.
//   - gcb_category lookup edge cases and the Plane 14 tag ordering are
//     covered by src/gcb_wbtest.mbt and src/plane14_tags_test.mbt.
//
// Scope/NA split: DR-0007 — docs/decisions/DR-0007-test-scope-split.md
// ============================================================================

///|
test "graphemes: ASCII string" {
  let g = graphemes("hello")
  inspect(g.length(), content="5")
}

///|
test "graphemes: BMP characters" {
  let g = graphemes("あいう")
  inspect(g.length(), content="3")
}

///|
test "graphemes: surrogate pair characters" {
  let g = graphemes("A\u{1F600}B")
  inspect(g.length(), content="3")
  inspect(g[1].to_owned(), content="\u{1F600}")
}

///|
test "graphemes: iter" {
  let result : Array[String] = []
  for cluster in graphemes("A\u{1F600}B").iter() {
    result.push(cluster.to_owned())
  }
  @debug.debug_inspect(
    result,
    content=(
      #|["A", "😀", "B"]
    ),
  )
}

///|
test "graphemes: empty string" {
  let g = graphemes("")
  inspect(g.length(), content="0")
}

///|
// Combining character: "ka" (U+304B) + combining dakuten (U+3099) -> 1 cluster
test "graphemes: combining character ga" {
  let g = graphemes("\u{304B}\u{3099}")
  inspect(g.length(), content="1")
  inspect(g[0].to_owned(), content="\u{304B}\u{3099}")
}

///|
// CRLF: \r\n -> 1 cluster
test "graphemes: CRLF" {
  let g = graphemes("\r\n")
  inspect(g.length(), content="1")
}

///|
// Around Control: NUL + A -> 2 clusters
test "graphemes: around Control" {
  let g = graphemes("\u{0000}A")
  inspect(g.length(), content="2")
}

///|
// SpacingMark: Devanagari "ka" (U+0915 U+093E) -> 1 cluster
test "graphemes: SpacingMark Devanagari" {
  let g = graphemes("\u{0915}\u{093E}")
  inspect(g.length(), content="1")
}

///|
// Input: two Regional Indicators forming the Japanese flag — U+1F1EF (RI 'J')
// followed by U+1F1F5 (RI 'P'). Expected: a single cluster whose content is the
// full RI pair, because GB12/GB13 binds an even count of RIs together.
// Asserting both length() AND content guards against a regression that collapses
// the count correctly but truncates / re-encodes the cluster string.
// DR-0004 — segmenter state parity (GB12/GB13).
test "graphemes: flag JP" {
  let g = graphemes("\u{1F1EF}\u{1F1F5}")
  inspect(g.length(), content="1")
  inspect(g[0].to_owned(), content="\u{1F1EF}\u{1F1F5}")
}

///|
// Input: four Regional Indicators encoding two consecutive flags — JP
// (U+1F1EF U+1F1F5) immediately followed by US (U+1F1FA U+1F1F8). Expected:
// exactly two clusters, the first being the JP RI pair and the second being the
// US RI pair — GB12/GB13 splits RI runs on even-count boundaries, so the
// fourth RI MUST start a new cluster pair, not extend the first one.
// Asserting per-cluster content prevents a regression that gets the count right
// but mis-routes RI bytes between the two cluster strings.
// DR-0004 — segmenter state parity (GB12/GB13).
test "graphemes: two flags JP+US" {
  let g = graphemes("\u{1F1EF}\u{1F1F5}\u{1F1FA}\u{1F1F8}")
  inspect(g.length(), content="2")
  inspect(g[0].to_owned(), content="\u{1F1EF}\u{1F1F5}")
  inspect(g[1].to_owned(), content="\u{1F1FA}\u{1F1F8}")
}

///|
// Input: a ZWJ-joined family emoji — Man (U+1F468) · ZWJ (U+200D) · Woman
// (U+1F469) · ZWJ · Girl (U+1F467) · ZWJ · Boy (U+1F466). Expected: exactly
// one cluster whose content equals the FULL 7-codepoint sequence. GB11 binds
// EP × (Extend|ZWJ)* × ZWJ × EP across the chain, so every codepoint MUST be
// folded into the single cluster string (not silently dropped or split between
// clusters). Length-only assert would miss a regression that emits 1 cluster
// but loses the trailing Boy or one of the ZWJs.
// DR-0004 — segmenter state parity (GB11 emoji ZWJ).
test "graphemes: family emoji ZWJ" {
  let g = graphemes(
    "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}",
  )
  inspect(g.length(), content="1")
  inspect(
    g[0].to_owned(),
    content="\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}",
  )
}

///|
// Input: a minimal Devanagari InCB conjunct — ka (U+0915, InCB_Consonant) +
// virama (U+094D, InCB_Linker which is also Extend) + ka (U+0915,
// InCB_Consonant). Expected: ONE cluster containing all three codepoints,
// because GB9c forbids breaking between a Consonant and a following Consonant
// when a Linker has appeared since the last Consonant. Pinning the cluster
// CONTENT (not just the count) prevents a regression where the Linker is
// dropped on output or where the trailing Consonant is split out while the
// length still reads 1 due to a stale state flag.
// DR-0004 — segmenter state parity (GB9c InCB).
test "graphemes: InCB Conjunct" {
  let g = graphemes("\u{0915}\u{094D}\u{0915}")
  inspect(g.length(), content="1")
  inspect(g[0].to_owned(), content="\u{0915}\u{094D}\u{0915}")
}

///|
// Input: three Regional Indicators — JP (U+1F1EF U+1F1F5) followed by a lone
// RI 'U' (U+1F1FA). Expected: two clusters — the JP pair, then a singleton
// RI. GB12/GB13 only binds an even-count RI run, so an odd trailing RI MUST
// stand alone (it is NOT silently glued to the previous pair). Pinning the
// per-cluster strings catches a regression that bundles the trailing RI into
// the first cluster while still reporting length=2 somehow.
// DR-0004 — segmenter state parity (GB12/GB13 odd-count RI).
test "graphemes: RI x3" {
  let g = graphemes("\u{1F1EF}\u{1F1F5}\u{1F1FA}")
  inspect(g.length(), content="2")
  inspect(g[0].to_owned(), content="\u{1F1EF}\u{1F1F5}")
  inspect(g[1].to_owned(), content="\u{1F1FA}")
}

///|
// Input: five Regional Indicators — JP (U+1F1EF U+1F1F5), US (U+1F1FA
// U+1F1F8), then a lone trailing RI 'A' (U+1F1E6). Expected: three clusters —
// JP pair, US pair, lone RI. This is the multi-pair extension of "RI x3":
// GB12/GB13 must reset its parity state at every pair boundary so the fifth
// RI ends up alone, NOT extending US. Pinning per-cluster content prevents a
// regression where parity slips and the trailing RI gets absorbed into the
// previous flag string while the count still reads 3.
// DR-0004 — segmenter state parity (GB12/GB13 multi-pair RI).
test "graphemes: RI x5" {
  let g = graphemes("\u{1F1EF}\u{1F1F5}\u{1F1FA}\u{1F1F8}\u{1F1E6}")
  inspect(g.length(), content="3")
  inspect(g[0].to_owned(), content="\u{1F1EF}\u{1F1F5}")
  inspect(g[1].to_owned(), content="\u{1F1FA}\u{1F1F8}")
  inspect(g[2].to_owned(), content="\u{1F1E6}")
}

// ============================================================
// A. op_get boundary value tests
// ============================================================

///|
// Input: a 3-cluster ASCII view "ABC" indexed at i=0. Expected: the StringView
// returned by op_get(0) equals "A", the first cluster. This pins the head-of-view
// boundary contract of op_get: the i=0 slot MUST be the cluster starting at
// boundaries[0] (which by invariant is offset 0 in the source string), not
// boundaries[1]. A regression that off-by-ones the index-to-boundary mapping
// (e.g. returning the cluster at boundaries[i+1..i+2]) would surface here as "B".
test "graphemes: op_get first index" {
  let g = graphemes("ABC")
  inspect(g[0].to_owned(), content="A")
}

///|
// Input: the same 3-cluster ASCII view "ABC" indexed at i=length()-1=2.
// Expected: op_get(length()-1) equals "C", the last cluster. This pins the
// tail-of-view boundary: the highest valid index MUST resolve to the cluster
// whose end equals the source's byte length, i.e. boundaries[length()] is the
// end-of-string sentinel. A regression that treats length() as inclusive
// (off-by-one at the tail) would either panic here or return an empty view.
test "graphemes: op_get last index" {
  let g = graphemes("ABC")
  inspect(g[g.length() - 1].to_owned(), content="C")
}

// ============================================================
// B. Panic tests -- op_get out-of-range access
// ============================================================

///|
// Panic on negative index
test "panic op_get negative index" {
  let g = graphemes("ABC")
  let _ = g[-1]
}

///|
// Panic on index >= length()
test "panic op_get out of range" {
  let g = graphemes("ABC")
  let _ = g[3]
}

///|
// Panic on op_get for empty string
test "panic op_get on empty" {
  let g = graphemes("")
  let _ = g[0]
}

// ============================================================
// C. length() various case tests
// ============================================================

///|
test "graphemes: length of single ASCII char" {
  inspect(graphemes("A").length(), content="1")
}

///|
test "graphemes: length of single emoji" {
  inspect(graphemes("\u{1F600}").length(), content="1")
}

///|
test "graphemes: length of single flag" {
  inspect(graphemes("\u{1F1EF}\u{1F1F5}").length(), content="1")
}

///|
test "graphemes: length of family emoji" {
  inspect(
    graphemes("\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}").length(),
    content="1",
  )
}

// ============================================================
// D. iter() various case tests
// ============================================================

///|
// Input: an empty GraphemeView built from "" and iterated via iter().
// Expected: zero iterations occur (count stays 0). This pins the empty-view
// termination contract of GraphemeView::iter — a view with length()==0 MUST
// produce no elements and exit cleanly, rather than yielding a phantom empty
// cluster or looping. The counter sentinel guards against a regression where
// an off-by-one in the iterator's `i < length()` check yields one bogus item
// at i=0 on an empty view.
test "graphemes: iter empty produces no elements" {
  let g = graphemes("")
  let mut count = 0
  for _cluster in g.iter() {
    count += 1
  }
  inspect(count, content="0")
}

///|
// Input: "A" + U+1F600 (😀, a single-cluster surrogate-pair emoji) + "B",
// iterated via iter() and collected into an Array[String]. Expected: exactly
// three elements in iteration order — "A", "😀", "B". This pins three facets
// of the iter contract at once: (1) iter visits ALL clusters of the view —
// length matches length(); (2) the visit order is left-to-right by source
// byte offset — matches op_get(i) for i=0..length()-1; (3) each yielded
// StringView spans the full cluster including non-BMP codepoints, so the
// emoji is not split across two iterations. A regression that drops the
// trailing "B" or splits the surrogate pair would surface here.
test "graphemes: iter collects all clusters" {
  let g = graphemes("A\u{1F600}B")
  let collected : Array[String] = []
  for cluster in g.iter() {
    collected.push(cluster.to_owned())
  }
  inspect(collected.length(), content="3")
  inspect(collected[0], content="A")
  inspect(collected[1], content="\u{1F600}")
  inspect(collected[2], content="B")
}

// ============================================================
// E. Special string tests
// ============================================================

///|
// Lone ZWJ is 1 cluster
test "graphemes: lone ZWJ" {
  inspect(graphemes("\u{200D}").length(), content="1")
}

///|
// Very long ASCII string
test "graphemes: long ASCII string" {
  let buf = StringBuilder::new()
  for _i = 0; _i < 1000; _i = _i + 1 {
    buf.write_char('A')
  }
  let s = buf.to_string()
  inspect(graphemes(s).length(), content="1000")
}

///|
// Chain of combining marks: 'a' + 10 combining acute accents (U+0301) = 1 cluster
test "graphemes: many combining marks" {
  let buf = StringBuilder::new()
  buf.write_char('a')
  for _i = 0; _i < 10; _i = _i + 1 {
    buf.write_char('\u{0301}')
  }
  let s = buf.to_string()
  inspect(graphemes(s).length(), content="1")
}

///|
// Mixed newlines: \r\n(1) + \n(1) + \r(1) = 3 clusters
test "graphemes: mixed newlines" {
  let g = graphemes("\r\n\n\r")
  inspect(g.length(), content="3")
}

///|
// Lone CR is 1 cluster
test "graphemes: lone CR" {
  inspect(graphemes("\r").length(), content="1")
}

///|
// Lone LF is 1 cluster
test "graphemes: lone LF" {
  inspect(graphemes("\n").length(), content="1")
}

///|
// Extend only (no base character) is 1 cluster
test "graphemes: lone combining mark" {
  inspect(graphemes("\u{0301}").length(), content="1")
}

///|
// Keycap sequence: digit + U+FE0F + U+20E3 = 1 cluster
test "graphemes: keycap sequence" {
  let g = graphemes("1\u{FE0F}\u{20E3}")
  inspect(g.length(), content="1")
}

///|
// Emoji modifier sequence: waving hand + skin tone modifier = 1 cluster
test "graphemes: emoji modifier sequence" {
  let g = graphemes("\u{1F44B}\u{1F3FD}")
  inspect(g.length(), content="1")
}

// ============================================================
// F. graphemes() invariant tests -- all clusters concatenated == original string
// ============================================================

///|
test "graphemes: concatenation invariant ASCII" {
  let input = "Hello World"
  let g = graphemes(input)
  let buf = StringBuilder::new()
  for cluster in g.iter() {
    buf.write_string(cluster.to_owned())
  }
  inspect(buf.to_string(), content="Hello World")
}

///|
test "graphemes: concatenation invariant mixed" {
  let input = "Hello\u{1F1EF}\u{1F1F5}World\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}!"
  let g = graphemes(input)
  let buf = StringBuilder::new()
  for cluster in g.iter() {
    buf.write_string(cluster.to_owned())
  }
  inspect(buf.to_string() == input, content="true")
}

///|
test "graphemes: concatenation invariant empty" {
  let input = ""
  let g = graphemes(input)
  let buf = StringBuilder::new()
  for cluster in g.iter() {
    buf.write_string(cluster.to_owned())
  }
  inspect(buf.to_string(), content="")
}

///|
test "graphemes: concatenation invariant combining marks" {
  // 'a' + combining acute accent + combining grave accent
  let input = "a\u{0301}\u{0300}"
  let g = graphemes(input)
  let buf = StringBuilder::new()
  for cluster in g.iter() {
    buf.write_string(cluster.to_owned())
  }
  inspect(buf.to_string() == input, content="true")
}

///|
// length() and iter() count should match
test "graphemes: length equals iter count" {
  let inputs = [
    "", "A", "ABC", "\u{1F600}", "\r\n", "\u{1F1EF}\u{1F1F5}", "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}",
    "a\u{0301}\u{0302}\u{0303}",
  ]
  for input in inputs {
    let g = graphemes(input)
    let mut count = 0
    for _cluster in g.iter() {
      count += 1
    }
    assert_eq(g.length(), count)
  }
}

// ============================================================
// G. Show trait tests
// ============================================================

///|
test "GraphemeView: Show trait" {
  let g = graphemes("AB")
  let expected =
    #|GraphemeView(["A", "B"])
  inspect(g, content=expected)
}

///|
test "GraphemeView: Show empty" {
  let g = graphemes("")
  let expected =
    #|GraphemeView([])
  inspect(g, content=expected)
}

///|
test "GraphemeView: Show emoji" {
  let g = graphemes("A\u{1F600}B")
  let expected =
    #|GraphemeView(["A", "😀", "B"])
  inspect(g, content=expected)
}

// ============================================================
// H. get() safe access tests
// ============================================================

///|
test "GraphemeView: get valid index" {
  let g = graphemes("ABC")
  let v = g.get(0)
  inspect(!(v is None), content="true")
}

///|
test "GraphemeView: get out of range returns None" {
  let g = graphemes("ABC")
  @debug.debug_inspect(g.get(3), content="None")
}

///|
test "GraphemeView: get negative returns None" {
  let g = graphemes("ABC")
  @debug.debug_inspect(g.get(-1), content="None")
}

///|
test "GraphemeView: get on empty returns None" {
  let g = graphemes("")
  @debug.debug_inspect(g.get(0), content="None")
}

// ============================================================
// I. for-in direct iteration tests
// ============================================================

///|
test "GraphemeView: for-in direct iteration" {
  let g = graphemes("AB")
  let mut count = 0
  for _cluster in g {
    count += 1
  }
  inspect(count, content="2")
}

///|
test "GraphemeView: for-in empty" {
  let g = graphemes("")
  let mut count = 0
  for _cluster in g {
    count += 1
  }
  inspect(count, content="0")
}

// ============================================================
// J. is_empty() tests
// ============================================================

///|
test "GraphemeView: is_empty on empty string" {
  inspect(graphemes("").is_empty(), content="true")
}

///|
test "GraphemeView: is_empty on non-empty string" {
  inspect(graphemes("A").is_empty(), content="false")
}

///|
test "GraphemeView: is_empty on emoji" {
  inspect(graphemes("\u{1F600}").is_empty(), content="false")
}

// ============================================================
// K. to_string() tests
// ============================================================

///|
test "GraphemeView: to_string returns original string" {
  let input = "Hello\u{1F600}World"
  let g = graphemes(input)
  inspect(g.to_string() == input, content="true")
}

///|
test "GraphemeView: to_string empty" {
  inspect(graphemes("").to_string(), content="")
}

///|
test "GraphemeView: to_string preserves combining marks" {
  let input = "a\u{0301}\u{0300}"
  inspect(graphemes(input).to_string() == input, content="true")
}

// ============================================================
// L. op_as_view() slice tests
// ============================================================

///|
test "GraphemeView: slice with op_as_view" {
  let g = graphemes("ABCDE")
  let sliced = g[1:3] // B, C
  inspect(sliced.length(), content="2")
  inspect(sliced[0].to_owned(), content="B")
  inspect(sliced[1].to_owned(), content="C")
}

///|
test "GraphemeView: slice to_string" {
  let g = graphemes("ABCDE")
  let sliced = g[1:3]
  inspect(sliced.to_string(), content="BC")
}

///|
test "GraphemeView: slice full range" {
  let g = graphemes("ABC")
  let sliced = g[0:3]
  inspect(sliced.length(), content="3")
}

///|
test "GraphemeView: slice empty" {
  let g = graphemes("ABC")
  let sliced = g[1:1]
  inspect(sliced.is_empty(), content="true")
}

///|
test "GraphemeView: nested slice" {
  let g = graphemes("ABCDE")
  let s1 = g[1:4] // B, C, D
  let s2 = s1[1:2] // C
  inspect(s2[0].to_owned(), content="C")
}

// ============================================================
// M. iter2() indexed iteration tests
// ============================================================

///|
test "GraphemeView: iter2 indexed iteration" {
  let g = graphemes("A\u{1F600}B")
  let indices : Array[Int] = []
  let values : Array[String] = []
  for i, cluster in g.iter2() {
    indices.push(i)
    values.push(cluster.to_owned())
  }
  @debug.debug_inspect(indices, content="[0, 1, 2]")
  inspect(values[1], content="\u{1F600}")
}

// ============================================================
// N. rev_iter() reverse iteration tests
// ============================================================

///|
test "GraphemeView: rev_iter" {
  let g = graphemes("ABC")
  let result : Array[String] = []
  for cluster in g.rev_iter() {
    result.push(cluster.to_owned())
  }
  let expected =
    #|["C", "B", "A"]
  @debug.debug_inspect(result, content=expected)
}

// ============================================================
// O. Eq trait tests
// ============================================================

///|
// Input: two independently constructed GraphemeView values both built from the
// same source string "Hello". Expected: a == b returns true. This pins the
// reflexive/value-identity facet of Eq for GraphemeView — equality MUST be
// content-based, not identity/pointer-based, so two views over equal cluster
// sequences MUST compare equal even though they are distinct heap objects.
// A regression that compares by underlying String reference identity would
// fail here.
test "GraphemeView: Eq same string" {
  let a = graphemes("Hello")
  let b = graphemes("Hello")
  inspect(a == b, content="true")
}

///|
// Input: two GraphemeView values of identical length (5) but differing cluster
// content — "Hello" vs "World". Expected: a == b returns false. This pins the
// content-discrimination facet of Eq: equality MUST NOT be reduced to a
// length-only check; the per-cluster sequence must be compared. A regression
// that short-circuits on matching length() and returns true would fail here.
test "GraphemeView: Eq different string" {
  let a = graphemes("Hello")
  let b = graphemes("World")
  inspect(a == b, content="false")
}

///|
// Input: two GraphemeView values where one is a strict prefix of the other —
// "AB" (length 2) and "ABC" (length 3). Expected: a == b returns false. This
// pins the length-discrimination facet of Eq: differing length() MUST always
// imply inequality, with no false-positive from matching the shared prefix.
// A regression that stops comparison at min(len(a), len(b)) without checking
// the remaining tail would incorrectly return true here.
test "GraphemeView: Eq different length" {
  let a = graphemes("AB")
  let b = graphemes("ABC")
  inspect(a == b, content="false")
}

///|
// Input: two empty GraphemeView values built from "". Expected: a == b returns
// true. This pins the zero-length boundary of Eq — two views with length()==0
// MUST compare equal (the empty cluster sequence is uniquely equal to itself).
// A regression that special-cases empty inputs and returns false (e.g. via a
// null-check fallthrough) would fail here.
test "GraphemeView: Eq empty" {
  let a = graphemes("")
  let b = graphemes("")
  inspect(a == b, content="true")
}

///|
// Input: a sliced view `graphemes("ABCDE")[1:3]` (clusters B, C) compared to
// a freshly-built view `graphemes("BC")`. Expected: a == b returns true. This
// pins the slice-equivalence facet of Eq: a slice MUST behave as a view over
// its own cluster range, equal in value to a fresh view built from the same
// clusters even though its backing source string and starting boundary offset
// differ. A regression where Eq compares raw source offsets (not the projected
// cluster sequence) would fail here, because a's boundaries are anchored in
// "ABCDE" while b's are anchored in "BC".
test "GraphemeView: Eq sliced" {
  let a = graphemes("ABCDE")[1:3] // B, C
  let b = graphemes("BC")
  inspect(a == b, content="true")
}

// ============================================================
// P. Hash trait tests
// ============================================================

///|
// Input: two independently constructed GraphemeView values from the same
// source string "Hello", whose Eq comparison would yield true (per the Eq
// "same string" case above). Expected: a.hash() equals b.hash(). This pins
// the Hash–Eq consistency contract: if a == b then hash(a) MUST equal
// hash(b), which is the precondition for using GraphemeView as a key in any
// hash-based collection (Map, Set). A regression where Hash mixes in
// implementation-internal state (e.g. backing String identity, slice offset,
// or boundary array address) instead of the projected cluster sequence
// would break this invariant and cause silent lookup failures in HashMap.
test "GraphemeView: Hash consistency with Eq" {
  let a = graphemes("Hello")
  let b = graphemes("Hello")
  // Equal objects must have equal hashes
  assert_eq(a.hash(), b.hash())
}

///|
// Input: a GraphemeView is stored as the KEY of a Map[GraphemeView, Int],
// then retrieved by a freshly built GraphemeView equal to the original.
// Expected: the lookup with the equal-but-distinct view succeeds and returns
// the stored value, which exercises GraphemeView::Hash + GraphemeView::Eq
// together (Map dispatch needs both: hash to find the bucket, eq to confirm
// the key inside the bucket). This is the contract under test — that two
// views considered equal by Eq must land in the same Map slot.
// DR-0004 — segmenter state parity (Eq + Hash composed for Map dispatch).
test "GraphemeView: Hash in HashMap" {
  let map : Map[GraphemeView, Int] = {}
  let key = graphemes("Hello🌍")
  map[key] = key.length()
  let lookup_key = graphemes("Hello🌍")
  inspect(map[lookup_key], content="6")
}

// ============================================================
// Q. Slice edge case tests
// ============================================================

///|
test "GraphemeView: slice emoji preservation" {
  // 絵文字がスライスで壊れないことを確認
  let g = graphemes("A🇯🇵B")
  let sliced = g[1:2]
  inspect(sliced[0].to_owned(), content="🇯🇵")
}

///|
test "GraphemeView: slice then iter" {
  let g = graphemes("ABCDE")
  let sliced = g[1:4]
  let result : Array[String] = []
  for cluster in sliced {
    result.push(cluster.to_owned())
  }
  inspect(result.length(), content="3")
}

///|
test "GraphemeView: slice then iter2" {
  let g = graphemes("ABCDE")
  let sliced = g[1:4]
  let indices : Array[Int] = []
  for i, _cluster in sliced.iter2() {
    indices.push(i)
  }
  // スライス内のインデックスは0始まり
  @debug.debug_inspect(indices, content="[0, 1, 2]")
}

///|
test "GraphemeView: slice then rev_iter" {
  let g = graphemes("ABCDE")
  let sliced = g[1:4]
  let result : Array[String] = []
  for cluster in sliced.rev_iter() {
    result.push(cluster.to_owned())
  }
  let expected =
    #|["D", "C", "B"]
  @debug.debug_inspect(result, content=expected)
}

// ============================================================
// R. op_as_view() open-ended slice tests (coverage for None branches)
// ============================================================

///|
test "GraphemeView: slice open end (g[1:])" {
  let g = graphemes("ABCDE")
  let sliced = g[1:]
  inspect(sliced.length(), content="4")
  inspect(sliced[0].to_owned(), content="B")
}

///|
test "GraphemeView: slice open start (g[:3])" {
  let g = graphemes("ABCDE")
  let sliced = g[:3]
  inspect(sliced.length(), content="3")
  inspect(sliced[0].to_owned(), content="A")
}

///|
test "GraphemeView: slice both open (g[:])" {
  let g = graphemes("ABCDE")
  let sliced = g[:]
  inspect(sliced.length(), content="5")
}

///|
test "GraphemeView: slice negative start clamped to 0" {
  let g = graphemes("ABCDE")
  let sliced = g[-2:3]
  inspect(sliced.length(), content="3")
  inspect(sliced[0].to_owned(), content="A")
}

///|
test "GraphemeView: slice start beyond length clamped" {
  let g = graphemes("ABCDE")
  let sliced = g[10:20]
  inspect(sliced.length(), content="0")
}

///|
test "GraphemeView: slice end beyond length clamped" {
  let g = graphemes("ABCDE")
  let sliced = g[2:100]
  inspect(sliced.length(), content="3")
  inspect(sliced[0].to_owned(), content="C")
}

///|
test "GraphemeView: slice end less than start clamped" {
  let g = graphemes("ABCDE")
  let sliced = g[3:1]
  inspect(sliced.length(), content="0")
}

// ============================================================
// S. grapheme_indices() tests
// ============================================================

///|
test "GraphemeView: grapheme_indices ASCII" {
  let g = graphemes("ABC")
  let offsets : Array[(Int, Int)] = []
  for entry in g.grapheme_indices() {
    offsets.push((entry.0, entry.1))
  }
  // ASCII: 各文字は1コードユニット
  @debug.debug_inspect(offsets, content="[(0, 1), (1, 2), (2, 3)]")
}

///|
test "GraphemeView: grapheme_indices emoji" {
  let g = graphemes("A\u{1F600}B")
  let offsets : Array[(Int, Int)] = []
  for entry in g.grapheme_indices() {
    offsets.push((entry.0, entry.1))
  }
  // 😀 はサロゲートペアで2コードユニット
  @debug.debug_inspect(offsets, content="[(0, 1), (1, 3), (3, 4)]")
}

///|
test "GraphemeView: grapheme_indices empty" {
  let g = graphemes("")
  let offsets : Array[(Int, Int)] = []
  for entry in g.grapheme_indices() {
    offsets.push((entry.0, entry.1))
  }
  @debug.debug_inspect(offsets, content="[]")
}

///|
test "GraphemeView: grapheme_indices sliced" {
  let g = graphemes("ABCDE")
  let sliced = g[1:3]
  let offsets : Array[(Int, Int)] = []
  for entry in sliced.grapheme_indices() {
    offsets.push((entry.0, entry.1))
  }
  // スライスされた場合、オフセットは元の文字列内の位置
  @debug.debug_inspect(offsets, content="[(1, 2), (2, 3)]")
}

///|
test "GraphemeView: grapheme_indices cluster content" {
  let g = graphemes("A\u{1F600}B")
  let clusters : Array[String] = []
  for entry in g.grapheme_indices() {
    clusters.push(entry.2.to_owned())
  }
  @debug.debug_inspect(
    clusters,
    content=(
      #|["A", "😀", "B"]
    ),
  )
}

// ============================================================
// T. Broken/special Unicode code point tests
// ============================================================

///|
test "graphemes: replacement character U+FFFD" {
  let g = graphemes("\u{FFFD}")
  inspect(g.length(), content="1")
  inspect(g[0].to_owned(), content="\u{FFFD}")
}

///|
test "graphemes: multiple replacement characters" {
  let g = graphemes("\u{FFFD}\u{FFFD}\u{FFFD}")
  inspect(g.length(), content="3")
}

///|
test "graphemes: BOM U+FEFF is Control, breaks cluster" {
  // BOM (GCB=Control) should be its own cluster and break from text
  let g = graphemes("\u{FEFF}text")
  inspect(g.length(), content="5") // BOM + t + e + x + t
  inspect(g[0].to_owned(), content="\u{FEFF}")
}

///|
test "graphemes: BOM between text" {
  let g = graphemes("A\u{FEFF}B")
  // Control breaks both sides (GB4+GB5): A | BOM | B
  inspect(g.length(), content="3")
}

///|
test "graphemes: private use area U+E000" {
  let g = graphemes("\u{E000}")
  inspect(g.length(), content="1")
}

///|
test "graphemes: private use area with combining mark" {
  // PUA char + combining acute accent = 1 cluster (GB9: × Extend)
  let g = graphemes("\u{E000}\u{0301}")
  inspect(g.length(), content="1")
}

///|
test "graphemes: noncharacter U+FFFF" {
  let g = graphemes("\u{FFFF}")
  inspect(g.length(), content="1")
}

///|
test "graphemes: noncharacter U+FDD0" {
  let g = graphemes("\u{FDD0}")
  inspect(g.length(), content="1")
}

///|
test "graphemes: noncharacter U+FDEF" {
  let g = graphemes("\u{FDEF}")
  inspect(g.length(), content="1")
}

///|
test "graphemes: noncharacter U+1FFFE" {
  let g = graphemes("\u{1FFFE}")
  inspect(g.length(), content="1")
}

///|
test "graphemes: mixed special codepoints" {
  // FFFD (Other) + FEFF (Control) + E000 (Other) + FFFF (Other)
  // = FFFD | FEFF | E000 | FFFF (Control breaks both sides)
  let g = graphemes("\u{FFFD}\u{FEFF}\u{E000}\u{FFFF}")
  inspect(g.length(), content="4")
}

// ============================================================
// U. grapheme_indices() edge case tests
// ============================================================

///|
test "grapheme_indices: single character" {
  let g = graphemes("X")
  let offsets : Array[(Int, Int)] = []
  for entry in g.grapheme_indices() {
    offsets.push((entry.0, entry.1))
  }
  @debug.debug_inspect(offsets, content="[(0, 1)]")
}

///|
test "grapheme_indices: combining character cluster" {
  // 'a' + combining acute = 1 cluster spanning 2 code units
  let g = graphemes("a\u{0301}")
  let offsets : Array[(Int, Int)] = []
  for entry in g.grapheme_indices() {
    offsets.push((entry.0, entry.1))
  }
  @debug.debug_inspect(offsets, content="[(0, 2)]")
}

///|
test "grapheme_indices: CRLF cluster" {
  let g = graphemes("\r\n")
  let offsets : Array[(Int, Int)] = []
  for entry in g.grapheme_indices() {
    offsets.push((entry.0, entry.1))
  }
  @debug.debug_inspect(offsets, content="[(0, 2)]")
}

///|
test "grapheme_indices: sliced single element" {
  let g = graphemes("ABCDE")[2:3]
  let offsets : Array[(Int, Int)] = []
  for entry in g.grapheme_indices() {
    offsets.push((entry.0, entry.1))
  }
  // Offset refers to position in original string
  @debug.debug_inspect(offsets, content="[(2, 3)]")
}

// ============================================================
// V. iter2() boundary tests
// ============================================================

///|
test "iter2: empty" {
  let g = graphemes("")
  let indices : Array[Int] = []
  for i, _cluster in g.iter2() {
    indices.push(i)
  }
  @debug.debug_inspect(indices, content="[]")
}

///|
test "iter2: single element" {
  let g = graphemes("Z")
  let indices : Array[Int] = []
  let values : Array[String] = []
  for i, cluster in g.iter2() {
    indices.push(i)
    values.push(cluster.to_owned())
  }
  @debug.debug_inspect(indices, content="[0]")
  @debug.debug_inspect(values, content="[\"Z\"]")
}

///|
test "iter2: on sliced view indices are 0-based" {
  let g = graphemes("ABCDE")[2:5]
  let indices : Array[Int] = []
  let values : Array[String] = []
  for i, cluster in g.iter2() {
    indices.push(i)
    values.push(cluster.to_owned())
  }
  @debug.debug_inspect(indices, content="[0, 1, 2]")
  @debug.debug_inspect(values, content="[\"C\", \"D\", \"E\"]")
}

// ============================================================
// W. rev_iter() boundary tests
// ============================================================

///|
test "rev_iter: empty" {
  let g = graphemes("")
  let result : Array[String] = []
  for cluster in g.rev_iter() {
    result.push(cluster.to_owned())
  }
  @debug.debug_inspect(result, content="[]")
}

///|
test "rev_iter: single element" {
  let g = graphemes("Q")
  let result : Array[String] = []
  for cluster in g.rev_iter() {
    result.push(cluster.to_owned())
  }
  @debug.debug_inspect(result, content="[\"Q\"]")
}

///|
test "rev_iter: on sliced view" {
  let g = graphemes("ABCDE")[1:4]
  let result : Array[String] = []
  for cluster in g.rev_iter() {
    result.push(cluster.to_owned())
  }
  let expected =
    #|["D", "C", "B"]
  @debug.debug_inspect(result, content=expected)
}

// ============================================================
// X. Eq boundary tests
// ============================================================

///|
test "Eq: NFC vs NFD are not equal (different codepoints)" {
  // U+304C (が, precomposed) vs U+304B + U+3099 (か + combining dakuten)
  // These are different code point sequences, so Eq should be false
  let nfc = graphemes("\u{304C}")
  let nfd = graphemes("\u{304B}\u{3099}")
  // Both are 1 cluster but different string content
  inspect(nfc.length(), content="1")
  inspect(nfd.length(), content="1")
  inspect(nfc == nfd, content="false")
}

///|
test "Eq: sliced vs full with same content" {
  let full = graphemes("BC")
  let sliced = graphemes("ABCDE")[1:3]
  inspect(full == sliced, content="true")
}

///|
test "Eq: empty sliced vs empty full" {
  let a = graphemes("")
  let b = graphemes("ABC")[2:2]
  inspect(a == b, content="true")
}

///|
test "Eq: single cluster with combining marks" {
  let a = graphemes("a\u{0301}")
  let b = graphemes("a\u{0301}")
  inspect(a == b, content="true")
}

// ============================================================
// Y. Hash boundary tests
// ============================================================

///|
test "Hash: sliced view has consistent hash with equal full view" {
  let full = graphemes("BC")
  let sliced = graphemes("ABCDE")[1:3]
  inspect(full.hash() == sliced.hash(), content="true")
}

///|
test "Hash: empty views have same hash" {
  let a = graphemes("")
  let b = graphemes("XYZ")[1:1]
  inspect(a.hash() == b.hash(), content="true")
}

// ============================================================
// Z. Show boundary tests
// ============================================================

///|
test "Show: sliced view" {
  let g = graphemes("ABCDE")[1:3]
  inspect(g, content="GraphemeView([\"B\", \"C\"])")
}

///|
test "Show: single cluster with combining mark" {
  let g = graphemes("a\u{0301}")
  // Combining acute accent renders as part of 'a'
  inspect(g.length(), content="1")
  let s = g.to_string()
  inspect(s.iter().count(), content="2") // 2 code points
}

///|
test "Show: special characters" {
  let g = graphemes("\u{FFFD}")
  inspect(g, content="GraphemeView([\"\u{FFFD}\"])")
}

// ============================================================
// AA. to_string boundary tests
// ============================================================

///|
test "to_string: sliced view returns substring" {
  let g = graphemes("ABCDE")[1:3]
  inspect(g.to_string(), content="BC")
}

///|
test "to_string: sliced view with emoji" {
  let g = graphemes("A\u{1F600}B")[0:2]
  inspect(g.to_string(), content="A\u{1F600}")
}

///|
test "to_string: empty slice" {
  let g = graphemes("ABCDE")[3:3]
  inspect(g.to_string(), content="")
}

///|
test "to_string: full slice equals original" {
  let input = "Hello\u{1F600}World"
  let g = graphemes(input)
  inspect(g[:].to_string() == input, content="true")
}

// ============================================================
// AB. Extreme input tests
// ============================================================

///|
// Input: a base 'a' followed by 100 combining acute accents (U+0301 × 100).
// Expected: exactly ONE cluster whose content is the FULL 101-codepoint
// string (the base plus all 100 combining marks, in order). GB9 binds Any ×
// Extend without limit, so the segmenter MUST keep extending the same cluster
// for every Extend. Pinning the cluster STRING (not just count==1 and the
// view-level to_string() invariant, which compares whole views) catches a
// regression where the per-cluster boundary is correct but the cluster's own
// to_owned() truncates / loses combining marks past some internal buffer
// length.
// DR-0004 — segmenter state parity (GB9 long Extend run).
test "graphemes: very long combining mark sequence (100 marks)" {
  let buf = StringBuilder::new()
  buf.write_char('a')
  for i = 0; i < 100; i = i + 1 {
    buf.write_char('\u{0301}')
  }
  let s = buf.to_string()
  let g = graphemes(s)
  inspect(g.length(), content="1")
  // The single cluster must contain the full base+100-marks string.
  inspect(g[0].to_owned() == s, content="true")
  // View-level concatenation invariant (separate contract).
  inspect(g.to_string() == s, content="true")
}

///|
test "graphemes: alternating control and text" {
  // NUL(Control) + A + NUL(Control) + B + NUL(Control) + C
  // GB4/GB5: Control always breaks both sides
  // NUL | A | NUL | B | NUL | C = 6 clusters... wait
  // Actually "\u{0000}A\u{0000}B\u{0000}C"
  // GB5: ÷ Control for first NUL from sot
  // GB4: Control ÷ A
  // GB5: A ÷ Control (NUL)
  // GB4: Control ÷ B
  // GB5: B ÷ Control
  // GB4: Control ÷ C
  // So: NUL | A | NUL | B | NUL | C = 6 clusters
  // But the prompt says "A\u{0000}B\u{0000}C"
  let g = graphemes("A\u{0000}B\u{0000}C")
  // A | NUL | B | NUL | C = 5 clusters
  inspect(g.length(), content="5")
}

///|
test "graphemes: only control characters" {
  let g = graphemes("\u{0000}\u{0001}\u{001F}")
  // Each control character is its own cluster (GB4: Control ÷, GB5: ÷ Control)
  inspect(g.length(), content="3")
}

///|
test "graphemes: mixed CRLF and LF" {
  // \r\n (CRLF=1) + \r\n (CRLF=1) + \n (LF=1) + \r\n (CRLF=1) = 4 clusters
  let g = graphemes("\r\n\r\n\n\r\n")
  inspect(g.length(), content="4")
}

///|
test "graphemes: CR LF CR LF pattern" {
  let g = graphemes("\r\n\r\n")
  inspect(g.length(), content="2")
}

///|
test "graphemes: isolated CR between text" {
  // A + CR + B = 3 clusters (GB4: CR ÷, GB5: ÷ CR)
  let g = graphemes("A\rB")
  inspect(g.length(), content="3")
}

///|
test "graphemes: isolated LF between text" {
  // A + LF + B = 3 clusters
  let g = graphemes("A\nB")
  inspect(g.length(), content="3")
}

///|
test "graphemes: CR not followed by LF" {
  // CR + A = 2 clusters (GB4: CR ÷)
  let g = graphemes("\rA")
  inspect(g.length(), content="2")
}

///|
test "graphemes: string of only CRLFs" {
  let g = graphemes("\r\n\r\n\r\n")
  inspect(g.length(), content="3")
}

///|
test "graphemes: Prepend character" {
  // Arabic Number Sign U+0600 (Prepend) + digit
  // GB9b: Prepend × Any, so they form 1 cluster
  let g = graphemes("\u{0600}1")
  inspect(g.length(), content="1")
}

///|
test "graphemes: Prepend before Control breaks (GB5 over GB9b)" {
  // Prepend + Control: GB5 (÷ Control) takes priority over GB9b (Prepend ×)
  let g = graphemes("\u{0600}\u{0000}")
  inspect(g.length(), content="2")
}

///|
test "graphemes: multiple Prepend characters" {
  // Prepend + Prepend + A: GB9b chains: Prepend × Prepend × A = 1 cluster
  let g = graphemes("\u{0600}\u{0600}A")
  inspect(g.length(), content="1")
}

///|
// Input: Hangul jamo sequence Leading (U+1100) · Vowel (U+1161) · Trailing
// (U+11A8). Expected: one cluster containing all three jamo, because GB6 binds
// L × V and GB7 binds V × T. Pinning the cluster content prevents a regression
// where a length-only check passes but one of the jamo is dropped or pushed
// into a separate cluster.
// DR-0004 — segmenter state parity (GB6/GB7/GB8 Hangul).
test "graphemes: Hangul L V T sequence" {
  let g = graphemes("\u{1100}\u{1161}\u{11A8}")
  inspect(g.length(), content="1")
  inspect(g[0].to_owned(), content="\u{1100}\u{1161}\u{11A8}")
}

///|
// Input: precomposed Hangul LV syllable (U+AC00, "가") followed by a Trailing
// jamo (U+11A8). Expected: one cluster fusing LV and T, because GB8 binds
// (LV|LVT) × T even when the LV part is a precomposed syllable. Pinning the
// cluster content guards against the regression where the trailing jamo is
// silently emitted as its own cluster while length somehow stays at 1.
// DR-0004 — segmenter state parity (GB8 LV+T fusion).
test "graphemes: Hangul LV + T" {
  let g = graphemes("\u{AC00}\u{11A8}")
  inspect(g.length(), content="1")
  inspect(g[0].to_owned(), content="\u{AC00}\u{11A8}")
}

///|
// Input: a single precomposed Hangul LVT syllable (U+AC01, "각"). Expected:
// one cluster whose content is exactly that codepoint. This pins the trivial
// case so a regression that misclassifies LVT as something needing further
// state would be caught immediately.
// DR-0004 — segmenter state parity (Hangul LVT classification).
test "graphemes: Hangul LVT alone" {
  let g = graphemes("\u{AC01}")
  inspect(g.length(), content="1")
  inspect(g[0].to_owned(), content="\u{AC01}")
}

///|
// Input: Leading jamo (U+1100) followed by a precomposed LV syllable (U+AC00)
// followed by a Trailing jamo (U+11A8). Expected: ONE cluster containing the
// full three-codepoint run. GB6 lets L × LV (because LV starts with V-class
// semantics) and GB8 then binds LV × T. Pinning the cluster content prevents
// a regression where the boundary between L and the precomposed LV is mis-
// handled while the count stays right by accident.
// DR-0004 — segmenter state parity (GB6 L+LV, GB8 LV+T).
test "graphemes: Hangul L + LV + T" {
  let g = graphemes("\u{1100}\u{AC00}\u{11A8}")
  inspect(g.length(), content="1")
  inspect(g[0].to_owned(), content="\u{1100}\u{AC00}\u{11A8}")
}

///|
// Input: two adjacent precomposed Hangul syllables — LV (U+AC00) immediately
// followed by LVT (U+AC01). Expected: TWO clusters, each containing exactly
// one syllable. There is NO Hangul rule that joins LV × LVT (only L/V/T or
// LV/LVT followed by V/T), so this pair MUST break. Pinning per-cluster
// content prevents a regression that erroneously fuses the two syllables into
// one (length 1) or that splits the bytes oddly across the boundary.
// DR-0004 — segmenter state parity (Hangul no-rule pair must break).
test "graphemes: Hangul two syllables" {
  let g = graphemes("\u{AC00}\u{AC01}")
  inspect(g.length(), content="2")
  inspect(g[0].to_owned(), content="\u{AC00}")
  inspect(g[1].to_owned(), content="\u{AC01}")
}

///|
test "graphemes: emoji with skin tone and ZWJ" {
  // Woman U+1F469 + skin tone U+1F3FB + ZWJ U+200D + laptop U+1F4BB = 1 cluster
  let g = graphemes("\u{1F469}\u{1F3FB}\u{200D}\u{1F4BB}")
  inspect(g.length(), content="1")
}

///|
test "graphemes: ZWJ between non-emoji creates boundary" {
  // A + ZWJ + B: ZWJ is Extend-like (GB9: × ZWJ), but B is not EP
  // A + ZWJ form 1 cluster, B is separate = 2 clusters
  let g = graphemes("A\u{200D}B")
  inspect(g.length(), content="2")
}

///|
// Input: a Devanagari triple conjunct — ka (U+0915) · virama (U+094D) · ka ·
// virama · ka. Expected: ONE cluster containing the full five-codepoint run.
// GB9c chains InCB indefinitely as long as each Consonant→Consonant transition
// has a Linker in between, so the second virama MUST also be absorbed and the
// third ka MUST NOT start a new cluster. Pinning the cluster content prevents
// a regression where state is reset after the first conjunct and the trailing
// "virama+ka" leaks out as additional clusters while length looks plausible
// (e.g. some refactor reads length from a stale running counter).
// DR-0004 — segmenter state parity (GB9c InCB chaining).
test "graphemes: InCB triple conjunct" {
  let g = graphemes("\u{0915}\u{094D}\u{0915}\u{094D}\u{0915}")
  inspect(g.length(), content="1")
  inspect(g[0].to_owned(), content="\u{0915}\u{094D}\u{0915}\u{094D}\u{0915}")
}

///|
test "graphemes: InCB without linker breaks" {
  // ka + ka = 2 clusters (no virama/linker between them)
  let g = graphemes("\u{0915}\u{0915}")
  inspect(g.length(), content="2")
}

///|
test "graphemes: single regional indicator" {
  // Single RI = 1 cluster
  let g = graphemes("\u{1F1E6}")
  inspect(g.length(), content="1")
}

///|
test "graphemes: four regional indicators" {
  // RI RI RI RI = 2 flags = 2 clusters
  let g = graphemes("\u{1F1E6}\u{1F1E7}\u{1F1E8}\u{1F1E9}")
  inspect(g.length(), content="2")
}

///|
test "graphemes: six regional indicators" {
  // RI x6 = 3 flags = 3 clusters
  let g = graphemes("\u{1F1E6}\u{1F1E7}\u{1F1E8}\u{1F1E9}\u{1F1EA}\u{1F1EB}")
  inspect(g.length(), content="3")
}

// ============================================================
// AC. op_as_view() panic/non-panic boundary tests
// ============================================================

///|
test "op_as_view: extreme negative start does not panic" {
  let g = graphemes("ABC")
  let sliced = g[-100:2]
  inspect(sliced.length(), content="2")
}

///|
test "op_as_view: extreme large end does not panic" {
  let g = graphemes("ABC")
  let sliced = g[0:1000]
  inspect(sliced.length(), content="3")
}

///|
test "op_as_view: both extreme does not panic" {
  let g = graphemes("ABC")
  let sliced = g[-100:1000]
  inspect(sliced.length(), content="3")
}

///|
test "op_as_view: start equals length" {
  let g = graphemes("ABC")
  let sliced = g[3:3]
  inspect(sliced.length(), content="0")
  inspect(sliced.is_empty(), content="true")
}

///|
test "op_as_view: on empty view" {
  let g = graphemes("")
  let sliced = g[0:0]
  inspect(sliced.length(), content="0")
}

///|
test "op_as_view: slice of a slice" {
  let g = graphemes("ABCDEFGH")
  let s1 = g[2:6] // C D E F
  let s2 = s1[1:3] // D E
  inspect(s2.length(), content="2")
  inspect(s2[0].to_owned(), content="D")
  inspect(s2[1].to_owned(), content="E")
}

///|
test "op_as_view: triple nested slice" {
  let g = graphemes("ABCDEFGHIJ")
  let s1 = g[1:9] // B C D E F G H I
  let s2 = s1[2:6] // D E F G
  let s3 = s2[1:3] // E F
  inspect(s3.length(), content="2")
  inspect(s3[0].to_owned(), content="E")
  inspect(s3[1].to_owned(), content="F")
}

// ============================================================
// AD. get() additional edge cases
// ============================================================

///|
test "get: first element of sliced view" {
  let g = graphemes("ABCDE")[2:4]
  @debug.debug_inspect(
    g.get(0).map(fn(v) { v.to_owned() }),
    content="Some(\"C\")",
  )
}

///|
test "get: last element of sliced view" {
  let g = graphemes("ABCDE")[2:4]
  @debug.debug_inspect(
    g.get(1).map(fn(v) { v.to_owned() }),
    content="Some(\"D\")",
  )
}

///|
test "get: out of range on sliced view" {
  let g = graphemes("ABCDE")[2:4]
  @debug.debug_inspect(g.get(2), content="None")
}

///|
test "get: negative on sliced view" {
  let g = graphemes("ABCDE")[2:4]
  @debug.debug_inspect(g.get(-1), content="None")
}

// ============================================================
// AE. is_empty() on sliced views
// ============================================================

///|
test "is_empty: empty slice of non-empty" {
  let g = graphemes("ABC")[1:1]
  inspect(g.is_empty(), content="true")
}

///|
test "is_empty: non-empty slice" {
  let g = graphemes("ABC")[1:2]
  inspect(g.is_empty(), content="false")
}

// ============================================================
// AF. Concatenation invariant tests for special strings
// ============================================================

///|
test "graphemes: concatenation invariant for CRLF" {
  let input = "\r\n\r\nA\r\n"
  let g = graphemes(input)
  let buf = StringBuilder::new()
  for cluster in g.iter() {
    buf.write_string(cluster.to_owned())
  }
  inspect(buf.to_string() == input, content="true")
}

///|
test "graphemes: concatenation invariant for control characters" {
  let input = "\u{0000}\u{0001}\u{001F}A"
  let g = graphemes(input)
  let buf = StringBuilder::new()
  for cluster in g.iter() {
    buf.write_string(cluster.to_owned())
  }
  inspect(buf.to_string() == input, content="true")
}

///|
test "graphemes: concatenation invariant for BOM" {
  let input = "\u{FEFF}Hello"
  let g = graphemes(input)
  let buf = StringBuilder::new()
  for cluster in g.iter() {
    buf.write_string(cluster.to_owned())
  }
  inspect(buf.to_string() == input, content="true")
}

///|
test "graphemes: concatenation invariant for special codepoints" {
  let input = "\u{FFFD}\u{E000}\u{FFFF}\u{FDD0}"
  let g = graphemes(input)
  let buf = StringBuilder::new()
  for cluster in g.iter() {
    buf.write_string(cluster.to_owned())
  }
  inspect(buf.to_string() == input, content="true")
}

///|
// Input: a base 'a' followed by 50 combining acute accents (U+0301 × 50).
// Expected: iterating the view's clusters and concatenating their owned
// strings yields exactly the original input — i.e. graphemes() is a
// loss-less partition. Additionally pin cluster COUNT == 1 and cluster
// CONTENT == full input, so a regression where the partition is loss-less
// but emits the 50 marks as separate clusters (length grows, but concat
// invariant holds) is also caught.
// DR-0004 — segmenter state parity (concat invariant + single-cluster Extend run).
test "graphemes: concatenation invariant for long combining marks" {
  let buf = StringBuilder::new()
  buf.write_char('a')
  for i = 0; i < 50; i = i + 1 {
    buf.write_char('\u{0301}')
  }
  let input = buf.to_string()
  let g = graphemes(input)
  inspect(g.length(), content="1")
  inspect(g[0].to_owned() == input, content="true")
  let buf2 = StringBuilder::new()
  for cluster in g.iter() {
    buf2.write_string(cluster.to_owned())
  }
  inspect(buf2.to_string() == input, content="true")
}

// ============================================================
// AG. grapheme_indices() on empty slice
// ============================================================

///|
test "grapheme_indices: on empty slice" {
  let g = graphemes("ABCDE")[2:2]
  let offsets : Array[(Int, Int)] = []
  for entry in g.grapheme_indices() {
    offsets.push((entry.0, entry.1))
  }
  @debug.debug_inspect(offsets, content="[]")
}

///|
test "grapheme_indices: on full emoji string" {
  let g = graphemes("\u{1F1EF}\u{1F1F5}A")
  let offsets : Array[(Int, Int)] = []
  for entry in g.grapheme_indices() {
    offsets.push((entry.0, entry.1))
  }
  // Flag: 2+2=4 code units, A: 1 code unit
  @debug.debug_inspect(offsets, content="[(0, 4), (4, 5)]")
}

// ============================================================
// AH. rev_iter on sliced view with emoji
// ============================================================

///|
test "rev_iter: sliced view with emoji" {
  let g = graphemes("A\u{1F600}BC")[1:3]
  let result : Array[String] = []
  for cluster in g.rev_iter() {
    result.push(cluster.to_owned())
  }
  @debug.debug_inspect(
    result,
    content=(
      #|["B", "😀"]
    ),
  )
}

// ============================================================
// AI. iter() early termination
// ============================================================

///|
test "iter: break early" {
  let g = graphemes("ABCDE")
  let result : Array[String] = []
  for cluster in g.iter() {
    if result.length() >= 2 {
      break
    }
    result.push(cluster.to_owned())
  }
  @debug.debug_inspect(result, content="[\"A\", \"B\"]")
}

// ============================================================
// AJ. Eq and Hash with emoji content
// ============================================================

///|
test "Eq: emoji sliced vs full" {
  let full = graphemes("\u{1F600}")
  let sliced = graphemes("A\u{1F600}B")[1:2]
  inspect(full == sliced, content="true")
}

///|
test "Hash: emoji sliced vs full" {
  let full = graphemes("\u{1F600}")
  let sliced = graphemes("A\u{1F600}B")[1:2]
  inspect(full.hash() == sliced.hash(), content="true")
}

// ============================================================
// AK. Edge case: string consisting only of Extend characters
// ============================================================

///|
test "graphemes: multiple lone combining marks" {
  // Multiple Extend characters without base: GB9 (× Extend) chains them
  // First one starts from sot (GB1), subsequent ones join via GB9
  let g = graphemes("\u{0301}\u{0302}\u{0303}")
  inspect(g.length(), content="1")
}

///|
test "graphemes: extend after control" {
  // Control + Extend: GB4 (Control ÷), so they are separate
  let g = graphemes("\u{0000}\u{0301}")
  inspect(g.length(), content="2")
}

///|
test "graphemes: ZWJ only string" {
  // Multiple ZWJs: GB9 (× ZWJ) chains
  let g = graphemes("\u{200D}\u{200D}\u{200D}")
  inspect(g.length(), content="1")
}

// ============================================================
// AL. SpacingMark edge cases
// ============================================================

///|
test "graphemes: SpacingMark after Control does not merge" {
  // Control + SpacingMark: GB4 (Control ÷) takes precedence over GB9a (× SpacingMark)
  let g = graphemes("\u{0000}\u{093E}")
  inspect(g.length(), content="2")
}

///|
test "graphemes: SpacingMark after text merges" {
  // Devanagari Ka + SpacingMark AA = 1 cluster (GB9a)
  let g = graphemes("\u{0915}\u{093E}")
  inspect(g.length(), content="1")
}

// ============================================================
// AM. length() and iter() consistency on sliced views
// ============================================================

///|
test "graphemes: length equals iter count on sliced view" {
  let g = graphemes("A\u{1F600}B\u{1F1EF}\u{1F1F5}CD")[1:5]
  let mut count = 0
  for _cluster in g.iter() {
    count += 1
  }
  assert_eq(g.length(), count)
}

///|
test "graphemes: length equals iter2 count on sliced view" {
  let g = graphemes("ABCDEFGH")[2:6]
  let mut count = 0
  for _i, _cluster in g.iter2() {
    count += 1
  }
  assert_eq(g.length(), count)
}

///|
test "graphemes: length equals rev_iter count" {
  let g = graphemes("A\u{1F600}BC")
  let mut count = 0
  for _cluster in g.rev_iter() {
    count += 1
  }
  assert_eq(g.length(), count)
}

///|
test "graphemes: length equals rev_iter count on sliced" {
  let g = graphemes("ABCDE")[1:4]
  let mut count = 0
  for _cluster in g.rev_iter() {
    count += 1
  }
  assert_eq(g.length(), count)
}

// ============================================================
// AN. Multi-script real-world text tests (linguist review)
// ============================================================

///|
// Subdivision flag: Wales 🏴󠁧󠁢󠁷󠁬󠁳󠁿 = EP + tag characters (Extend) = 1 cluster
test "graphemes: subdivision flag Wales" {
  // U+1F3F4 U+E0067 U+E0062 U+E0077 U+E006C U+E0073 U+E007F
  let g = graphemes(
    "\u{1F3F4}\u{E0067}\u{E0062}\u{E0077}\u{E006C}\u{E0073}\u{E007F}",
  )
  inspect(g.length(), content="1")
}

///|
// Thai text: สวัสดี (sawatdee) — base + combining marks
// ส=Other, ว=Other, ั(U+0E31)=Extend, ส=Other, ด=Other, ี(U+0E35)=Extend
// GB9 (× Extend): ส | วั | ส | ดี = 4 clusters
test "graphemes: Thai sawatdee" {
  let g = graphemes("สวัสดี")
  inspect(g.length(), content="4")
}

///|
// Arabic text with combining marks: بِسْمِ (bismillah start)
// U+0628(ba)=Other, U+0650(kasra)=Extend, U+0633(sin)=Other,
// U+0652(sukun)=Extend, U+0645(mim)=Other, U+0650(kasra)=Extend
// GB9 (× Extend): بِ(1) سْ(1) مِ(1) = 3 clusters
test "graphemes: Arabic with diacritics" {
  let g = graphemes("\u{0628}\u{0650}\u{0633}\u{0652}\u{0645}\u{0650}")
  inspect(g.length(), content="3")
}

///|
// Tibetan: ༄༅ (head mark)
// U+0F04=Other, U+0F05=Other → 2 clusters
test "graphemes: Tibetan head mark" {
  let g = graphemes("\u{0F04}\u{0F05}")
  inspect(g.length(), content="2")
}

///|
// Myanmar: က + ္ + က (kinzi-like conjunct)
// U+1000(ka)=InCB_Consonant, U+1039(virama)=InCB Linker, U+1000(ka)=InCB_Consonant
// Since Unicode 17.0.0, Myanmar is in InCB.
// GB9c: Consonant + Linker + Consonant = 1 cluster
test "graphemes: Myanmar conjunct" {
  let g = graphemes("\u{1000}\u{1039}\u{1000}")
  inspect(g.length(), content="1")
}

///|
// Concatenation invariant for multi-script text (Thai)
test "graphemes: concatenation invariant Thai" {
  let input = "สวัสดี"
  let g = graphemes(input)
  let buf = StringBuilder::new()
  for cluster in g {
    buf.write_string(cluster.to_owned())
  }
  inspect(buf.to_string() == input, content="true")
}

///|
// Concatenation invariant for multi-script text (Arabic)
test "graphemes: concatenation invariant Arabic" {
  let input = "\u{0628}\u{0650}\u{0633}\u{0652}\u{0645}\u{0650}"
  let g = graphemes(input)
  let buf = StringBuilder::new()
  for cluster in g {
    buf.write_string(cluster.to_owned())
  }
  inspect(buf.to_string() == input, content="true")
}

///|
test "grapheme_iter: basic iteration" {
  let result : Array[String] = []
  for cluster in grapheme_iter("A\u{1F600}B") {
    result.push(cluster.to_owned())
  }
  inspect(result.length(), content="3")
  inspect(result[0], content="A")
  inspect(result[1], content="\u{1F600}")
  inspect(result[2], content="B")
}

///|
test "grapheme_iter: early break (first 2 only)" {
  let result : Array[String] = []
  for cluster in grapheme_iter("ABCDEFGHIJ") {
    result.push(cluster.to_owned())
    if result.length() >= 2 {
      break
    }
  }
  inspect(result.length(), content="2")
  inspect(result[0], content="A")
  inspect(result[1], content="B")
}

///|
test "grapheme_iter: empty string" {
  let mut count = 0
  for _cluster in grapheme_iter("") {
    count += 1
  }
  inspect(count, content="0")
}

///|
test "grapheme_iter: family emoji is 1 cluster" {
  let mut count = 0
  for
    _cluster in grapheme_iter(
      "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}",
    ) {
    count += 1
  }
  inspect(count, content="1")
}

///|
test "grapheme_iter: matches graphemes() count and content" {
  // grapheme_iter と graphemes() の結果が要素数・内容ともに一致することを確認
  let inputs = [
    "", "Hello", "A\u{1F600}B", "\r\n", "\u{1F1EF}\u{1F1F5}\u{1F1FA}",
    // Devanagari conjunct (InCB)
     "\u{0915}\u{094D}\u{0915}",
    // Hangul syllable sequence (L+V+T)
     "\u{1100}\u{1161}\u{11A8}",
    // Thai with combining marks
     "\u{0E2A}\u{0E27}\u{0E31}\u{0E2A}\u{0E14}\u{0E35}",
    // Family emoji ZWJ
     "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}",
    // Long combining mark sequence
     "A\u{0300}\u{0301}\u{0302}\u{0303}\u{0304}",
    // Mixed: ASCII + emoji + flag + Devanagari
     "Hi\u{1F600}\u{1F1EF}\u{1F1F5}\u{0915}\u{094D}\u{0915}",
  ]
  for input in inputs {
    let g = graphemes(input)
    let iter_result : Array[String] = []
    for cluster in grapheme_iter(input) {
      iter_result.push(cluster.to_owned())
    }
    assert_eq(g.length(), iter_result.length())
    for i in 0..<g.length() {
      assert_eq(g[i].to_owned(), iter_result[i])
    }
  }
}

// --- QA edge case tests ---

// AO. Regional Indicator (RI) extended parity tests (GB12/13)

///|
// 6 RI code points: 🇯🇵🇺🇸🇫🇷 → 3 clusters
test "graphemes: 6 RI code points (3 flags)" {
  let g = graphemes("\u{1F1EF}\u{1F1F5}\u{1F1FA}\u{1F1F8}\u{1F1EB}\u{1F1F7}")
  inspect(g.length(), content="3")
}

///|
// 7 RI code points: 3 pairs + 1 lone → 4 clusters
test "graphemes: 7 RI code points (3 pairs + lone)" {
  let g = graphemes(
    "\u{1F1EF}\u{1F1F5}\u{1F1FA}\u{1F1F8}\u{1F1EB}\u{1F1F7}\u{1F1E6}",
  )
  inspect(g.length(), content="4")
}

///|
// 8 RI code points: 4 pairs → 4 clusters
test "graphemes: 8 RI code points (4 flags)" {
  let g = graphemes(
    "\u{1F1EF}\u{1F1F5}\u{1F1FA}\u{1F1F8}\u{1F1EB}\u{1F1F7}\u{1F1E9}\u{1F1EA}",
  )
  inspect(g.length(), content="4")
}

// AP. Skin tone modifier tests (Extend after Extended_Pictographic)

///|
// Two emoji with different skin tones → 2 clusters
test "graphemes: two emoji with different skin tones" {
  // Waving hand + light + thumbs up + dark
  let g = graphemes("\u{1F44B}\u{1F3FB}\u{1F44D}\u{1F3FF}")
  inspect(g.length(), content="2")
}

///|
// EP + multiple Extend (skin tone + combining) → 1 cluster
test "graphemes: emoji with skin tone and combining mark" {
  // Person U+1F9D1 + skin tone U+1F3FD + combining enclosing keycap U+20E3 (Extend)
  let g = graphemes("\u{1F9D1}\u{1F3FD}\u{20E3}")
  inspect(g.length(), content="1")
}

// AQ. InCB state deep nesting tests (GB9c)

///|
// Consonant + Extend + Linker + Extend + Consonant → 1 cluster
test "graphemes: InCB with interleaved Extend (C+E+L+E+C)" {
  // ka + nukta(Extend) + virama(Linker) + nukta(Extend) + ka
  let g = graphemes("\u{0915}\u{093C}\u{094D}\u{093C}\u{0915}")
  inspect(g.length(), content="1")
}

///|
// Consonant + Linker + Consonant + Linker + Consonant + Linker + Consonant → 1 cluster
test "graphemes: InCB quadruple consonant chain" {
  // ka + virama + ka + virama + ka + virama + ka
  let g = graphemes("\u{0915}\u{094D}\u{0915}\u{094D}\u{0915}\u{094D}\u{0915}")
  inspect(g.length(), content="1")
}

// AR. InCB + emoji state simultaneous activation

///|
// Devanagari conjunct followed by emoji ZWJ sequence
test "graphemes: InCB then emoji ZWJ" {
  // ka+virama+ka (1 cluster) + family emoji (1 cluster)
  let g = graphemes(
    "\u{0915}\u{094D}\u{0915}\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}",
  )
  inspect(g.length(), content="2")
}

///|
// Emoji ZWJ sequence followed by Devanagari conjunct
test "graphemes: emoji ZWJ then InCB" {
  // thumbs up (1 cluster) + ka+virama+ka (1 cluster)
  let g = graphemes("\u{1F44D}\u{0915}\u{094D}\u{0915}")
  inspect(g.length(), content="2")
}

///|
// Mixed: RI pair + InCB conjunct + emoji ZWJ
test "graphemes: RI + InCB + emoji ZWJ mixed" {
  // JP flag (1) + ka+virama+ka (1) + person+ZWJ+person (1)
  let g = graphemes(
    "\u{1F1EF}\u{1F1F5}\u{0915}\u{094D}\u{0915}\u{1F468}\u{200D}\u{1F469}",
  )
  inspect(g.length(), content="3")
}

// AS. Long ZWJ emoji chain

///|
// Very long ZWJ sequence: EP ZWJ EP ZWJ EP ZWJ EP ZWJ EP (5 EP) → 1 cluster
test "graphemes: long ZWJ chain (5 emoji)" {
  // person + ZWJ + person + ZWJ + person + ZWJ + person + ZWJ + person
  let g = graphemes(
    "\u{1F9D1}\u{200D}\u{1F9D1}\u{200D}\u{1F9D1}\u{200D}\u{1F9D1}\u{200D}\u{1F9D1}",
  )
  inspect(g.length(), content="1")
}

///|
// ZWJ between non-EP characters → ZWJ joins to preceding (GB9), B breaks (GB999)
test "graphemes: ZWJ between non-EP is not GB11" {
  // A + ZWJ → 1 cluster (GB9: × ZWJ), then B → separate cluster (GB999)
  let g = graphemes("A\u{200D}B")
  inspect(g.length(), content="2")
  inspect(g[0].to_owned(), content="A\u{200D}")
  inspect(g[1].to_owned(), content="B")
}

// AT. Sliced view grapheme_indices offset precision

///|
test "grapheme_indices: sliced view offsets refer to original source" {
  // "ABCDE" → slice [2:4] → "CD"
  let g = graphemes("ABCDE")
  let sliced = g[2:4]
  let offsets : Array[(Int, Int)] = []
  for entry in sliced.grapheme_indices() {
    offsets.push((entry.0, entry.1))
  }
  // C starts at offset 2, D starts at offset 3 in original string
  @debug.debug_inspect(offsets, content="[(2, 3), (3, 4)]")
}

///|
test "grapheme_indices: double-sliced view offsets" {
  // "ABCDEFGH" → slice [1:7] → "BCDEFG" → slice [2:5] → "DEF"
  let g = graphemes("ABCDEFGH")
  let s1 = g[1:7]
  let s2 = s1[2:5]
  let offsets : Array[(Int, Int)] = []
  for entry in s2.grapheme_indices() {
    offsets.push((entry.0, entry.1))
  }
  // D=3, E=4, F=5 in original string
  @debug.debug_inspect(offsets, content="[(3, 4), (4, 5), (5, 6)]")
}

///|
test "grapheme_indices: sliced emoji view offsets" {
  // "A🇯🇵B" → graphemes: A(0-1), 🇯🇵(1-5), B(5-6)
  let g = graphemes("A\u{1F1EF}\u{1F1F5}B")
  let sliced = g[1:2] // just the flag
  let offsets : Array[(Int, Int)] = []
  for entry in sliced.grapheme_indices() {
    offsets.push((entry.0, entry.1))
  }
  // Flag occupies UTF-16 offsets 1..5 (2 surrogate pairs)
  @debug.debug_inspect(offsets, content="[(1, 5)]")
}

// AU. RI parity reset after non-RI character

///|
test "graphemes: RI parity resets after non-RI" {
  // RI+RI (1 flag) + A (1) + RI+RI (1 flag) → 3 clusters
  let g = graphemes("\u{1F1EF}\u{1F1F5}A\u{1F1FA}\u{1F1F8}")
  inspect(g.length(), content="3")
}

///|
test "graphemes: lone RI between flags" {
  // RI+RI (flag) + RI (lone) + RI+RI (flag) → 3 clusters
  let g = graphemes("\u{1F1EF}\u{1F1F5}\u{1F1E6}\u{1F1FA}\u{1F1F8}")
  inspect(g.length(), content="3")
}

// Malformed UTF-16 tests.
// 0xD800-0xDBFF are high surrogates; 0xDC00-0xDFFF are low surrogates.
// A well-formed surrogate pair is "high followed by low". These tests
// exercise isolated (lone) surrogates, which the decoder must treat as
// single-unit code points rather than pairing them with unrelated neighbors.
// Each test verifies both cluster count AND the code-unit value of the
// lone surrogate cluster, so bugs that silently replace or drop the
// surrogate (e.g. U+FFFD substitution) would still be detected.

///|
// Run the same malformed input through both graphemes() and grapheme_iter()
// to confirm they agree; other malformed tests below use graphemes() only.
test "grapheme_iter: lone high surrogate followed by ASCII" {
  let s = String::from_array([(0xD800).unsafe_to_char(), 'A'])
  let clusters : Array[StringView] = []
  for cluster in grapheme_iter(s) {
    clusters.push(cluster)
  }
  inspect(clusters.length(), content="2")
  inspect(clusters[0].length(), content="1")
  inspect(clusters[0].at(0).to_int(), content="55296") // 0xD800
  inspect(clusters[1].to_owned(), content="A")
}

///|
test "graphemes: lone high surrogate followed by ASCII" {
  let s = String::from_array([(0xD800).unsafe_to_char(), 'A'])
  let g = graphemes(s)
  inspect(g.length(), content="2")
  inspect(g[0].length(), content="1")
  inspect(g[0].at(0).to_int(), content="55296") // 0xD800
  inspect(g[1].to_owned(), content="A")
}

///|
// High surrogate at end of string (no next code unit): the decoder must not
// read past the end and must yield the lone surrogate as its own cluster.
test "graphemes: lone high surrogate at end of string" {
  let s = String::from_array([(0xD800).unsafe_to_char()])
  let g = graphemes(s)
  inspect(g.length(), content="1")
  inspect(g[0].length(), content="1")
  inspect(g[0].at(0).to_int(), content="55296") // 0xD800
}

///|
// Lone low surrogate (not preceded by a high surrogate): must be treated as
// a single-unit code point and form its own cluster.
test "graphemes: lone low surrogate followed by ASCII" {
  let s = String::from_array([(0xDC00).unsafe_to_char(), 'A'])
  let g = graphemes(s)
  inspect(g.length(), content="2")
  inspect(g[0].length(), content="1")
  inspect(g[0].at(0).to_int(), content="56320") // 0xDC00
  inspect(g[1].to_owned(), content="A")
}

///|
// Two consecutive high surrogates: neither forms a valid pair (the second is
// not followed by a low surrogate), so both must be treated as lone surrogates
// and yield two separate clusters preserving each code-unit value.
test "graphemes: two consecutive high surrogates" {
  let s = String::from_array([
    (0xD800).unsafe_to_char(),
    (0xD801).unsafe_to_char(),
  ])
  let g = graphemes(s)
  inspect(g.length(), content="2")
  inspect(g[0].at(0).to_int(), content="55296") // 0xD800
  inspect(g[1].at(0).to_int(), content="55297") // 0xD801
}

// ============================================================
// Z. Invariants from DR-0003 / DR-0004 / DR-0006
// ============================================================

///|
test "GB2 sentinel: boundaries[last] == source.length() for ASCII" {
  // ASCII string "abc" must produce 3 single-codepoint clusters and a
  // terminating end-sentinel at offset 3 (= source.length()). This pins
  // UAX #29 GB2 (Any ÷ eot) plus the +1 offset advancement for BMP-only
  // input — a regression here corrupts every multi-cluster boundary
  // because every downstream offset (op_get range, grapheme_indices end,
  // to_string slice) is computed from the same boundaries array.
  // (DR-0003 — UAX #29 corpus coverage strategy)
  let g = graphemes("abc")
  let pairs : Array[(Int, Int)] = []
  for entry in g.grapheme_indices() {
    pairs.push((entry.0, entry.1))
  }
  // Last pair's end offset is the GB2 end-sentinel.
  assert_eq(pairs[pairs.length() - 1].1, 3)
  assert_eq(pairs[pairs.length() - 1].1, "abc".length())
}

///|
test "GB2 sentinel: surrogate pair advances +2" {
  // U+1F600 GRINNING FACE lives on the Supplementary Multilingual Plane,
  // so in MoonBit's UTF-16 String it occupies 2 code units. The end
  // sentinel — and therefore the per-cluster end offset for this single
  // cluster — must be 2, not 1. If the offset advancement code path
  // mistakenly increments by 1 for non-BMP code points, every offset for
  // any non-BMP content (emoji, CJK Extension B+, math symbols, ...)
  // collapses, breaking slice indexing and to_string roundtripping.
  // (DR-0003 — UAX #29 corpus coverage strategy)
  let g = graphemes("\u{1F600}")
  let pairs : Array[(Int, Int)] = []
  for entry in g.grapheme_indices() {
    pairs.push((entry.0, entry.1))
  }
  assert_eq(pairs.length(), 1)
  assert_eq(pairs[0].0, 0)
  assert_eq(pairs[0].1, 2)
}

///|
test "op_as_view zero-copy: sliced view grapheme_indices refer to original source" {
  // op_as_view (g[i:j]) shares the underlying boundaries array with the
  // parent view rather than recomputing offsets from 0. Consumers rely on
  // this contract to compute substring positions in the original source
  // from a sliced view (e.g. "find the byte range of the 6th cluster in
  // the original string"). If a future change re-bases the offsets to 0
  // for the sliced view, this contract silently breaks and downstream
  // string slicing produces wrong substrings.
  // (DR-0003 — UAX #29 corpus coverage strategy)
  let g = graphemes("Hello\u{1F1EF}\u{1F1F5}World")
  let sliced = g[5:7] // 🇯🇵 and W (or 🇯🇵 and "W"? cluster 5=flag, cluster 6=W)
  let pairs : Array[(Int, Int)] = []
  for entry in sliced.grapheme_indices() {
    pairs.push((entry.0, entry.1))
  }
  // Every offset in the sliced view must still refer to the ORIGINAL
  // source position. Cluster 5 (the flag) starts at code-unit offset 5
  // in "Hello🇯🇵World"; offsets here MUST NOT be re-based to 0.
  for entry in pairs {
    assert_eq(entry.0 >= 5, true)
    assert_eq(entry.1 >= 5, true)
  }
}

///|
test "grapheme_iter exhaustion is stable: None then None" {
  // Iterator contract: once an iterator yields None, every subsequent
  // .next() call must keep yielding None. A buggy state machine that
  // re-emits the last cluster — or wraps around — would surprise callers
  // who use the standard "while it.next() is Some(x) { ... }" loop and
  // could produce infinite loops in downstream code. This test pins the
  // `done` flag latching in grapheme_iter().
  // (DR-0004 — segmenter state parity)
  let it = grapheme_iter("ab")
  // Consume the two clusters.
  let _ = it.next()
  let _ = it.next()
  // Now the iterator must be permanently exhausted.
  @debug.debug_inspect(it.next(), content="None")
  @debug.debug_inspect(it.next(), content="None")
}

///|
test "grapheme_iter parity with graphemes() on a SMP input" {
  // DR-0004 contract: the lazy iterator path (grapheme_iter) and the
  // eager view path (graphemes().iter()) must yield identical cluster
  // sequences for every input. This is a sample spot-check on an input
  // mixing ASCII with a supplementary-plane emoji (which exercises the
  // surrogate-pair advancement on both paths). Full UAX #29 corpus
  // parity is asserted elsewhere by the generated uax29_iter_test.mbt;
  // this case acts as a hand-written regression anchor that fails fast
  // if the two paths diverge.
  // (DR-0004 — segmenter state parity)
  let input = "A\u{1F600}B"
  let view_collected : Array[String] = []
  for cluster in graphemes(input).iter() {
    view_collected.push(cluster.to_owned())
  }
  let iter_collected : Array[String] = []
  for cluster in grapheme_iter(input) {
    iter_collected.push(cluster.to_owned())
  }
  assert_eq(view_collected.length(), iter_collected.length())
  for i in 0..<view_collected.length() {
    assert_eq(view_collected[i], iter_collected[i])
  }
}

///|
test "lone high surrogate at end of string: one extra cluster" {
  // Lenient lone-surrogate policy: an unpaired high surrogate at the end
  // of the string (no following low surrogate) must be passed through as
  // its own cluster — never panic, never replaced silently with U+FFFD.
  // Also the +1 offset advancement applies (a lone surrogate occupies 1
  // UTF-16 code unit), so the GB2 end-sentinel for "A" + lone-high must
  // land at offset 2. A regression here would either crash on malformed
  // UTF-16 or merge the lone surrogate into the preceding cluster.
  // (DR-0006 — lone surrogate policy)
  let s = String::from_array(['A', (0xD800).unsafe_to_char()])
  let g = graphemes(s)
  assert_eq(g.length(), 2)
  // The final cluster is exactly the lone high surrogate (1 code unit,
  // value 0xD800 = 55296).
  let last = g[1]
  assert_eq(last.length(), 1)
  assert_eq(last.at(0).to_int(), 55296)
  // The GB2 end-sentinel is the source length (= 2).
  let pairs : Array[(Int, Int)] = []
  for entry in g.grapheme_indices() {
    pairs.push((entry.0, entry.1))
  }
  assert_eq(pairs[pairs.length() - 1].1, 2)
}

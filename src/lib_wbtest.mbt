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
  inspect(g[1].to_string(), content="\u{1F600}")
}

///|
test "graphemes: iter" {
  let result : Array[String] = []
  for cluster in graphemes("A\u{1F600}B").iter() {
    result.push(cluster.to_string())
  }
  inspect(
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
  inspect(g[0].to_string(), content="\u{304B}\u{3099}")
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
// Flag: JP flag (RI+RI) -> 1 cluster
test "graphemes: flag JP" {
  let g = graphemes("\u{1F1EF}\u{1F1F5}")
  inspect(g.length(), content="1")
}

///|
// Two flags: JP+US (RI RI RI RI) -> 2 clusters
test "graphemes: two flags JP+US" {
  let g = graphemes("\u{1F1EF}\u{1F1F5}\u{1F1FA}\u{1F1F8}")
  inspect(g.length(), content="2")
}

///|
// Emoji ZWJ sequence: family emoji -> 1 cluster
test "graphemes: family emoji ZWJ" {
  // Man U+1F468, ZWJ U+200D, Woman U+1F469, ZWJ, Girl U+1F467, ZWJ, Boy U+1F466
  let g = graphemes(
    "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}",
  )
  inspect(g.length(), content="1")
}

///|
// InCB Conjunct: Devanagari ka + virama + ka (Consonant + Virama + Consonant) -> 1 cluster
test "graphemes: InCB Conjunct" {
  // ka U+0915 (InCB_Consonant), virama U+094D (Virama = InCB Linker + Extend), ka U+0915
  let g = graphemes("\u{0915}\u{094D}\u{0915}")
  inspect(g.length(), content="1")
}

///|
// RI x3: JP flag + isolated RI -> 2 clusters ([RI RI] [RI])
test "graphemes: RI x3" {
  let g = graphemes("\u{1F1EF}\u{1F1F5}\u{1F1FA}")
  inspect(g.length(), content="2")
}

///|
// RI x5: JP+US flags + isolated RI -> 3 clusters ([RI RI] [RI RI] [RI])
test "graphemes: RI x5" {
  let g = graphemes("\u{1F1EF}\u{1F1F5}\u{1F1FA}\u{1F1F8}\u{1F1E6}")
  inspect(g.length(), content="3")
}

// ============================================================
// A. op_get boundary value tests
// ============================================================

///|
test "graphemes: op_get first index" {
  let g = graphemes("ABC")
  inspect(g[0].to_string(), content="A")
}

///|
test "graphemes: op_get last index" {
  let g = graphemes("ABC")
  inspect(g[g.length() - 1].to_string(), content="C")
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
test "graphemes: iter empty produces no elements" {
  let g = graphemes("")
  let mut count = 0
  for _cluster in g.iter() {
    count += 1
  }
  inspect(count, content="0")
}

///|
test "graphemes: iter collects all clusters" {
  let g = graphemes("A\u{1F600}B")
  let collected : Array[String] = []
  for cluster in g.iter() {
    collected.push(cluster.to_string())
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
    buf.write_string(cluster.to_string())
  }
  inspect(buf.to_string(), content="Hello World")
}

///|
test "graphemes: concatenation invariant mixed" {
  let input = "Hello\u{1F1EF}\u{1F1F5}World\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}!"
  let g = graphemes(input)
  let buf = StringBuilder::new()
  for cluster in g.iter() {
    buf.write_string(cluster.to_string())
  }
  inspect(buf.to_string() == input, content="true")
}

///|
test "graphemes: concatenation invariant empty" {
  let input = ""
  let g = graphemes(input)
  let buf = StringBuilder::new()
  for cluster in g.iter() {
    buf.write_string(cluster.to_string())
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
    buf.write_string(cluster.to_string())
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
  inspect(not(v is None), content="true")
}

///|
test "GraphemeView: get out of range returns None" {
  let g = graphemes("ABC")
  inspect(g.get(3), content="None")
}

///|
test "GraphemeView: get negative returns None" {
  let g = graphemes("ABC")
  inspect(g.get(-1), content="None")
}

///|
test "GraphemeView: get on empty returns None" {
  let g = graphemes("")
  inspect(g.get(0), content="None")
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
  inspect(sliced[0].to_string(), content="B")
  inspect(sliced[1].to_string(), content="C")
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
  inspect(s2[0].to_string(), content="C")
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
    values.push(cluster.to_string())
  }
  inspect(indices, content="[0, 1, 2]")
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
    result.push(cluster.to_string())
  }
  let expected =
    #|["C", "B", "A"]
  inspect(result, content=expected)
}

// ============================================================
// O. Eq trait tests
// ============================================================

///|
test "GraphemeView: Eq same string" {
  let a = graphemes("Hello")
  let b = graphemes("Hello")
  inspect(a == b, content="true")
}

///|
test "GraphemeView: Eq different string" {
  let a = graphemes("Hello")
  let b = graphemes("World")
  inspect(a == b, content="false")
}

///|
test "GraphemeView: Eq different length" {
  let a = graphemes("AB")
  let b = graphemes("ABC")
  inspect(a == b, content="false")
}

///|
test "GraphemeView: Eq empty" {
  let a = graphemes("")
  let b = graphemes("")
  inspect(a == b, content="true")
}

///|
test "GraphemeView: Eq sliced" {
  let a = graphemes("ABCDE")[1:3] // B, C
  let b = graphemes("BC")
  inspect(a == b, content="true")
}

// ============================================================
// P. Hash trait tests
// ============================================================

///|
test "GraphemeView: Hash consistency with Eq" {
  let a = graphemes("Hello")
  let b = graphemes("Hello")
  // Equal objects must have equal hashes
  assert_eq(a.hash(), b.hash())
}

///|
test "GraphemeView: Hash in HashMap" {
  let map : Map[String, Int] = {}
  // GraphemeView を文字列キーとして使う例（直接キーにはしないが、hash は使える）
  let g = graphemes("Hello🌍")
  map[g.to_string()] = g.length()
  inspect(map["Hello🌍"], content="6")
}

// ============================================================
// Q. Slice edge case tests
// ============================================================

///|
test "GraphemeView: slice emoji preservation" {
  // 絵文字がスライスで壊れないことを確認
  let g = graphemes("A🇯🇵B")
  let sliced = g[1:2]
  inspect(sliced[0].to_string(), content="🇯🇵")
}

///|
test "GraphemeView: slice then iter" {
  let g = graphemes("ABCDE")
  let sliced = g[1:4]
  let result : Array[String] = []
  for cluster in sliced {
    result.push(cluster.to_string())
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
  inspect(indices, content="[0, 1, 2]")
}

///|
test "GraphemeView: slice then rev_iter" {
  let g = graphemes("ABCDE")
  let sliced = g[1:4]
  let result : Array[String] = []
  for cluster in sliced.rev_iter() {
    result.push(cluster.to_string())
  }
  let expected =
    #|["D", "C", "B"]
  inspect(result, content=expected)
}

// ============================================================
// R. op_as_view() open-ended slice tests (coverage for None branches)
// ============================================================

///|
test "GraphemeView: slice open end (g[1:])" {
  let g = graphemes("ABCDE")
  let sliced = g[1:]
  inspect(sliced.length(), content="4")
  inspect(sliced[0].to_string(), content="B")
}

///|
test "GraphemeView: slice open start (g[:3])" {
  let g = graphemes("ABCDE")
  let sliced = g[:3]
  inspect(sliced.length(), content="3")
  inspect(sliced[0].to_string(), content="A")
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
  inspect(sliced[0].to_string(), content="A")
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
  inspect(sliced[0].to_string(), content="C")
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
  inspect(offsets, content="[(0, 1), (1, 2), (2, 3)]")
}

///|
test "GraphemeView: grapheme_indices emoji" {
  let g = graphemes("A\u{1F600}B")
  let offsets : Array[(Int, Int)] = []
  for entry in g.grapheme_indices() {
    offsets.push((entry.0, entry.1))
  }
  // 😀 はサロゲートペアで2コードユニット
  inspect(offsets, content="[(0, 1), (1, 3), (3, 4)]")
}

///|
test "GraphemeView: grapheme_indices empty" {
  let g = graphemes("")
  let offsets : Array[(Int, Int)] = []
  for entry in g.grapheme_indices() {
    offsets.push((entry.0, entry.1))
  }
  inspect(offsets, content="[]")
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
  inspect(offsets, content="[(1, 2), (2, 3)]")
}

///|
test "GraphemeView: grapheme_indices cluster content" {
  let g = graphemes("A\u{1F600}B")
  let clusters : Array[String] = []
  for entry in g.grapheme_indices() {
    clusters.push(entry.2.to_string())
  }
  inspect(
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
  inspect(g[0].to_string(), content="\u{FFFD}")
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
  inspect(g[0].to_string(), content="\u{FEFF}")
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
  inspect(offsets, content="[(0, 1)]")
}

///|
test "grapheme_indices: combining character cluster" {
  // 'a' + combining acute = 1 cluster spanning 2 code units
  let g = graphemes("a\u{0301}")
  let offsets : Array[(Int, Int)] = []
  for entry in g.grapheme_indices() {
    offsets.push((entry.0, entry.1))
  }
  inspect(offsets, content="[(0, 2)]")
}

///|
test "grapheme_indices: CRLF cluster" {
  let g = graphemes("\r\n")
  let offsets : Array[(Int, Int)] = []
  for entry in g.grapheme_indices() {
    offsets.push((entry.0, entry.1))
  }
  inspect(offsets, content="[(0, 2)]")
}

///|
test "grapheme_indices: sliced single element" {
  let g = graphemes("ABCDE")[2:3]
  let offsets : Array[(Int, Int)] = []
  for entry in g.grapheme_indices() {
    offsets.push((entry.0, entry.1))
  }
  // Offset refers to position in original string
  inspect(offsets, content="[(2, 3)]")
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
  inspect(indices, content="[]")
}

///|
test "iter2: single element" {
  let g = graphemes("Z")
  let indices : Array[Int] = []
  let values : Array[String] = []
  for i, cluster in g.iter2() {
    indices.push(i)
    values.push(cluster.to_string())
  }
  inspect(indices, content="[0]")
  inspect(values, content="[\"Z\"]")
}

///|
test "iter2: on sliced view indices are 0-based" {
  let g = graphemes("ABCDE")[2:5]
  let indices : Array[Int] = []
  let values : Array[String] = []
  for i, cluster in g.iter2() {
    indices.push(i)
    values.push(cluster.to_string())
  }
  inspect(indices, content="[0, 1, 2]")
  inspect(values, content="[\"C\", \"D\", \"E\"]")
}

// ============================================================
// W. rev_iter() boundary tests
// ============================================================

///|
test "rev_iter: empty" {
  let g = graphemes("")
  let result : Array[String] = []
  for cluster in g.rev_iter() {
    result.push(cluster.to_string())
  }
  inspect(result, content="[]")
}

///|
test "rev_iter: single element" {
  let g = graphemes("Q")
  let result : Array[String] = []
  for cluster in g.rev_iter() {
    result.push(cluster.to_string())
  }
  inspect(result, content="[\"Q\"]")
}

///|
test "rev_iter: on sliced view" {
  let g = graphemes("ABCDE")[1:4]
  let result : Array[String] = []
  for cluster in g.rev_iter() {
    result.push(cluster.to_string())
  }
  let expected =
    #|["D", "C", "B"]
  inspect(result, content=expected)
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

///|
test "Hash: different content likely different hash" {
  let a = graphemes("Hello")
  let b = graphemes("World")
  // Not strictly guaranteed, but highly likely for different strings
  inspect(a.hash() != b.hash(), content="true")
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
test "graphemes: very long combining mark sequence (100 marks)" {
  // 1 base character + 100 combining marks = 1 cluster
  let buf = StringBuilder::new()
  buf.write_char('a')
  for i = 0; i < 100; i = i + 1 {
    buf.write_char('\u{0301}')
  }
  let s = buf.to_string()
  let g = graphemes(s)
  inspect(g.length(), content="1")
  // Concatenation invariant
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
test "graphemes: Hangul L V T sequence" {
  // L (U+1100) + V (U+1161) + T (U+11A8) = 1 cluster (GB6 + GB7/GB8)
  let g = graphemes("\u{1100}\u{1161}\u{11A8}")
  inspect(g.length(), content="1")
}

///|
test "graphemes: Hangul LV + T" {
  // LV syllable (U+AC00) + T (U+11A8) = 1 cluster (GB8)
  let g = graphemes("\u{AC00}\u{11A8}")
  inspect(g.length(), content="1")
}

///|
test "graphemes: Hangul LVT alone" {
  // LVT syllable (U+AC01) = 1 cluster
  let g = graphemes("\u{AC01}")
  inspect(g.length(), content="1")
}

///|
test "graphemes: Hangul L + LV + T" {
  // L + LV + T: GB6 (L × LV), then (LV+T merged as LVT×T) via GB7/GB8 = 1 cluster
  let g = graphemes("\u{1100}\u{AC00}\u{11A8}")
  inspect(g.length(), content="1")
}

///|
test "graphemes: Hangul two syllables" {
  // LV (U+AC00) + LVT (U+AC01) = 2 clusters (no rule joins LV+LVT without L/V/T)
  let g = graphemes("\u{AC00}\u{AC01}")
  inspect(g.length(), content="2")
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
test "graphemes: InCB triple conjunct" {
  // ka + virama + ka + virama + ka = 1 cluster (GB9c chains)
  let g = graphemes("\u{0915}\u{094D}\u{0915}\u{094D}\u{0915}")
  inspect(g.length(), content="1")
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
  inspect(s2[0].to_string(), content="D")
  inspect(s2[1].to_string(), content="E")
}

///|
test "op_as_view: triple nested slice" {
  let g = graphemes("ABCDEFGHIJ")
  let s1 = g[1:9] // B C D E F G H I
  let s2 = s1[2:6] // D E F G
  let s3 = s2[1:3] // E F
  inspect(s3.length(), content="2")
  inspect(s3[0].to_string(), content="E")
  inspect(s3[1].to_string(), content="F")
}

// ============================================================
// AD. get() additional edge cases
// ============================================================

///|
test "get: first element of sliced view" {
  let g = graphemes("ABCDE")[2:4]
  inspect(g.get(0).map(fn(v) { v.to_string() }), content="Some(\"C\")")
}

///|
test "get: last element of sliced view" {
  let g = graphemes("ABCDE")[2:4]
  inspect(g.get(1).map(fn(v) { v.to_string() }), content="Some(\"D\")")
}

///|
test "get: out of range on sliced view" {
  let g = graphemes("ABCDE")[2:4]
  inspect(g.get(2), content="None")
}

///|
test "get: negative on sliced view" {
  let g = graphemes("ABCDE")[2:4]
  inspect(g.get(-1), content="None")
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
    buf.write_string(cluster.to_string())
  }
  inspect(buf.to_string() == input, content="true")
}

///|
test "graphemes: concatenation invariant for control characters" {
  let input = "\u{0000}\u{0001}\u{001F}A"
  let g = graphemes(input)
  let buf = StringBuilder::new()
  for cluster in g.iter() {
    buf.write_string(cluster.to_string())
  }
  inspect(buf.to_string() == input, content="true")
}

///|
test "graphemes: concatenation invariant for BOM" {
  let input = "\u{FEFF}Hello"
  let g = graphemes(input)
  let buf = StringBuilder::new()
  for cluster in g.iter() {
    buf.write_string(cluster.to_string())
  }
  inspect(buf.to_string() == input, content="true")
}

///|
test "graphemes: concatenation invariant for special codepoints" {
  let input = "\u{FFFD}\u{E000}\u{FFFF}\u{FDD0}"
  let g = graphemes(input)
  let buf = StringBuilder::new()
  for cluster in g.iter() {
    buf.write_string(cluster.to_string())
  }
  inspect(buf.to_string() == input, content="true")
}

///|
test "graphemes: concatenation invariant for long combining marks" {
  let buf = StringBuilder::new()
  buf.write_char('a')
  for i = 0; i < 50; i = i + 1 {
    buf.write_char('\u{0301}')
  }
  let input = buf.to_string()
  let g = graphemes(input)
  let buf2 = StringBuilder::new()
  for cluster in g.iter() {
    buf2.write_string(cluster.to_string())
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
  inspect(offsets, content="[]")
}

///|
test "grapheme_indices: on full emoji string" {
  let g = graphemes("\u{1F1EF}\u{1F1F5}A")
  let offsets : Array[(Int, Int)] = []
  for entry in g.grapheme_indices() {
    offsets.push((entry.0, entry.1))
  }
  // Flag: 2+2=4 code units, A: 1 code unit
  inspect(offsets, content="[(0, 4), (4, 5)]")
}

// ============================================================
// AH. rev_iter on sliced view with emoji
// ============================================================

///|
test "rev_iter: sliced view with emoji" {
  let g = graphemes("A\u{1F600}BC")[1:3]
  let result : Array[String] = []
  for cluster in g.rev_iter() {
    result.push(cluster.to_string())
  }
  inspect(
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
    result.push(cluster.to_string())
  }
  inspect(result, content="[\"A\", \"B\"]")
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
    buf.write_string(cluster.to_string())
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
    buf.write_string(cluster.to_string())
  }
  inspect(buf.to_string() == input, content="true")
}

///|
test "grapheme_iter: basic iteration" {
  let result : Array[String] = []
  for cluster in grapheme_iter("A\u{1F600}B") {
    result.push(cluster.to_string())
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
    result.push(cluster.to_string())
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
test "grapheme_iter: matches graphemes()" {
  // grapheme_iter と graphemes() の結果が一致することを確認
  let inputs = [
    "Hello", "A\u{1F600}B", "\r\n", "\u{1F1EF}\u{1F1F5}\u{1F1FA}", "",
  ]
  for input in inputs {
    let g = graphemes(input)
    let iter_result : Array[String] = []
    for cluster in grapheme_iter(input) {
      iter_result.push(cluster.to_string())
    }
    assert_eq(g.length(), iter_result.length())
  }
}

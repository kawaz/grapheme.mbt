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

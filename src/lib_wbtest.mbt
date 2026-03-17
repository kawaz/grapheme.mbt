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
  inspect(result, content=(
    #|["A", "😀", "B"]
  ))
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
    "", "A", "ABC", "\u{1F600}", "\r\n",
    "\u{1F1EF}\u{1F1F5}", "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}",
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

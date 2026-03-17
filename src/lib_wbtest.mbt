///|
test "graphemes: ASCII 文字列" {
  let g = graphemes("hello")
  inspect(g.length(), content="5")
}

///|
test "graphemes: BMP 文字" {
  let g = graphemes("あいう")
  inspect(g.length(), content="3")
}

///|
test "graphemes: サロゲートペア文字" {
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
test "graphemes: 空文字列" {
  let g = graphemes("")
  inspect(g.length(), content="0")
}

///|
// 結合文字: 「か」(U+304B) + 結合濁点(U+3099) → 1 cluster
test "graphemes: 結合文字 が" {
  let g = graphemes("\u{304B}\u{3099}")
  inspect(g.length(), content="1")
  inspect(g[0].to_string(), content="\u{304B}\u{3099}")
}

///|
// CRLF: \r\n → 1 cluster
test "graphemes: CRLF" {
  let g = graphemes("\r\n")
  inspect(g.length(), content="1")
}

///|
// Control 前後: NUL + A → 2 clusters
test "graphemes: Control 前後" {
  let g = graphemes("\u{0000}A")
  inspect(g.length(), content="2")
}

///|
// SpacingMark: デーヴァナーガリー "का" (U+0915 U+093E) → 1 cluster
test "graphemes: SpacingMark デーヴァナーガリー" {
  let g = graphemes("\u{0915}\u{093E}")
  inspect(g.length(), content="1")
}

///|
// 国旗: 🇯🇵 (RI+RI) → 1 cluster
test "graphemes: 国旗 🇯🇵" {
  let g = graphemes("\u{1F1EF}\u{1F1F5}")
  inspect(g.length(), content="1")
}

///|
// 国旗2つ: 🇯🇵🇺🇸 (RI RI RI RI) → 2 clusters
test "graphemes: 国旗2つ 🇯🇵🇺🇸" {
  let g = graphemes("\u{1F1EF}\u{1F1F5}\u{1F1FA}\u{1F1F8}")
  inspect(g.length(), content="2")
}

///|
// 絵文字 ZWJ シーケンス: 👨‍👩‍👧‍👦 → 1 cluster
test "graphemes: 家族絵文字 ZWJ" {
  // 👨 U+1F468, ZWJ U+200D, 👩 U+1F469, ZWJ, 👧 U+1F467, ZWJ, 👦 U+1F466
  let g = graphemes(
    "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}",
  )
  inspect(g.length(), content="1")
}

///|
// InCB Conjunct: デーヴァナーガリー क + ् + क (Consonant + Virama + Consonant) → 1 cluster
test "graphemes: InCB Conjunct" {
  // क U+0915 (InCB_Consonant), ् U+094D (Virama = InCB Linker + Extend), क U+0915
  let g = graphemes("\u{0915}\u{094D}\u{0915}")
  inspect(g.length(), content="1")
}

///|
// RI 3個: 🇯🇵 + 孤立 RI → 2 clusters ([RI RI] [RI])
test "graphemes: RI x3" {
  let g = graphemes("\u{1F1EF}\u{1F1F5}\u{1F1FA}")
  inspect(g.length(), content="2")
}

///|
// RI 5個: 🇯🇵🇺🇸 + 孤立 RI → 3 clusters ([RI RI] [RI RI] [RI])
test "graphemes: RI x5" {
  let g = graphemes("\u{1F1EF}\u{1F1F5}\u{1F1FA}\u{1F1F8}\u{1F1E6}")
  inspect(g.length(), content="3")
}

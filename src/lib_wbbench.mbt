///|
test "bench: graphemes ASCII short" (b : @bench.T) {
  let s = "Hello, World!"
  b.bench(fn() {
    let g = graphemes(s)
    b.keep(g)
  })
}

///|
test "bench: graphemes ASCII long" (b : @bench.T) {
  // 1000文字のASCII文字列を事前構築
  let buf = StringBuilder::new()
  for i = 0; i < 100; i = i + 1 {
    buf.write_string("0123456789")
  }
  let s = buf.to_string()
  b.bench(fn() {
    let g = graphemes(s)
    b.keep(g)
  })
}

///|
test "bench: graphemes emoji ZWJ" (b : @bench.T) {
  // 家族絵文字 x 10
  let buf = StringBuilder::new()
  for i = 0; i < 10; i = i + 1 {
    buf.write_string("\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}")
  }
  let s = buf.to_string()
  b.bench(fn() {
    let g = graphemes(s)
    b.keep(g)
  })
}

///|
test "bench: graphemes flags" (b : @bench.T) {
  // 国旗 x 10
  let buf = StringBuilder::new()
  for i = 0; i < 10; i = i + 1 {
    buf.write_string("\u{1F1EF}\u{1F1F5}")
  }
  let s = buf.to_string()
  b.bench(fn() {
    let g = graphemes(s)
    b.keep(g)
  })
}

///|
test "bench: graphemes hangul" (b : @bench.T) {
  // ハングル文字列
  let s = "안녕하세요 세계 여러분"
  b.bench(fn() {
    let g = graphemes(s)
    b.keep(g)
  })
}

///|
test "bench: graphemes devanagari" (b : @bench.T) {
  // デーヴァナーガリー（InCB状態が活性化する）
  let s = "\u{0915}\u{094D}\u{0915}\u{093E}\u{0915}\u{094D}\u{0915}\u{093E}\u{0915}\u{094D}\u{0915}\u{093E}"
  b.bench(fn() {
    let g = graphemes(s)
    b.keep(g)
  })
}

///|
test "bench: graphemes mixed real world" (b : @bench.T) {
  // 実世界テキスト混在
  let s = "Hello🌍, こんにちは世界! 🇯🇵🇺🇸 가나다라 👨\u{200D}👩\u{200D}👧\u{200D}👦"
  b.bench(fn() {
    let g = graphemes(s)
    b.keep(g)
  })
}

///|
test "bench: gcb_category ASCII" (b : @bench.T) {
  b.bench(fn() {
    let cat = gcb_category(0x41) // 'A'
    b.keep(cat)
  })
}

///|
test "bench: gcb_category emoji" (b : @bench.T) {
  b.bench(fn() {
    let cat = gcb_category(0x1F600) // grinning face
    b.keep(cat)
  })
}

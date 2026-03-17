# unicodegrapheme

Unicode grapheme cluster segmentation library for MoonBit.

## Overview

MoonBit の String は UTF-16 内部表現のため、`length()` や `str[i]` は UTF-16 コードユニット単位で動作する。
本ライブラリは UAX #29 (Unicode Text Segmentation) に基づき、文字列を grapheme cluster 単位で安全に操作する API を提供する。

## Status

**UAX #29 準拠の grapheme cluster 分割を実装済み**。Unicode 16.0.0 の全 GB ルール（GB3〜GB13, GB999）をステートマシンで実装し、公式テストデータ全 1,093 件をパスしている。

## Install

```
moon add kawaz/unicodegrapheme
```

## Usage

```moonbit
let view = @unicodegrapheme.graphemes("Hello🇯🇵World")
println(view.length())  // grapheme cluster 数
println(view[5].to_string())  // "🇯🇵"

for cluster in view.iter() {
  println(cluster)
}
```

## API

### `graphemes(s: String) -> GraphemeView`

文字列を grapheme cluster 単位で分割した `GraphemeView` を返す。

### `GraphemeView::length() -> Int`

grapheme cluster の数を返す。

### `GraphemeView::op_get(i: Int) -> StringView`

i 番目の grapheme cluster を `StringView` として返す。ゼロコピー。

### `GraphemeView::iter() -> Iter[StringView]`

grapheme cluster を順にイテレートする。

## Roadmap

- [x] UAX #29 Grapheme Cluster Break ステートマシン実装
- [x] `Extended_Pictographic` プロパティ対応
- [x] 合成絵文字（ZWJ シーケンス、国旗、肌色修飾子）対応
- [ ] スライス操作（`view[1:3]`）
- [ ] mooncakes.io 公開

## Unicode Version

Target: Unicode 16.0.0

## License

MIT License - Yoshiaki Kawazu (@kawaz)

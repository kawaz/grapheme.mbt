[English](README.md) | 日本語

# grapheme

[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Unicode 17.0.0](https://img.shields.io/badge/Unicode-17.0.0-blue.svg)](https://unicode.org/versions/Unicode17.0.0/)
[![UAX #29 compliant](https://img.shields.io/badge/UAX%20%2329-compliant-brightgreen.svg)](https://unicode.org/reports/tr29/)

MoonBit で `"👨‍👩‍👧‍👦".length()` は 11 を返す — 本ライブラリを使えば正しく 1 を返す。

## Overview

MoonBit の String は UTF-16 内部表現のため、`length()` や `str[i]` は UTF-16 コードユニット単位で動作する。
本ライブラリは [UAX #29](https://unicode.org/reports/tr29/) (Unicode Text Segmentation) の**デフォルト拡張書記素クラスタ**ルールに基づき、文字列を grapheme cluster（人間が「1文字」として認識する単位）ごとに安全に操作する API を提供する。ロケール固有の tailored ルールには非対応。

- 外部依存なし（Zero dependencies）
- 対応バックエンド: wasm-gc, js, native
- バンドルサイズ: wasm-gc ~25 KB / js ~59 KB / native ~56 KB

| レイヤー | 問題 | 解決 |
|----------|------|------|
| L1: UTF-16 encoding | `str[i]` がコードユニット単位 | MoonBit core の `iter()` |
| **L2: Grapheme cluster** | 合成絵文字が複数コードポイント | **本ライブラリ** |
| L3: Display width | 全角/半角の表示幅 | `rami3l/unicodewidth` |

Unicode 17.0.0 の全 GB ルール（GB3〜GB13, GB999）をステートマシンで実装し、公式テストデータ全 766 件をパス済み。

## Install

```
moon add kawaz/grapheme
```

使用するパッケージの `moon.pkg.json` に依存を追加:

```json
{
  "import": ["kawaz/grapheme"]
}
```

## Usage

```moonbit
// grapheme cluster 単位で正しくカウント
let family = @grapheme.graphemes("👨‍👩‍👧‍👦")
println(family.length())  // 1

// 分割・アクセス・スライス
let view = @grapheme.graphemes("Hello🇯🇵World")
println(view.length())  // 11 (H,e,l,l,o,🇯🇵,W,o,r,l,d)
println(view[5].to_string())  // "🇯🇵"
println(view[1:3].to_string())  // "el" (スライス)

// イテレーション
for cluster in view {
  println(cluster)
}

// 遅延評価: 先頭だけ必要な場合に高速
let first = @grapheme.grapheme_iter("very long text...").head()
```

`graphemes()` は全文を事前走査してランダムアクセス・スライスを提供する。O(n) full scan + O(k) memory（k = クラスタ数）。

`grapheme_iter()` は O(1) で開始し事前走査不要。先頭N件だけ必要な場合に高速。

## API

[API ドキュメント](https://mooncakes.io/docs/kawaz/grapheme)

> **Note:** `==` 比較はコードポイント列で行います。Unicode 正規化（NFC/NFD）は考慮しないため、`"が"` (U+304C) と `"か" + "゙"` (U+304B U+3099) は異なる GraphemeView として扱われます。

## Features

- UAX #29 Grapheme Cluster Break ステートマシン実装
- `Extended_Pictographic` プロパティ対応
- 合成絵文字（ZWJ シーケンス、国旗、肌色修飾子）対応
- mooncakes.io 公開
- 二段ルックアップテーブルによる O(1) プロパティ判定
- 安全アクセス (`get`)、`Show`/`Eq`/`Hash` trait、`is_empty`、`to_string`
- スライス操作（`view[1:3]`）
- イテレーション拡充（`rev_iter`、`iter2`、`grapheme_indices`）
- 遅延評価イテレータ `grapheme_iter()` — early-break 時に最大 64x 高速

## Unicode Version

Target: Unicode 17.0.0

## License

MIT License - Yoshiaki Kawazu (@kawaz)

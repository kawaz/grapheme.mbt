# DR-0006: Lone surrogate の取り扱い方針

- Status: Active
- Date: 2026-06-28

## Context

MoonBit の `String` は UTF-16 code unit 列で構成され、surrogate pair
(0xD800-0xDBFF + 0xDC00-0xDFFF) で BMP 外 (Plane 1-16, U+10000-U+10FFFF) を
表現する。**lone surrogate** (= ペアが揃わない単独 surrogate code unit) は
不正な UTF-16 だが、外部入力やバイナリ操作の結果として出現しうる。

本ライブラリは lone surrogate に対して以下のポリシーで処理する:

- **`grapheme_iter()` (lazy 経路)**: `decode_utf16` ヘルパが lone high
  surrogate を検出した場合、その単体 code unit を 1 つの code point として
  扱う (= `(unit, 1)` を返す)。これは「壊れた入力でも crash させずに最善
  努力で読む」方針 (lenient mode)。
- **`graphemes()` (pre-scan 経路)**: 文字列を `for ch in s` で iterate する。
  MoonBit の文字列 iteration は surrogate pair を 1 つの Char (Int) として
  扱う一方、lone surrogate は単体 Char としてそのまま渡される。

両経路は **同じ「lone surrogate を 1 cluster 切り」** の振る舞いに収束する
が、内部の到達経路が異なる (= `graphemes()` は MoonBit iteration の挙動に
依存、`grapheme_iter()` は `decode_utf16` の明示的フォールバック)。この
**意図的な実装非対称**は仕様 (lone surrogate を crash させない) を満たす
ための実装選択で、parity を壊しているわけではない。

## Decision

Lone surrogate の取り扱いを以下のとおり固定する:

1. **crash させない**: いかなる入力に対しても panic / index out of range
   を起こさない。
2. **lone high surrogate (0xD800-0xDBFF) の後に valid low が来ない場合**:
   lone high surrogate を **単独 1 code point として 1 cluster** に切り出す
   (= GB999: Any ÷ Any、隣接コードポイントとの境界判定は通常通り)。
3. **trailing lone high surrogate (文字列末尾)**: 同じく単独 1 cluster と
   して切り出す。

両経路の **API 観察結果は同じ** (= `grapheme_iter(s).collect() ==
graphemes(s).iter().collect()`)、実装内部の経路差は許容する。

## Alternatives Considered

- 案 A: lone surrogate を error として `Result[GraphemeView, ...]` で返す
  - 不採用理由: API が複雑化し、99% の正常入力 (= valid UTF-16) で利用者が
    余分な unwrap を強いられる。MoonBit core の文字列処理も lenient なので
    本ライブラリだけ strict にすると整合が崩れる。
- 案 B: lone surrogate を `U+FFFD` (REPLACEMENT CHARACTER) に置換する
  - 不採用理由: 文字列の長さが変わると `to_string()` が source の round-trip
    にならなくなる。invariant「`to_string()` は source slice を返す」が壊れる。
- 案 C: 両経路の実装を統一する (= `graphemes()` も `decode_utf16` を使う)
  - 不採用理由: pre-scan 経路は MoonBit iteration の最適化を活かしている
    (= for ch in s が compiler 最適化対象)、わざわざ手書きの decode_utf16 を
    挟むと性能が落ちる。観察可能挙動が同じである限り、内部経路の差は許容。

## Consequences

- `src/lib_wbtest.mbt` の lone-surrogate test (現状 2001-2014 周辺) は本 DR
  を cross-ref し、「lone high surrogate を 1 cluster として切る」「両経路の
  cluster 列が一致する」両軸を明示テストする。
- 将来 MoonBit の文字列処理が strict mode (= lone surrogate を error 化)
  を導入した場合、本ライブラリの挙動も追従するかは別 DR で再判断する。
- Code review で「lone surrogate を `U+FFFD` 置換に変えたい」のような提案
  が出たら、本 DR の Decision 3. invariant を盾に却下する (= 意図的な非対称
  であり、bug ではない)。

## 関連

- [DR-0003-uax29-corpus-coverage-strategy](./DR-0003-uax29-corpus-coverage-strategy.md)
  (= 公式コーパスは lone surrogate を扱わない、本 test ファイルが担う)
- 実装: `src/lib.mbt::decode_utf16`, `src/lib.mbt::grapheme_iter`,
  `src/lib.mbt::graphemes`
- UAX #29 §3 "Unicode Conformance Requirements" (実装が ill-formed sequence
  に対してどう振る舞うかの一般指針)

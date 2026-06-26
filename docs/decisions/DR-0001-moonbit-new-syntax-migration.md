# DR-0001: MoonBit 新文法・新 deprecation への追従

- Status: Active
- Date: 2026-06-26

## Context

MoonBit toolchain (`moon 0.1.20260618`) でいくつかの破壊的変更が入った:

1. `moon.mod.json` / `moon.pkg.json` (JSON) → `moon.mod` / `moon.pkg`
   (TOML-like 専用記法)。`moon fmt` が自動で移行する。
2. `impl T with output(...)` → `impl T with fn output(...)` (fn 必須)。
   `moon fmt` が自動補正する。
3. `StringView::to_string()` deprecated → `to_owned()` (Show::to_string と
   役割分離)。
4. composed value (Array / Tuple / Option 等) に対する `Show` 経由の
   `inspect()` deprecated → `Debug` trait と `@debug.debug_inspect()`。

`moon check --deny-warn` で 92 件の deprecation warning が出ていた。

## Decision

全て新文法・新 API に追従する:

- `moon.mod` 新形式に移行 (moon fmt 任せ)。
- `impl ... with fn output(...)` に統一 (moon fmt 任せ)。
- StringView の `.to_string()` を全て `.to_owned()` に置換 (実装側 2 箇所 +
  white-box テスト + 自動生成テスト)。
- white-box テスト内の composed value に対する `inspect(...)` を
  `@debug.debug_inspect(...)` に置換。`src/moon.pkg` に
  `import { "moonbitlang/core/debug" } for "wbtest"` を追加。
- `tools/gen_uax29_tests.py` も `to_owned` を生成するよう更新
  (再生成テストファイルに deprecation が再混入しないため)。

## Alternatives Considered

- 案 A: `moon check --deny-warn` の deny を緩めて warning を残す
  - 不採用理由: deprecation は遠からず error 化する。最新 toolchain で
    push 出来なくなる前に追従するのが安い。`just check` が CI 経路と
    乖離するのも避けたい。
- 案 B: 自動生成テスト (`src/uax29_test.mbt`) は触らず generator も放置、
  生成物に warning を残す
  - 不採用理由: 生成物 1391 件の warning を残すと「0 warning」invariant を
    維持できず、新規 warning に気付けなくなる。generator を直しておけば
    将来の Unicode bump 時にも再混入しない。

## Consequences

- `moon check --deny-warn` が 0 warning でクリーン。
- white-box テスト (`*_wbtest.mbt`) は `@debug.debug_inspect` 経由で
  Debug repr スナップショットを取る形式に統一。
- `src/moon.pkg` に `wbtest` カテゴリの `@debug` 依存が追加。publish には
  含まれない (white-box テストは publish 除外)。
- `tools/gen_uax29_tests.py` の出力が変わるため、Unicode 更新時の
  `just gen-tests` は新形式の `assert_eq(g[i].to_owned(), ...)` を吐く。

## 関連

- 公式ガイド: <https://github.com/moonbitlang/core/blob/main/debug/README.mbt.md>
- [journal/2026-06-26-moonbit-syntax-update.md](../journal/2026-06-26-moonbit-syntax-update.md)
  — 移行作業の経緯

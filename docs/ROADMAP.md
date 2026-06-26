# ロードマップ

将来検討項目のリスト。確定した予定ではなく、検討中のアイデアを集める場所。

## 短期 (= 直近着手候補)

- Unicode バージョン更新の追従 (`.unicode-version` を bump → `just gen` → release)

## 中期 (= 構想中)

- `grapheme_iter` 系 API の最適化 (現在 boundaries 配列を作らない lazy パスを持つが、
  StringView 切り出しの allocation を更に削れないか検討)
- benchmark の baseline 自動回帰検出 (CI 上で前回値と比較し、回帰閾値超で fail)

## 長期 / アイデア (= 検討初期)

- Word / Sentence segmentation (UAX #29 の grapheme 以外のパート) を別パッケージで提供する案

## 関連

- [decisions/INDEX.md](./decisions/INDEX.md) — 確定した設計判断
- [DESIGN-ja.md](./DESIGN-ja.md) — 現実装の説明

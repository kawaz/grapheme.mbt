# ドキュメント i18n ルール

正本は常に `*-ja.md`、英語版は publish タイミングで原本から同期する。
詳細は personal-docs-structure skill の「言語ポリシー」と
「相互リンクのテンプレ」を参照。

## このリポでの対象ペア

- `README.md` (英訳) / `README-ja.md` (原本)
- `docs/DESIGN.md` (英訳) / `docs/DESIGN-ja.md` (原本)

## 相互リンクヘッダ

タイトル直下に `>` blockquote で配置。リンクは同ディレクトリの対応ファイルへ
`./` 付きの相対パスで書く。

英語版:

```markdown
# Title

> English | [日本語](./README-ja.md)
```

日本語版:

```markdown
# Title

> [English](./README.md) | 日本語
```

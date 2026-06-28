#!/usr/bin/env python3
"""
Unicode UAX #29 GraphemeBreakTest テスト生成スクリプト

GraphemeBreakTest.txt から MoonBit のテストコードを生成する。

入力: tools/data/<UNICODE_VERSION>/GraphemeBreakTest.txt
出力:
  - src/uax29_test.mbt        (graphemes() のホワイトボックステスト)
  - src/uax29_iter_test.mbt   (grapheme_iter() と graphemes() の parity テスト
                               -- DR-0004 segmenter-state-parity の二重化検証)
"""

import hashlib
import os
import re
import sys
import urllib.request
from pathlib import Path

UNICODE_VERSION = (Path(__file__).resolve().parent.parent / ".unicode-version").read_text().strip()
TEST_DATA_URL = f"https://www.unicode.org/Public/{UNICODE_VERSION}/ucd/auxiliary/GraphemeBreakTest.txt"

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
DATA_DIR = SCRIPT_DIR / "data" / UNICODE_VERSION
OUTPUT_FILE = PROJECT_ROOT / "src" / "uax29_test.mbt"
ITER_OUTPUT_FILE = PROJECT_ROOT / "src" / "uax29_iter_test.mbt"


def download_if_needed():
    """テストデータをダウンロード（未取得の場合のみ）"""
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    filepath = DATA_DIR / "GraphemeBreakTest.txt"
    if not filepath.exists():
        print(f"Downloading GraphemeBreakTest.txt ...")
        urllib.request.urlretrieve(TEST_DATA_URL, filepath)
        print(f"  -> {filepath}")
    return filepath


def parse_test_line(line: str):
    """
    テスト行をパースする。

    入力例: '÷ 0020 ÷ 0020 ÷\t#  ÷ [0.2] SPACE (Other) ÷ [999.0] SPACE (Other) ÷ [0.3]'

    返り値: (clusters, comment)
      clusters: list of list of int  -- 各クラスタのコードポイントリスト
      comment: str                   -- '#' 以降のコメント文字列
    """
    # コメント分離
    comment = ""
    if "#" in line:
        data_part, comment = line.split("#", 1)
        comment = comment.strip()
    else:
        data_part = line

    data_part = data_part.strip()
    if not data_part:
        return None, comment

    # ÷ と × でトークン分割
    # データ部分: "÷ 0020 ÷ 0020 ÷" or "÷ 0020 × 0308 ÷ 0020 ÷"
    # 先頭と末尾の ÷ を除去してからパース
    tokens = data_part.split()

    clusters = []
    current_cluster = []

    i = 0
    while i < len(tokens):
        tok = tokens[i]
        if tok == "÷":  # ÷ (break)
            if current_cluster:
                clusters.append(current_cluster)
                current_cluster = []
        elif tok == "×":  # × (no break)
            pass  # 境界なし、同じクラスタに追加し続ける
        else:
            # 16進コードポイント
            cp = int(tok, 16)
            current_cluster.append(cp)
        i += 1

    if current_cluster:
        clusters.append(current_cluster)

    return clusters, comment


def extract_short_comment(comment: str) -> str:
    """コメントから短い説明を抽出する"""
    if not comment:
        return ""
    # コメントから文字名だけを抽出（括弧内のプロパティ名やルール番号を除去）
    # 例: "÷ [0.2] SPACE (Other) ÷ [999.0] SPACE (Other) ÷ [0.3]"
    # → "SPACE / SPACE"
    names = []
    # パターン: ルール番号の後に文字名が来る
    # [数字.数字] の後にある文字名（括弧の前まで）を抽出
    parts = re.findall(r'\]\s+([^(÷×]+?)\s*\(', comment)
    for part in parts:
        name = part.strip()
        if name and name not in ("[", "]"):
            # 長い名前は短縮
            if len(name) > 30:
                name = name[:27] + "..."
            names.append(name)

    if names:
        return " / ".join(names)
    return ""


def escape_for_test_name(s: str) -> str:
    """テスト名に使える文字列にエスケープする"""
    # MoonBit のテスト名は文字列リテラルなのでほぼ何でも使える
    # ただしダブルクォートとバックスラッシュはエスケープ
    s = s.replace("\\", "\\\\")
    s = s.replace('"', '\\"')
    # 改行を除去
    s = s.replace("\n", " ")
    return s


def cp_to_moonbit_escape(cp: int) -> str:
    """コードポイントを MoonBit の \\u{XXXX} 形式に変換"""
    return f"\\u{{{cp:04X}}}"


def cluster_to_string_literal(cluster: list) -> str:
    """クラスタ (コードポイント列) を MoonBit の文字列リテラル (中身) に変換"""
    return "".join(cp_to_moonbit_escape(cp) for cp in cluster)


def cluster_utf16_units(cluster: list) -> int:
    """
    クラスタの UTF-16 コードユニット幅を算出する。
    MoonBit の String は UTF-16 表現 (StringView の offset は code-unit ベース)。
    BMP (< U+10000) は 1 unit、supplementary plane は surrogate pair で 2 unit。
    """
    width = 0
    for cp in cluster:
        if cp >= 0x10000:
            width += 2
        else:
            width += 1
    return width


def has_supplementary(clusters: list) -> bool:
    """いずれかのコードポイントが BMP 外 (>= U+10000) か"""
    for cluster in clusters:
        for cp in cluster:
            if cp >= 0x10000:
                return True
    return False


def generate_test(test_num: int, clusters: list, comment: str, raw_line: str) -> str:
    """1つのテストケースを生成する (uax29_test.mbt 用)"""
    short_comment = extract_short_comment(comment)
    test_name = f"UAX29/{test_num:04d}"
    if short_comment:
        test_name += f": {escape_for_test_name(short_comment)}"

    lines = []
    lines.append("///|")
    lines.append(f'test "{test_name}" {{')

    # 元の行をコメントとして追加（短縮）
    raw_data = raw_line.split("#")[0].strip() if "#" in raw_line else raw_line.strip()
    lines.append(f"  // {raw_data}")

    # 入力文字列の構築
    all_cps = []
    for cluster in clusters:
        all_cps.extend(cluster)

    input_str = "".join(cp_to_moonbit_escape(cp) for cp in all_cps)
    lines.append(f'  let input = "{input_str}"')
    lines.append(f"  let g = graphemes(input)")
    lines.append(f"  assert_eq(g.length(), {len(clusters)})")

    # 各クラスタの検証 (インデックス経由)
    cluster_literals = []
    for i, cluster in enumerate(clusters):
        cluster_str = cluster_to_string_literal(cluster)
        cluster_literals.append(f'"{cluster_str}"')
        cp_hex = " ".join(f"{cp:04X}" for cp in cluster)
        lines.append(f'  // cluster {i}: [{cp_hex}]')
        lines.append(f'  assert_eq(g[{i}].to_owned(), "{cluster_str}")')

    # iter() ordering: インデックス参照の順序と iter() の順序が一致することを
    # 1 assertion で固定する (DR-0004 segmenter-state-parity — graphemes() と
    # iter() の双方が同じクラスタ列を返す invariant)。
    # 注: 本来は `assert_eq(... .collect(), [...])` で書きたいが、プロジェクトの
    # lint policy `moon check --deny-warn` は Array[String] に対する assert_eq を
    # deprecated 警告 (Show vs Debug の遷移) で error 化する。等価判定の意図を
    # 保ったまま `assert_true(... == [...])` 形で書くことで lint を通している。
    expected_array = "[" + ", ".join(cluster_literals) + "]"
    lines.append(
        f"  assert_true(graphemes(input).iter().map(fn(v) {{ v.to_owned() }}).collect() == {expected_array})"
    )

    # supplementary 面を含む場合: grapheme_indices() の (start, end) 差分が
    # UTF-16 code-unit ベースで supplementary を +2 計上することを固定。
    # lint policy 上 Array[Int] も Show vs Debug 警告で deny されるため
    # `assert_true(== )` で等価判定する。
    if has_supplementary(clusters):
        widths = [cluster_utf16_units(c) for c in clusters]
        widths_array = "[" + ", ".join(str(w) for w in widths) + "]"
        lines.append(
            f"  assert_true(graphemes(input).grapheme_indices().map(fn(t) {{ t.1 - t.0 }}).collect() == {widths_array})"
        )

    lines.append("}")
    return "\n".join(lines)


def generate_iter_test(test_num: int, clusters: list, comment: str, raw_line: str) -> str:
    """1つの iter parity テストケースを生成する (uax29_iter_test.mbt 用)"""
    short_comment = extract_short_comment(comment)
    test_name = f"UAX29/{test_num:04d}-iter"
    if short_comment:
        test_name += f": {escape_for_test_name(short_comment)}"

    lines = []
    lines.append("///|")
    lines.append(f'test "{test_name}" {{')

    raw_data = raw_line.split("#")[0].strip() if "#" in raw_line else raw_line.strip()
    lines.append(f"  // {raw_data}")

    all_cps = []
    for cluster in clusters:
        all_cps.extend(cluster)
    input_str = "".join(cp_to_moonbit_escape(cp) for cp in all_cps)
    lines.append(f'  let input = "{input_str}"')
    lines.append(
        "  let from_iter = grapheme_iter(input).map(fn(v) { v.to_owned() }).collect()"
    )
    lines.append(
        "  let from_view = graphemes(input).iter().map(fn(v) { v.to_owned() }).collect()"
    )
    # lint policy 上 Array[String] への assert_eq は deprecated 警告 (Show vs Debug)
    # で deny されるため、等価判定の意図を保ったまま `assert_true(== )` で書く。
    lines.append("  assert_true(from_iter == from_view)")
    lines.append("}")
    return "\n".join(lines)


def main():
    data_file = download_if_needed()
    corpus_bytes = data_file.read_bytes()
    corpus_sha = hashlib.sha256(corpus_bytes).hexdigest()
    print(f"Parsing {data_file} ...")
    print(f"  sha256 = {corpus_sha}")

    tests = []
    iter_tests = []
    test_num = 0

    for line in corpus_bytes.decode("utf-8").splitlines():
        line = line.rstrip("\n")
        # 空行・コメント行をスキップ
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue

        # テスト行（÷ で始まる）
        if stripped.startswith("÷"):
            test_num += 1
            clusters, comment = parse_test_line(stripped)
            if clusters is not None:
                tests.append(generate_test(test_num, clusters, comment, stripped))
                iter_tests.append(generate_iter_test(test_num, clusters, comment, stripped))

    print(f"Generated {len(tests)} tests (+{len(iter_tests)} iter parity tests)")

    # uax29_test.mbt header (源コーパス URL + SHA-256 + DR 相互参照)
    header = f"""\
// Auto-generated by tools/gen_uax29_tests.py (Unicode {UNICODE_VERSION} GraphemeBreakTest.txt)
// DO NOT EDIT THIS FILE MANUALLY
//
// Source: {TEST_DATA_URL}
// Corpus SHA-256: {corpus_sha}
// Cross-refs: DR-0003 (UAX#29 corpus coverage strategy) / DR-0004 (segmenter-state parity)
// Test count: {len(tests)}

"""

    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        f.write(header)
        f.write("\n\n".join(tests))
        f.write("\n")
    print(f"Output: {OUTPUT_FILE}")

    iter_header = f"""\
// Auto-generated by tools/gen_uax29_tests.py (Unicode {UNICODE_VERSION} GraphemeBreakTest.txt)
// DO NOT EDIT THIS FILE MANUALLY
//
// Source: {TEST_DATA_URL}
// Corpus SHA-256: {corpus_sha}
// Purpose: grapheme_iter() と graphemes().iter() の parity 検証
//          (DR-0004 segmenter-state-parity — 同一入力に対し両 API が
//           同じクラスタ列を返す invariant をコーパス全件で固定する)
// Test count: {len(iter_tests)}

"""
    with open(ITER_OUTPUT_FILE, "w", encoding="utf-8") as f:
        f.write(iter_header)
        f.write("\n\n".join(iter_tests))
        f.write("\n")
    print(f"Output: {ITER_OUTPUT_FILE}")

    print(f"Total tests: {len(tests)} (+ {len(iter_tests)} iter parity)")


if __name__ == "__main__":
    main()

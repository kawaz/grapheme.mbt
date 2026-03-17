#!/usr/bin/env python3
"""
Unicode UAX #29 GraphemeBreakTest テスト生成スクリプト

GraphemeBreakTest.txt から MoonBit のテストコードを生成する。

入力: tools/data/GraphemeBreakTest.txt
出力: src/uax29_test.mbt (ホワイトボックステスト)
"""

import os
import re
import sys
import urllib.request
from pathlib import Path

UNICODE_VERSION = (Path(__file__).resolve().parent.parent / ".unicode-version").read_text().strip()
TEST_DATA_URL = f"https://www.unicode.org/Public/{UNICODE_VERSION}/ucd/auxiliary/GraphemeBreakTest.txt"

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
DATA_DIR = SCRIPT_DIR / "data"
OUTPUT_FILE = PROJECT_ROOT / "src" / "uax29_test.mbt"


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
        if tok == "\u00F7":  # ÷ (break)
            if current_cluster:
                clusters.append(current_cluster)
                current_cluster = []
        elif tok == "\u00D7":  # × (no break)
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


def generate_test(test_num: int, clusters: list, comment: str, raw_line: str) -> str:
    """1つのテストケースを生成する"""
    short_comment = extract_short_comment(comment)
    test_name = f"UAX29/{test_num:04d}"
    if short_comment:
        test_name += f": {escape_for_test_name(short_comment)}"

    lines = []
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

    # 各クラスタの検証
    for i, cluster in enumerate(clusters):
        cluster_str = "".join(cp_to_moonbit_escape(cp) for cp in cluster)
        cp_hex = " ".join(f"{cp:04X}" for cp in cluster)
        lines.append(f'  // cluster {i}: [{cp_hex}]')
        lines.append(f'  assert_eq(g[{i}].to_string(), "{cluster_str}")')

    lines.append("}")
    return "\n".join(lines)


def main():
    data_file = download_if_needed()
    print(f"Parsing {data_file} ...")

    tests = []
    test_num = 0

    with open(data_file, "r", encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            # 空行・コメント行をスキップ
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue

            # テスト行（÷ で始まる）
            if stripped.startswith("\u00F7"):
                test_num += 1
                clusters, comment = parse_test_line(stripped)
                if clusters is not None:
                    test_code = generate_test(test_num, clusters, comment, stripped)
                    tests.append(test_code)

    print(f"Generated {len(tests)} tests")

    # 出力
    header = f"""\
// Auto-generated by tools/gen_uax29_tests.py (Unicode {UNICODE_VERSION} GraphemeBreakTest.txt)
// DO NOT EDIT THIS FILE MANUALLY
// Test count: {len(tests)}

"""

    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        f.write(header)
        f.write("\n\n".join(tests))
        f.write("\n")

    print(f"Output: {OUTPUT_FILE}")
    print(f"Total tests: {len(tests)}")


if __name__ == "__main__":
    main()

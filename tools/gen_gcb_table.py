#!/usr/bin/env python3
"""
Unicode GCB テーブル生成スクリプト

Unicode 16.0.0 の UCD データから MoonBit 用の GCB テーブルコードを生成する。

入力:
  - GraphemeBreakProperty.txt (GCB プロパティ)
  - emoji-data.txt (Extended_Pictographic)
  - DerivedCoreProperties.txt (InCB プロパティ)

出力:
  - src/gcb_table.mbt
"""

import os
import re
import sys
import urllib.request
from pathlib import Path

UNICODE_VERSION = (Path(__file__).resolve().parent.parent / ".unicode-version").read_text().strip()
BASE_URL = f"https://www.unicode.org/Public/{UNICODE_VERSION}/ucd"

DATA_FILES = {
    "GraphemeBreakProperty.txt": f"{BASE_URL}/auxiliary/GraphemeBreakProperty.txt",
    "emoji-data.txt": f"{BASE_URL}/emoji/emoji-data.txt",
    "DerivedCoreProperties.txt": f"{BASE_URL}/DerivedCoreProperties.txt",
}

# GCB property name → MoonBit enum variant
GCB_MAP = {
    "CR": "CR",
    "LF": "LF",
    "Control": "Control",
    "Extend": "Extend",
    "ZWJ": "ZWJ",
    "Regional_Indicator": "Regional_Indicator",
    "Prepend": "Prepend",
    "SpacingMark": "SpacingMark",
    "L": "L",
    "V": "V",
    "T": "T",
    "LV": "LV",
    "LVT": "LVT",
}

SCRIPT_DIR = Path(__file__).resolve().parent
DATA_DIR = SCRIPT_DIR / "data" / UNICODE_VERSION
PROJECT_ROOT = SCRIPT_DIR.parent
OUTPUT_FILE = PROJECT_ROOT / "src" / "gcb_table.mbt"


def download_if_missing(filename: str) -> Path:
    """データファイルが存在しなければダウンロードする。"""
    filepath = DATA_DIR / filename
    if filepath.exists():
        print(f"  [cached] {filename}")
        return filepath
    url = DATA_FILES[filename]
    print(f"  [download] {filename} from {url}")
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    urllib.request.urlretrieve(url, filepath)
    return filepath


def parse_ranges(filepath: Path, property_filter: str | None = None) -> list[tuple[int, int, str]]:
    """
    UCD フォーマットのファイルをパースし、(start, end, property) のリストを返す。

    property_filter が指定された場合、そのプロパティ値のみ抽出する。
    """
    entries = []
    with open(filepath, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            # コメント除去
            if "#" in line:
                line = line[: line.index("#")]
            parts = [p.strip() for p in line.split(";")]
            if len(parts) < 2:
                continue
            code_range = parts[0].strip()
            prop = parts[1].strip()
            if property_filter is not None and prop != property_filter:
                continue
            if ".." in code_range:
                start_s, end_s = code_range.split("..")
                start = int(start_s, 16)
                end = int(end_s, 16)
            else:
                start = int(code_range, 16)
                end = start
            entries.append((start, end, prop))
    return entries


def parse_incb(filepath: Path) -> dict[str, list[tuple[int, int]]]:
    """
    DerivedCoreProperties.txt から InCB プロパティを抽出する。

    Returns:
        {"Linker": [(start, end), ...], "Consonant": [...], "Extend": [...]}
    """
    result: dict[str, list[tuple[int, int]]] = {
        "Linker": [],
        "Consonant": [],
        "Extend": [],
    }
    with open(filepath, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "InCB" not in line:
                continue
            # コメント除去
            comment_pos = line.find("#")
            if comment_pos >= 0:
                line = line[:comment_pos]
            parts = [p.strip() for p in line.split(";")]
            if len(parts) < 3:
                continue
            code_range = parts[0].strip()
            # parts[1] == "InCB"
            incb_value = parts[2].strip()
            if incb_value not in result:
                continue
            if ".." in code_range:
                start_s, end_s = code_range.split("..")
                start = int(start_s, 16)
                end = int(end_s, 16)
            else:
                start = int(code_range, 16)
                end = start
            result[incb_value].append((start, end))
    # ソート
    for k in result:
        result[k].sort()
    return result


def merge_ranges(
    entries: list[tuple[int, int, str]],
) -> list[tuple[int, int, str]]:
    """隣接する同一カテゴリのレンジをマージする。"""
    if not entries:
        return []
    entries.sort(key=lambda x: (x[0], x[1]))
    merged = [entries[0]]
    for start, end, cat in entries[1:]:
        prev_start, prev_end, prev_cat = merged[-1]
        if cat == prev_cat and start == prev_end + 1:
            merged[-1] = (prev_start, end, cat)
        else:
            merged.append((start, end, cat))
    return merged


def merge_int_ranges(ranges: list[tuple[int, int]]) -> list[tuple[int, int]]:
    """隣接するレンジをマージする。"""
    if not ranges:
        return []
    ranges = sorted(ranges)
    merged = [ranges[0]]
    for start, end in ranges[1:]:
        prev_start, prev_end = merged[-1]
        if start <= prev_end + 1:
            merged[-1] = (prev_start, max(end, prev_end))
        else:
            merged.append((start, end))
    return merged


def main():
    print(f"=== Unicode {UNICODE_VERSION} GCB Table Generator ===\n")

    # 1. データファイルのダウンロード
    print("Downloading data files...")
    gbp_file = download_if_missing("GraphemeBreakProperty.txt")
    emoji_file = download_if_missing("emoji-data.txt")
    dcp_file = download_if_missing("DerivedCoreProperties.txt")
    print()

    # 2. GraphemeBreakProperty を読み込む
    print("Parsing GraphemeBreakProperty.txt...")
    gbp_entries = parse_ranges(gbp_file)
    print(f"  {len(gbp_entries)} entries")

    # GCBプロパティ名をMoonBitバリアント名にマッピング
    # code_point → category のマップを構築（個別コードポイント単位）
    cp_category: dict[int, str] = {}
    for start, end, prop in gbp_entries:
        if prop not in GCB_MAP:
            print(f"  WARNING: Unknown GCB property '{prop}', skipping")
            continue
        cat = GCB_MAP[prop]
        for cp in range(start, end + 1):
            cp_category[cp] = cat

    # 3. Extended_Pictographic を読み込む
    print("Parsing emoji-data.txt (Extended_Pictographic)...")
    ep_entries = parse_ranges(emoji_file, property_filter="Extended_Pictographic")
    print(f"  {len(ep_entries)} entries")

    ep_applied = 0
    ep_skipped = 0
    for start, end, _ in ep_entries:
        for cp in range(start, end + 1):
            if cp not in cp_category:
                # GCB=Other → Extended_Pictographic
                cp_category[cp] = "Extended_Pictographic"
                ep_applied += 1
            else:
                # GCB が Other 以外の場合はスキップ（GCB 側を優先）
                ep_skipped += 1
    print(f"  Applied: {ep_applied}, Skipped (GCB != Other): {ep_skipped}")

    # 4. InCB を読み込む
    print("Parsing DerivedCoreProperties.txt (InCB)...")
    incb = parse_incb(dcp_file)
    print(f"  Linker: {len(incb['Linker'])} ranges")
    print(f"  Consonant: {len(incb['Consonant'])} ranges")
    print(f"  Extend: {len(incb['Extend'])} ranges")

    # InCB=Consonant → GCB=Other のコードポイントのみ InCB_Consonant に
    incb_consonant_applied = 0
    incb_consonant_warned = 0
    for start, end in incb["Consonant"]:
        for cp in range(start, end + 1):
            if cp not in cp_category:
                cp_category[cp] = "InCB_Consonant"
                incb_consonant_applied += 1
            else:
                existing = cp_category[cp]
                print(
                    f"  WARNING: U+{cp:04X} has GCB={existing} but InCB=Consonant, keeping GCB={existing}"
                )
                incb_consonant_warned += 1
    print(
        f"  InCB_Consonant applied: {incb_consonant_applied}, warned: {incb_consonant_warned}"
    )
    if incb_consonant_warned > 0:
        print(
            f"\nERROR: {incb_consonant_warned} InCB=Consonant code point(s) overlap with GCB != Other."
        )
        print(
            "  This means InCB_Consonant cannot be merged into the main GCB table."
        )
        print(
            "  Consider moving InCB_Consonant to an auxiliary table (see DESIGN.md)."
        )
        sys.exit(1)

    # 5. レンジに変換してマージ
    print("\nBuilding ranges...")
    range_entries: list[tuple[int, int, str]] = []
    # cp_category をソート済みレンジに変換
    sorted_cps = sorted(cp_category.keys())
    if sorted_cps:
        run_start = sorted_cps[0]
        run_cat = cp_category[run_start]
        run_end = run_start
        for cp in sorted_cps[1:]:
            cat = cp_category[cp]
            if cat == run_cat and cp == run_end + 1:
                run_end = cp
            else:
                range_entries.append((run_start, run_end, run_cat))
                run_start = cp
                run_cat = cat
                run_end = cp
        range_entries.append((run_start, run_end, run_cat))

    range_entries.sort()
    print(f"  {len(range_entries)} ranges in gcb_table")

    # 6. InCB 補助テーブルの構築
    # Linker: 個別コードポイントのリスト
    linker_cps: list[int] = []
    for start, end in incb["Linker"]:
        for cp in range(start, end + 1):
            linker_cps.append(cp)
    linker_cps.sort()
    print(f"  {len(linker_cps)} codepoints in incb_linker_table")

    # Extend: レンジのリスト（マージ済み）
    incb_extend_ranges = merge_int_ranges(incb["Extend"])
    print(f"  {len(incb_extend_ranges)} ranges in incb_extend_table")

    # 7. MoonBit コード生成
    print(f"\nGenerating {OUTPUT_FILE}...")
    lines: list[str] = []
    lines.append(
        f"// Auto-generated by tools/gen_gcb_table.py (Unicode {UNICODE_VERSION})"
    )
    lines.append("// DO NOT EDIT THIS FILE MANUALLY")
    lines.append("//")
    lines.append("// Generated from Unicode Character Database (UCD).")
    lines.append("// Copyright (c) 1991-2024 Unicode, Inc. All rights reserved.")
    lines.append("// Licensed under the Unicode License V3: https://www.unicode.org/license.txt")
    lines.append("")

    # メイン GCB テーブル
    lines.append(
        "let gcb_table : FixedArray[(Int, Int, GCBCategory)] = ["
    )
    for start, end, cat in range_entries:
        lines.append(f"  ({hex(start)}, {hex(end)}, {cat}),")
    lines.append("]")
    lines.append("")

    # InCB Linker テーブル
    lines.append("// InCB=Linker codepoints (sorted)")
    lines.append("let incb_linker_table : FixedArray[Int] = [")
    for cp in linker_cps:
        lines.append(f"  {hex(cp)},")
    lines.append("]")
    lines.append("")

    # InCB Extend テーブル
    lines.append("// InCB=Extend codepoint ranges (sorted)")
    lines.append("let incb_extend_table : FixedArray[(Int, Int)] = [")
    for start, end in incb_extend_ranges:
        lines.append(f"  ({hex(start)}, {hex(end)}),")
    lines.append("]")
    lines.append("")

    output_text = "\n".join(lines)
    OUTPUT_FILE.write_text(output_text, encoding="utf-8")
    print(f"  Written {len(output_text)} bytes")

    # 8. サマリ
    print(f"\n=== Summary ===")
    print(f"  gcb_table: {len(range_entries)} entries")
    print(f"  incb_linker_table: {len(linker_cps)} entries")
    print(f"  incb_extend_table: {len(incb_extend_ranges)} entries")
    print(f"  Output: {OUTPUT_FILE}")

    return 0


if __name__ == "__main__":
    sys.exit(main())

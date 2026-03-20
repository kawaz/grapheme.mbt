#!/usr/bin/env python3
"""
Unicode GCB テーブル生成スクリプト

UCD データから MoonBit 用の GCB テーブルコードを生成する。
対象バージョンは .unicode-version ファイルで指定。

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

    # 5. 二段ルックアップテーブルの構築
    # GCBCategory → 数値マッピング（enum 定義順）
    CAT_TO_ID = {
        "Other": 0, "CR": 1, "LF": 2, "Control": 3, "Extend": 4,
        "ZWJ": 5, "Regional_Indicator": 6, "Prepend": 7, "SpacingMark": 8,
        "L": 9, "V": 10, "T": 11, "LV": 12, "LVT": 13,
        "Extended_Pictographic": 14, "InCB_Consonant": 15,
    }

    BLOCK_SIZE = 256
    MAX_CP = 0x10FFFF
    # Plane 0-2 limit: only U+0000..U+02FFFF goes into the two-stage table.
    # Plane 14 Tags (E0001, E0020-E007F: Control, E0100-E01EF: Extend) are
    # handled by branch logic in gcb_category(). Planes 3-13, 15-16 are all Other.
    TABLE_MAX_CP = 0x02FFFF

    print("\nBuilding two-stage lookup table...")
    print(f"  Block size: {BLOCK_SIZE}")
    print(f"  Table range: U+0000..U+{TABLE_MAX_CP:06X} (Plane 0-2)")
    print(f"  Plane 14 Tags handled by branch logic in gcb_category()")

    # Verify Plane 14 entries (for branch logic in gcb_category())
    plane14_entries: dict[int, str] = {}
    for cp_val, cat_name in cp_category.items():
        if cp_val >= 0xE0000 and cp_val <= 0xEFFFF:
            plane14_entries[cp_val] = cat_name
    if plane14_entries:
        print(f"\n  Plane 14 entries ({len(plane14_entries)} codepoints):")
        # Group into ranges for display
        sorted_cps = sorted(plane14_entries.keys())
        range_start = sorted_cps[0]
        range_cat = plane14_entries[range_start]
        range_end = range_start
        for cp_val in sorted_cps[1:]:
            if cp_val == range_end + 1 and plane14_entries[cp_val] == range_cat:
                range_end = cp_val
            else:
                print(f"    U+{range_start:06X}..U+{range_end:06X}: {range_cat}")
                range_start = cp_val
                range_cat = plane14_entries[cp_val]
                range_end = cp_val
        print(f"    U+{range_start:06X}..U+{range_end:06X}: {range_cat}")
        print("  These will be handled by branch logic, not included in the table.")

    # Verify no non-Other entries exist in Planes 3-13, 15-16
    out_of_range_entries = {
        cp_val: cat_name
        for cp_val, cat_name in cp_category.items()
        if cp_val > TABLE_MAX_CP and not (0xE0000 <= cp_val <= 0xEFFFF)
    }
    if out_of_range_entries:
        print(f"\nERROR: Found {len(out_of_range_entries)} non-Other entries outside Plane 0-2 and Plane 14:")
        for cp_val in sorted(out_of_range_entries.keys())[:10]:
            print(f"  U+{cp_val:06X}: {out_of_range_entries[cp_val]}")
        sys.exit(1)

    # 全コードポイントの GCB ID テーブルを構築 (Plane 0-2 only)
    full_table = bytearray(TABLE_MAX_CP + 1)  # 0 = Other
    for cp_val, cat_name in cp_category.items():
        if cp_val <= TABLE_MAX_CP:
            full_table[cp_val] = CAT_TO_ID[cat_name]

    # Stage1/Stage2 構築（重複ブロック排除）
    num_blocks = (TABLE_MAX_CP + 1 + BLOCK_SIZE - 1) // BLOCK_SIZE
    block_map: dict[bytes, int] = {}
    unique_blocks: list[bytes] = []
    stage1: list[int] = []

    for i in range(num_blocks):
        start = i * BLOCK_SIZE
        end = min(start + BLOCK_SIZE, MAX_CP + 1)
        block = bytes(full_table[start:end])
        if len(block) < BLOCK_SIZE:
            block = block + bytes(BLOCK_SIZE - len(block))
        if block not in block_map:
            block_map[block] = len(unique_blocks)
            unique_blocks.append(block)
        stage1.append(block_map[block])

    # 4bit パック: 各ブロック 256 entries → 128 bytes
    packed_stage2 = bytearray()
    for block in unique_blocks:
        for j in range(0, BLOCK_SIZE, 2):
            hi_nibble = block[j]
            lo_nibble = block[j + 1] if j + 1 < BLOCK_SIZE else 0
            packed_stage2.append((hi_nibble << 4) | lo_nibble)

    print(f"  Stage1: {len(stage1)} entries (max index: {max(stage1)})")
    print(f"  Stage2: {len(unique_blocks)} unique blocks / {num_blocks} total ({(1 - len(unique_blocks) / num_blocks) * 100:.1f}% dedup)")
    print(f"  Stage1 size: {len(stage1)} bytes")
    print(f"  Stage2 size: {len(packed_stage2)} bytes (4-bit packed)")
    print(f"  Total: {len(stage1) + len(packed_stage2)} bytes ({(len(stage1) + len(packed_stage2)) / 1024:.1f} KB)")

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

    def bytes_literal(data: bytes | bytearray) -> str:
        """bytes データを MoonBit の b"\\xHH..." リテラルに変換する（単一リテラル）。"""
        hex_str = "".join(f"\\x{b:02X}" for b in data)
        return f'  b"{hex_str}"'

    lines: list[str] = []
    lines.append(
        f"// Auto-generated by tools/gen_gcb_table.py (Unicode {UNICODE_VERSION})"
    )
    lines.append("// DO NOT EDIT THIS FILE MANUALLY")
    lines.append("//")
    lines.append("// Generated from Unicode Character Database (UCD).")
    lines.append("// Copyright (c) 1991-2025 Unicode, Inc. All rights reserved.")
    lines.append("// Licensed under the Unicode License V3: https://www.unicode.org/license.txt")
    lines.append("//")
    lines.append(f"// Two-stage lookup table (block size: {BLOCK_SIZE}, 4-bit packed)")
    lines.append(f"// Covers Plane 0-2 (U+0000..U+02FFFF) only.")
    lines.append(f"// Plane 14 Tags (E0000-E001F, E0080-E00FF, E01F0-E0FFF: Control;")
    lines.append(f"//   E0020-E007F, E0100-E01EF: Extend) are handled by branch logic")
    lines.append(f"// in gcb_category().")
    lines.append(f"// Planes 3-13, 15-16 are all Other.")
    lines.append(f"//")
    lines.append(f"// Stage1: {len(stage1)} bytes ({len(stage1)} entries, 1 byte each)")
    lines.append(f"// Stage2: {len(packed_stage2)} bytes ({len(unique_blocks)} unique blocks x {BLOCK_SIZE // 2} bytes)")
    lines.append(f"// Total:  {len(stage1) + len(packed_stage2)} bytes")
    lines.append("//")
    lines.append("// Lookup: stage1[cp >> 8] -> block index")
    lines.append("//         stage2[block_idx * 128 + (cp & 0xFF) >> 1] -> nibble extraction")
    lines.append("")

    # Stage 1
    lines.append("// Stage 1: block index table (cp >> 8)")
    lines.append("")
    lines.append("///|")
    lines.append("let gcb_stage1 : Bytes =")
    lines.append(bytes_literal(bytes(stage1)))
    lines.append("")

    # Stage 2
    lines.append("// Stage 2: property values (4-bit packed, 256 entries per block -> 128 bytes per block)")
    lines.append("")
    lines.append("///|")
    lines.append("let gcb_stage2 : Bytes =")
    lines.append(bytes_literal(packed_stage2))
    lines.append("")

    # InCB Linker テーブル (packed: 3 bytes per codepoint, big-endian)
    linker_packed = bytearray()
    for cp in linker_cps:
        linker_packed.append((cp >> 16) & 0xFF)
        linker_packed.append((cp >> 8) & 0xFF)
        linker_packed.append(cp & 0xFF)

    lines.append(f"// InCB=Linker codepoints (sorted, packed: 3 bytes/entry, {len(linker_cps)} entries = {len(linker_packed)} bytes)")
    lines.append("")
    lines.append("///|")
    lines.append("let incb_linker_packed : Bytes =")
    lines.append(bytes_literal(linker_packed))
    lines.append("")

    # InCB Extend テーブル (packed: 6 bytes per range, start 3B + end 3B, big-endian)
    extend_packed = bytearray()
    for start, end in incb_extend_ranges:
        extend_packed.append((start >> 16) & 0xFF)
        extend_packed.append((start >> 8) & 0xFF)
        extend_packed.append(start & 0xFF)
        extend_packed.append((end >> 16) & 0xFF)
        extend_packed.append((end >> 8) & 0xFF)
        extend_packed.append(end & 0xFF)

    lines.append(f"// InCB=Extend codepoint ranges (sorted, packed: 6 bytes/entry, {len(incb_extend_ranges)} entries = {len(extend_packed)} bytes)")
    lines.append("")
    lines.append("///|")
    lines.append("let incb_extend_packed : Bytes =")
    lines.append(bytes_literal(extend_packed))
    lines.append("")

    output_text = "\n".join(lines)
    OUTPUT_FILE.write_text(output_text, encoding="utf-8")
    print(f"  Written {len(output_text)} bytes")

    # 8. サマリ
    print(f"\n=== Summary ===")
    print(f"  gcb_stage1: {len(stage1)} bytes")
    print(f"  gcb_stage2: {len(packed_stage2)} bytes ({len(unique_blocks)} unique blocks)")
    print(f"  Total GCB table: {len(stage1) + len(packed_stage2)} bytes ({(len(stage1) + len(packed_stage2)) / 1024:.1f} KB)")
    print(f"  incb_linker_packed: {len(linker_packed)} bytes ({len(linker_cps)} entries x 3 bytes)")
    print(f"  incb_extend_packed: {len(extend_packed)} bytes ({len(incb_extend_ranges)} entries x 6 bytes)")
    print(f"  Output: {OUTPUT_FILE}")

    return 0


if __name__ == "__main__":
    sys.exit(main())

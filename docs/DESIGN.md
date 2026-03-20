English | [日本語](DESIGN-ja.md)

# grapheme Design

## Purpose

Provide Unicode grapheme cluster level string operations in MoonBit.

## Architecture

### GraphemeView

Holds the original String and an array of grapheme cluster boundary offsets.
Access to each cluster is returned as a StringView (zero-copy slice).

```
GraphemeView {
  source: String              // original string (owned)
  boundaries: Array[Int]      // UTF-16 offsets of grapheme cluster boundaries
  cluster_start: Int          // index into boundaries for the first cluster (inclusive)
  cluster_end: Int            // index into boundaries for the end cluster (exclusive)
}
// Invariants:
//   Empty string: boundaries == [], cluster_start == 0, cluster_end == 0
//   Non-empty string: boundaries[0] == 0, boundaries[last] == source.length()
//   length() == cluster_end - cluster_start
//   op_get(i) slices from boundaries[cluster_start + i]..boundaries[cluster_start + i + 1]
//   Slicing via op_as_view adjusts cluster_start/cluster_end without copying boundaries
```

### UAX #29 Implementation Strategy

1. `Grapheme_Cluster_Break` property table -- generated from Unicode 17.0.0 `GraphemeBreakProperty.txt`
2. `Extended_Pictographic` property -- generated from `emoji-data.txt`
3. Table generation -- Python or Rust script auto-generates `.mbt` files
4. State machine -- implements UAX #29 GB rules as a state transition table

### Three Layers of Unicode Problems and This Library's Position

| Layer | Problem | Solution |
|-------|---------|----------|
| L1: UTF-16 encoding | `str[i]` operates at code unit level | MoonBit core's `iter()` / `char_length()` |
| **L2: Grapheme cluster** | Composite emoji span multiple code points | **This library** |
| L3: Display width | Full-width / half-width display widths | `rami3l/unicodewidth` |

### Implementation Status

- **All UAX #29 GB rules implemented** -- table generation, state machine, all 766 official test cases passing.
- **Performance optimization** -- Two-stage lookup table implemented (O(1) constant time). ASCII fast path removed as it became unnecessary with O(1) table lookup.
- **API** -- `graphemes()`, `grapheme_iter()` (lazy), slice (`op_as_view`), reverse iteration (`rev_iter`), `iter2`, `grapheme_indices`, `Show`/`Eq`/`Hash` traits, `get`/`is_empty`/`to_string`.

---

## Detailed Design

### 1. Architecture

#### File Structure

```
src/
  lib.mbt              # GraphemeView struct, graphemes(), grapheme_iter(), public API
  gcb.mbt              # GCBCategory enum definition, gcb_category() lookup function
  gcb_table.mbt        # Auto-generated: GCB two-stage lookup table (gcb_stage1, gcb_stage2)
  segmenter.mbt        # SegmenterState, check_boundary(): pair rules + state tracking
  lib_wbtest.mbt       # White-box tests (existing + additions)
  gcb_wbtest.mbt       # White-box tests: gcb_category() tests
  segmenter_wbtest.mbt # White-box tests: check_boundary() individual GB rule tests
  uax29_test.mbt       # Black-box tests: all 766 official test cases
  lib_wbbench.mbt      # Benchmarks
tools/
  gen_gcb_table.py     # Table generation script
  gen_uax29_tests.py   # Test code generation from official test data
  data/                # Unicode data files (not tracked by git, auto-downloaded by scripts)
```

#### GCB Category Enum

16 categories integrating UAX #29 `Grapheme_Cluster_Break` property values with additional categories required for segmentation:

```moonbit
enum GCBCategory {
  Other             // none of the above
  CR
  LF
  Control
  Extend
  ZWJ
  Regional_Indicator
  Prepend
  SpacingMark
  L                 // Hangul Leading Jamo
  V                 // Hangul Vowel Jamo
  T                 // Hangul Trailing Jamo
  LV                // Hangul LV Syllable
  LVT               // Hangul LVT Syllable
  Extended_Pictographic  // GCB=Other and Extended_Pictographic=Yes -> merged
  InCB_Consonant    // InCB=Consonant -> merged
}
```

Design rationale: Extended_Pictographic and InCB_Consonant are merged as independent categories into GCB.
This allows a single gcb_category() lookup to obtain the information needed for GB11/GB9c,
eliminating the need for a second lookup into a separate table. Rust unicode-segmentation uses the same approach.

#### Table Design

A two-stage lookup table (4-bit packed) is used, providing O(1) constant time category lookup.

- **Stage1:** 4,352 bytes (`cp >> 8` yields block index)
- **Stage2:** 14,208 bytes (111 unique blocks x 128 bytes, 4-bit packed)
- **Total:** 18,560 bytes (18.1 KB)
- **Deduplication rate:** 97.4% (111 unique out of 4,352 blocks)

```moonbit
// Two-stage table lookup
// Stage1: cp >> 8 -> block index
// Stage2: block_idx * 128 + (cp & 0xFF) >> 1 -> 4-bit nibble extraction
let gcb_stage1 : Bytes = b"..."  // 4,352 bytes
let gcb_stage2 : Bytes = b"..."  // 14,208 bytes (4-bit packed)
```

Code points not present in the table (nibble value 0) return `Other`.

Design rationale: The initial implementation used sorted range arrays + binary search (O(log n), ~1,200 entries).
Migration to a two-stage table achieved O(1) constant time lookup. The table size is a compact 18.5 KB,
with 97.4% block deduplication providing good space efficiency.

#### InCB Auxiliary Tables

GB9c evaluation additionally requires InCB=Linker and InCB=Extend information.
These are maintained in separate small tables (tens of entries).

```moonbit
// InCB=Linker code points (3 bytes/entry, big-endian, binary search)
let incb_linker_packed : Bytes = b"..."

// InCB=Extend code point/ranges (6 bytes/entry: start 3B + end 3B, big-endian)
let incb_extend_packed : Bytes = b"..."
```

Design rationale: InCB_Consonant has high occurrence frequency and is worth merging into the main table.
On the other hand, InCB_Linker/Extend are only referenced during GB9c backward scanning,
so they are separated as auxiliary tables to avoid polluting the main GCB categories.

#### Segmentation Algorithm

The `graphemes()` function determines boundaries by forward-scanning code points with pair rule evaluation + state tracking.

```
Initialization:
  boundaries = []                -- start empty
  prev_gcb: none (first code point is unconditionally a boundary)
  ri_count: 0
  emoji_state: ES_None
  incb_state: IC_None

For each code point:
  1. Get category via gcb_category()
  2. If first code point (GB1: sot / Any), or
     check_boundary(prev_gcb, cur_gcb, state) is true:
     -> add current UTF-16 offset to boundaries
  3. Update state (prev_gcb, ri_count, emoji_state, incb_state)
  4. Advance UTF-16 offset (BMP: +1, surrogate pair: +2)

After loop:
  If boundaries is not empty (= string is non-empty):
    add end-of-string offset (= source.length()) to boundaries (GB2: Any / eot)

Invariants:
  Empty string -> boundaries == [], length() == 0
  Non-empty string -> boundaries[0] == 0, boundaries[last] == source.length()
  length() == max(0, boundaries.length() - 1)
  op_get(i) can safely slice at boundaries[i]..boundaries[i+1]
```

### 2. Table Generation

#### Generation Script `tools/gen_gcb_table.py`

**Input data:**
- `GraphemeBreakProperty.txt` (Unicode 17.0.0) -- GCB properties
- `emoji-data.txt` (Unicode 17.0.0) -- Extended_Pictographic property
- `DerivedCoreProperties.txt` (Unicode 17.0.0) -- InCB properties

**Processing:**
1. Parse each data file and build code point -> property mappings
2. Merge by GCB category priority:
   - Explicit GCB value -> that category (Control, Prepend, SpacingMark, etc. are never overwritten)
   - No GCB (= Other equivalent) + Extended_Pictographic=Yes -> `Extended_Pictographic`
   - No GCB (= Other equivalent) + InCB=Consonant -> `InCB_Consonant`
   - **Safety check:** If a code point with GCB != Other is also assigned InCB=Consonant, the generation script outputs a warning and prioritizes the GCB category. This prevents breaking GB4/5/9a/9b evaluation.
   - **Note:** In Unicode 17.0.0, there are 0 overlaps between InCB=Consonant and GCB!=Other (Rust unicode-segmentation uses the same approach). If collisions occur in future Unicode versions, moving InCB_Consonant to an auxiliary table will be considered.
3. Merge adjacent ranges with the same category
4. Sort by code point ascending

**Output:** `src/gcb_table.mbt`
- `gcb_stage1` / `gcb_stage2`: two-stage lookup table (4-bit packed)
- `incb_linker_packed`: InCB=Linker code point table (3-byte packed)
- `incb_extend_packed`: InCB=Extend range table (6-byte packed)

**Data file retrieval:**
The script auto-downloads to the `tools/data/` directory (if not present).
`tools/data/` is added to `.gitignore`.

#### Generation Script `tools/gen_uax29_tests.py`

**Input:** `GraphemeBreakTest.txt` (Unicode 17.0.0)
**Output:** `src/uax29_test.mbt` -- 766 test functions

Parses the `÷` (boundary) / `×` (no boundary) notation from the test data,
outputting each line as a `test "UAX29/NNN: ..."` format.

### 3. Property Lookup

```moonbit
/// Returns the GCB category for a code point.
/// Returns Other for code points not in the table.
fn gcb_category(cp : Int) -> GCBCategory {
  // Two-stage table lookup (O(1) constant time)
  // stage1[cp >> 8] -> block index
  // stage2[block_idx * 128 + (cp & 0xFF) >> 1] -> 4-bit nibble extraction
  // Nibble value 0 is Other
}

/// Returns whether a code point is InCB=Linker.
fn is_incb_linker(cp : Int) -> Bool {
  // Binary search on incb_linker_packed (3-byte packed)
}

/// Returns whether a code point is InCB=Extend.
fn is_incb_extend(cp : Int) -> Bool {
  // Binary search on incb_extend_packed (6-byte packed)
}
```

### 4. Segmentation Implementation

#### State Types

```moonbit
enum EmojiState {
  ES_None
  ES_EP_Seen           // Seen Extended_Pictographic
  ES_EP_Extend_ZWJ     // Seen Extend* ZWJ after EP
}

enum InCBState {
  IC_None
  IC_Consonant_Seen           // Seen InCB_Consonant
  IC_Consonant_Linker_Seen    // Seen [Extend|Linker]* Linker after Consonant
}
```

#### Pair Rule Evaluation `check_boundary()`

```moonbit
/// Determines grapheme cluster boundary from prev and cur pair.
/// true = boundary (÷), false = no boundary (×)
fn check_boundary(
  prev : GCBCategory,
  cur : GCBCategory,
  ri_count : Int,
  emoji_state : EmojiState,
  incb_state : InCBState,
) -> Bool {
  // GB3: CR × LF
  if prev == CR && cur == LF { return false }
  // GB4: (Control|CR|LF) ÷
  if prev == Control || prev == CR || prev == LF { return true }
  // GB5: ÷ (Control|CR|LF)
  if cur == Control || cur == CR || cur == LF { return true }
  // GB6: L × (L|V|LV|LVT)
  if prev == L && (cur == L || cur == V || cur == LV || cur == LVT) { return false }
  // GB7: (LV|V) × (V|T)
  if (prev == LV || prev == V) && (cur == V || cur == T) { return false }
  // GB8: (LVT|T) × T
  if (prev == LVT || prev == T) && cur == T { return false }
  // GB9: × (Extend|ZWJ)
  if cur == Extend || cur == ZWJ { return false }
  // GB9a: × SpacingMark
  if cur == SpacingMark { return false }
  // GB9b: Prepend ×
  if prev == Prepend { return false }
  // GB9c: \p{InCB=Consonant} [\p{InCB=Extend}\p{InCB=Linker}]* \p{InCB=Linker} [\p{InCB=Extend}\p{InCB=Linker}]* × \p{InCB=Consonant}
  if incb_state == IC_Consonant_Linker_Seen && cur == InCB_Consonant { return false }
  // GB11: \p{Extended_Pictographic} Extend* ZWJ × \p{Extended_Pictographic}
  if emoji_state == ES_EP_Extend_ZWJ && cur == Extended_Pictographic { return false }
  // GB12/13: sot (RI RI)* RI × RI / [^RI] (RI RI)* RI × RI
  if prev == Regional_Indicator && cur == Regional_Indicator && ri_count % 2 == 1 { return false }
  // GB999: Any ÷ Any
  true
}
```

#### State Update Logic

State is updated after processing each code point:

```
ri_count:
  cur == Regional_Indicator -> ri_count + 1
  otherwise -> 0

emoji_state:
  cur == Extended_Pictographic -> ES_EP_Seen
  emoji_state == ES_EP_Seen && cur == Extend -> ES_EP_Seen (maintain)
  emoji_state == ES_EP_Seen && cur == ZWJ -> ES_EP_Extend_ZWJ
  GB11 matched (ES_EP_Extend_ZWJ && cur == EP) -> ES_EP_Seen (start of new EP sequence)
  otherwise -> ES_None

incb_state:
  cur == InCB_Consonant -> IC_Consonant_Seen
  incb_state != IC_None && is_incb_extend(cp) -> maintain
  incb_state != IC_None && is_incb_linker(cp) -> IC_Consonant_Linker_Seen
  GB9c matched (IC_Consonant_Linker_Seen && cur == InCB_Consonant) -> IC_Consonant_Seen
  otherwise -> IC_None
```

Note: Because GB9 prevents Extend/ZWJ from creating boundaries, emoji_state and incb_state
are maintained across Extend/ZWJ. This is naturally achieved by the combination of
rule evaluation order (GB9 precedes GB9c/GB11) and state updates.

#### graphemes() Implementation

`graphemes()` determines boundaries using the state machine described above.
Public API (GraphemeView, length, op_get, iter) remains unchanged.

### 5. Test Strategy

#### 5.1 All Official Test Data (auto-generated)

`tools/gen_uax29_tests.py` outputs all 766 cases from `GraphemeBreakTest.txt`
to `src/uax29_test.mbt`. Each test verifies grapheme cluster boundary positions.

```moonbit
// Example: ÷ 0020 ÷ 0020 ÷  ->  split into " " and " "
test "UAX29/001: ÷ [0.2] SPACE ÷ [999.0] SPACE ÷ [0.3]" {
  let g = @lib.graphemes("\u{0020}\u{0020}")
  inspect!(g.length(), content="2")
  inspect!(g[0].to_string(), content="\u{0020}")
  inspect!(g[1].to_string(), content="\u{0020}")
}
```

#### 5.2 Individual GB Rule Tests (hand-written)

Hand-written tests in `src/segmenter_wbtest.mbt` that target each GB rule individually.
Complements edge cases not covered by official tests.

| Rule | Test Content |
|------|-------------|
| GB3 | CR+LF forms 1 cluster |
| GB4/5 | Split around Control |
| GB6-8 | Hangul syllable joining |
| GB9 | Extend/ZWJ joins to preceding cluster |
| GB9a | SpacingMark joins to preceding cluster |
| GB9b | Prepend joins to following cluster |
| GB9c | Indic consonant conjunct (Consonant + Linker + Consonant) |
| GB11 | Emoji ZWJ sequence (e.g., family emoji) |
| GB12/13 | Flag sequence (1 flag = 1 cluster, 2 flags = 2 clusters) |

#### 5.3 Real-world Text Tests (hand-written)

Added to `src/lib_wbtest.mbt`. Tests with strings users actually encounter.

- Family emoji: "👨‍👩‍👧‍👦" -> 1 grapheme cluster
- Flags: "🇯🇵" -> 1 cluster, "🇯🇵🇺🇸" -> 2 clusters
- Combining characters: "が" (U+304B U+3099) -> 1 cluster
- Mixed text+emoji: "Hello🌍World"
- Empty string: "" -> 0 clusters

#### 5.4 gcb_category() Tests (hand-written)

Representative code point category tests in `src/gcb_wbtest.mbt`.

- ASCII: 0x41('A') -> Other, 0x0A(LF) -> LF, 0x0D(CR) -> CR
- Extend: 0x0300(COMBINING GRAVE ACCENT) -> Extend
- RI: 0x1F1E6(REGIONAL INDICATOR SYMBOL LETTER A) -> Regional_Indicator
- EP: 0x1F600(GRINNING FACE) -> Extended_Pictographic
- Hangul: 0x1100 -> L, 0x1161 -> V, 0x11A8 -> T

### 6. Rejected Alternatives and Rationale

#### Why Not Use moonbit-community/unicode_data

`moonbit-community/unicode_data` provides basic properties like General_Category, but
does not provide all 13 `Grapheme_Cluster_Break` categories.
It also lacks segmentation-specific properties like Extended_Pictographic and InCB.
This library requires custom merged categories (16 types), so we generate our own tables.

#### Why Not Use Compressed Bitsets

Bitsets are suitable for boolean "has property or not" checks, but
this library needs to return values from 16 categories.
While one could use a bitset per category, a two-stage lookup table is
simpler to implement and debug.

### 7. Development History

Implemented in the following order using TDD (test-first):

1. GCBCategory enum definition (16 types)
2. Table generation script (`gen_gcb_table.py`) -> `gcb_table.mbt` generation
3. `gcb_category()` binary search implementation
4. `check_boundary()` pair rule implementation (GB3 -> GB4/5 -> GB6-8 -> GB9/9a/9b -> GB999)
5. Replaced `graphemes()` with state machine-based implementation
6. GB12/13 (Regional Indicator) even/odd counting via ri_count
7. GB11 (Emoji ZWJ Sequence) state tracking via emoji_state
8. GB9c (InCB Conjunct) incb_state + auxiliary tables
9. All 766 official test cases passing (`gen_uax29_tests.py`)
10. Additional APIs (slice, reverse iteration, lazy iterator, etc.)
11. GCB table migrated to two-stage lookup table (O(log n) -> O(1), ASCII fast path eliminated)

## References

- [UAX #29: Unicode Text Segmentation](https://unicode.org/reports/tr29/)
- [Rust unicode-segmentation](https://github.com/unicode-rs/unicode-segmentation)
- [moonbit-community/unicode_data](https://github.com/moonbit-community/unicode_data)
- [rami3l/unicodewidth](https://github.com/moonbit-community/unicodewidth.mbt)

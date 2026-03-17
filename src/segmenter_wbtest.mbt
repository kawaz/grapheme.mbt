// check_boundary() の個別 GB ルールテスト
// 状態依存パラメータはデフォルト値（ri_count=0, ES_None, IC_None）で呼ぶ

// GB3: CR × LF
test "check_boundary: GB3 CR×LF" {
  inspect(check_boundary(CR, LF, 0, ES_None, IC_None), content="false")
}

// GB4: (Control|CR|LF) ÷
test "check_boundary: GB4 Control÷Any" {
  inspect(check_boundary(Control, Other, 0, ES_None, IC_None), content="true")
}

test "check_boundary: GB4 CR÷Any(not LF)" {
  inspect(check_boundary(CR, Other, 0, ES_None, IC_None), content="true")
}

// GB5: ÷ (Control|CR|LF)
test "check_boundary: GB5 Any÷Control" {
  inspect(check_boundary(Other, Control, 0, ES_None, IC_None), content="true")
}

// GB6: L × (L|V|LV|LVT)
test "check_boundary: GB6 L×L" {
  inspect(check_boundary(L, L, 0, ES_None, IC_None), content="false")
}

test "check_boundary: GB6 L×V" {
  inspect(check_boundary(L, V, 0, ES_None, IC_None), content="false")
}

test "check_boundary: GB6 L×LV" {
  inspect(check_boundary(L, LV, 0, ES_None, IC_None), content="false")
}

test "check_boundary: GB6 L×LVT" {
  inspect(check_boundary(L, LVT, 0, ES_None, IC_None), content="false")
}

// GB7: (LV|V) × (V|T)
test "check_boundary: GB7 LV×V" {
  inspect(check_boundary(LV, V, 0, ES_None, IC_None), content="false")
}

test "check_boundary: GB7 V×T" {
  inspect(check_boundary(V, T, 0, ES_None, IC_None), content="false")
}

// GB8: (LVT|T) × T
test "check_boundary: GB8 LVT×T" {
  inspect(check_boundary(LVT, T, 0, ES_None, IC_None), content="false")
}

test "check_boundary: GB8 T×T" {
  inspect(check_boundary(T, T, 0, ES_None, IC_None), content="false")
}

// GB9: × (Extend|ZWJ)
test "check_boundary: GB9 Any×Extend" {
  inspect(check_boundary(Other, Extend, 0, ES_None, IC_None), content="false")
}

test "check_boundary: GB9 Any×ZWJ" {
  inspect(check_boundary(Other, ZWJ, 0, ES_None, IC_None), content="false")
}

// GB9a: × SpacingMark
test "check_boundary: GB9a Any×SpacingMark" {
  inspect(
    check_boundary(Other, SpacingMark, 0, ES_None, IC_None),
    content="false",
  )
}

// GB9b: Prepend ×
test "check_boundary: GB9b Prepend×Any" {
  inspect(check_boundary(Prepend, Other, 0, ES_None, IC_None), content="false")
}

// GB999: Any ÷ Any
test "check_boundary: GB999 Other÷Other" {
  inspect(check_boundary(Other, Other, 0, ES_None, IC_None), content="true")
}

// --- 状態依存ルールのテスト ---

// GB9c: InCB Consonant + [Extend|Linker]* Linker [Extend|Linker]* × InCB_Consonant
test "check_boundary: GB9c Consonant_Linker_Seen × InCB_Consonant" {
  inspect(
    check_boundary(Extend, InCB_Consonant, 0, ES_None, IC_Consonant_Linker_Seen),
    content="false",
  )
}

test "check_boundary: GB9c without linker → boundary" {
  inspect(
    check_boundary(Extend, InCB_Consonant, 0, ES_None, IC_Consonant_Seen),
    content="true",
  )
}

// GB11: Extended_Pictographic Extend* ZWJ × Extended_Pictographic
test "check_boundary: GB11 EP_Extend_ZWJ × EP" {
  inspect(
    check_boundary(ZWJ, Extended_Pictographic, 0, ES_EP_Extend_ZWJ, IC_None),
    content="false",
  )
}

test "check_boundary: GB11 without EP state → boundary" {
  inspect(
    check_boundary(ZWJ, Extended_Pictographic, 0, ES_None, IC_None),
    content="true",
  )
}

// GB12/13: RI × RI (odd count → no break, even count → break)
test "check_boundary: GB12/13 RI×RI odd count → no break" {
  inspect(
    check_boundary(Regional_Indicator, Regional_Indicator, 1, ES_None, IC_None),
    content="false",
  )
}

test "check_boundary: GB12/13 RI×RI even count → break" {
  inspect(
    check_boundary(Regional_Indicator, Regional_Indicator, 2, ES_None, IC_None),
    content="true",
  )
}

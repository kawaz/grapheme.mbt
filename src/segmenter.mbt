///|
/// 絵文字 ZWJ シーケンス（GB11）の状態追跡。
priv enum EmojiState {
  ES_None
  ES_EP_Seen // Extended_Pictographic を見た
  ES_EP_Extend_ZWJ // EP の後に Extend* ZWJ を見た
} derive(Eq, Show)

///|
/// InCB Conjunct（GB9c）の状態追跡。
priv enum InCBState {
  IC_None
  IC_Consonant_Seen // InCB_Consonant を見た
  IC_Consonant_Linker_Seen // Consonant の後に [Extend|Linker]* Linker を見た
} derive(Eq, Show)

///|
/// prev と cur のペアで grapheme cluster 境界を判定する。
/// true = 境界あり（÷）、false = 境界なし（×）
fn check_boundary(
  prev : GCBCategory,
  cur : GCBCategory,
  ri_count : Int,
  emoji_state : EmojiState,
  incb_state : InCBState,
) -> Bool {
  // GB3: CR × LF
  if prev == CR && cur == LF {
    return false
  }
  // GB4: (Control|CR|LF) ÷
  if prev == Control || prev == CR || prev == LF {
    return true
  }
  // GB5: ÷ (Control|CR|LF)
  if cur == Control || cur == CR || cur == LF {
    return true
  }
  // GB6: L × (L|V|LV|LVT)
  if prev == L && (cur == L || cur == V || cur == LV || cur == LVT) {
    return false
  }
  // GB7: (LV|V) × (V|T)
  if (prev == LV || prev == V) && (cur == V || cur == T) {
    return false
  }
  // GB8: (LVT|T) × T
  if (prev == LVT || prev == T) && cur == T {
    return false
  }
  // GB9: × (Extend|ZWJ)
  if cur == Extend || cur == ZWJ {
    return false
  }
  // GB9a: × SpacingMark
  if cur == SpacingMark {
    return false
  }
  // GB9b: Prepend ×
  if prev == Prepend {
    return false
  }
  // GB9c: \p{InCB=Consonant} [\p{InCB=Extend}\p{InCB=Linker}]* \p{InCB=Linker}
  //       [\p{InCB=Extend}\p{InCB=Linker}]* × \p{InCB=Consonant}
  if incb_state == IC_Consonant_Linker_Seen && cur == InCB_Consonant {
    return false
  }
  // GB11: \p{Extended_Pictographic} Extend* ZWJ × \p{Extended_Pictographic}
  if emoji_state == ES_EP_Extend_ZWJ && cur == Extended_Pictographic {
    return false
  }
  // GB12/13: sot (RI RI)* RI × RI / [^RI] (RI RI)* RI × RI
  if prev == Regional_Indicator &&
    cur == Regional_Indicator &&
    ri_count % 2 == 1 {
    return false
  }
  // GB999: Any ÷ Any
  true
}

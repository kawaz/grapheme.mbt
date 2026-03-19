///|
/// State tracking for emoji ZWJ sequences (GB11).
priv enum EmojiState {
  ES_None
  ES_EP_Seen // Seen Extended_Pictographic
  ES_EP_Extend_ZWJ // Seen Extend* ZWJ after EP
} derive(Eq)

///|
/// State tracking for InCB Conjunct (GB9c).
priv enum InCBState {
  IC_None
  IC_Consonant_Seen // Seen InCB_Consonant
  IC_Consonant_Linker_Seen // Seen [Extend|Linker]* Linker after Consonant
} derive(Eq)

///|
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

///|
/// State transition for emoji ZWJ sequences.
fn next_emoji_state(state : EmojiState, cur_gcb : GCBCategory) -> EmojiState {
  if cur_gcb == Extended_Pictographic {
    ES_EP_Seen
  } else if state == ES_EP_Seen && cur_gcb == Extend {
    ES_EP_Seen
  } else if state == ES_EP_Seen && cur_gcb == ZWJ {
    ES_EP_Extend_ZWJ
  } else {
    ES_None
  }
}

///|
/// State transition for InCB Conjunct.
fn next_incb_state(
  state : InCBState,
  cur_gcb : GCBCategory,
  cp : Int,
) -> InCBState {
  if cur_gcb == InCB_Consonant {
    IC_Consonant_Seen
  } else if state != IC_None && is_incb_linker(cp) {
    IC_Consonant_Linker_Seen
  } else if state != IC_None && is_incb_extend(cp) {
    state
  } else {
    IC_None
  }
}

///|
/// Encapsulates the UAX #29 grapheme segmentation state machine.
/// Both graphemes() and grapheme_iter() share this single implementation
/// to avoid state machine logic duplication.
priv struct SegmenterState {
  mut prev_gcb : GCBCategory?
  mut ri_count : Int
  mut emoji_state : EmojiState
  mut incb_state : InCBState
}

///|
fn SegmenterState::new() -> SegmenterState {
  { prev_gcb: None, ri_count: 0, emoji_state: ES_None, incb_state: IC_None }
}

///|
/// Feed a code point to the state machine.
/// Returns true if this code point starts a new grapheme cluster boundary.
fn SegmenterState::next(self : SegmenterState, cp : Int) -> Bool {
  let cur_gcb = gcb_category(cp)
  let is_boundary = match self.prev_gcb {
    None => true
    Some(prev) =>
      check_boundary(prev, cur_gcb, self.ri_count, self.emoji_state, self.incb_state)
  }
  self.ri_count = if cur_gcb == Regional_Indicator { self.ri_count + 1 } else { 0 }
  self.emoji_state = next_emoji_state(self.emoji_state, cur_gcb)
  self.incb_state = next_incb_state(self.incb_state, cur_gcb, cp)
  self.prev_gcb = Some(cur_gcb)
  is_boundary
}

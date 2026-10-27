/-
The normalised 64-bit sort-key prefix planned for qvm's sorter (cursed-http explore/pg-jit-study/REPORT.md §3.5,
"idea 5"), for a first key under BINARY collation:

  bits 63-62  the storage class: 0 NULL, 1 number, 2 TEXT, 3 BLOB (SQLite's order of classes)
  bits 61-0   numbers: (n + 2^63) >> 2, n the value's integer floor clamped to int64 (an integer is its own floor;
              -inf and +inf the ends); TEXT and BLOB: the first 7 bytes big-endian (zero-padded), times 8, plus
              min(length, 7); NULL: 0
  DESC        the bitwise complement

Proved: the prefix is monotone in SQLite's order, so a strict prefix order implies the full order, and comparing
prefixes first with the full KeyInfo compare on equal prefixes is *the same comparator* as the full compare (any sort,
stable or not, gives the same result). Equal prefixes of unequal values are characterised (`tie_text`, `tie_num`).
With an all-integer first key the exact mode (the biased i64, no class bits) has no ties between unequal values.
Not covered: NOCASE and other collations (the prefix is disabled for them), NULLS FIRST/LAST (BIGNULL) on the first
key (would need a different class map).
-/
import Turbo.FastPaths

namespace Turbo

/-! ## The order is antisymmetric (BINARY) -/

theorem dbl_cmp_swap (a b : Dbl) : (a.cmp b).swap = b.cmp a := by
  cases a <;> cases b <;> simp [Dbl.cmp, cmp3_rat_swap, cmp3_nat_swap]

theorem cmpIntDbl_swap_swap (i : Int) (r : Dbl) : ((cmpIntDbl i r).swap).swap = cmpIntDbl i r := by
  cases cmpIntDbl i r <;> rfl

theorem order_swap (a b : Val) : (order .binary a b).swap = order .binary b a := by
  cases a <;> cases b <;>
    simp [order, Val.cls, numCmp, Coll.cmp, memcmpLen_eq_lex, cmp3_int_swap, dbl_cmp_swap, lex_swap,
      Ordering.swap_swap]
  all_goals rfl

/-! ## Byte prefixes -/

/-- The first n bytes, zero-padded to n. -/
def pad : Nat → List UInt8 → List UInt8
  | 0, _ => []
  | n + 1, [] => 0 :: pad n []
  | n + 1, a :: as => a :: pad n as

/-- Big-endian value of a byte list. -/
def be : List UInt8 → Nat
  | [] => 0
  | a :: as => a.toNat * 256 ^ as.length + be as

theorem pad_length : ∀ n s, (pad n s).length = n
  | 0, _ => rfl
  | n + 1, [] => by simp [pad, pad_length n []]
  | n + 1, _ :: as => by simp [pad, pad_length n as]

theorem be_lt : ∀ p : List UInt8, be p < 256 ^ p.length
  | [] => by simp [be]
  | a :: as => by
    have h1 := be_lt as
    have h2 : a.toNat < 256 := UInt8.toNat_lt a
    simp only [be, List.length_cons, Nat.pow_succ]
    have : a.toNat * 256 ^ as.length + be as < (a.toNat + 1) * 256 ^ as.length := by
      rw [Nat.add_mul, Nat.one_mul]; omega
    have : (a.toNat + 1) * 256 ^ as.length ≤ 256 * 256 ^ as.length := Nat.mul_le_mul_right _ (by omega)
    rw [Nat.mul_comm (256 ^ as.length) 256]; omega

/-- The prefix code of a byte string: `(pad 7, min len 7)` packed. -/
def enc (n : Nat) (s : List UInt8) : Nat := be (pad n s) * 8 + min s.length 7

/-- Lexicographic order of (padded prefix, clipped length) follows the full order: the key fact, by induction. -/
theorem pad_mono : ∀ (n : Nat) (s t : List UInt8), lex s t ≠ .gt →
    be (pad n s) < be (pad n t) ∨ (be (pad n s) = be (pad n t) ∧ min s.length n ≤ min t.length n)
  | 0, s, t, _ => by simp [pad, be]
  | n + 1, [], [], _ => by simp
  | n + 1, [], b :: bs, _ => by
    have ih := pad_mono n [] bs (by cases bs <;> simp [lex])
    simp only [pad, be, pad_length]
    have hb := be_lt (pad n bs); rw [pad_length] at hb
    have z : (0 : UInt8).toNat = 0 := rfl
    by_cases h0 : b.toNat = 0
    · rw [h0]; simp only [z, Nat.zero_mul, Nat.zero_add]; rcases ih with h | ⟨h, _⟩
      · left; omega
      · right; simp at h ⊢; omega
    · left
      have : 256 ^ n ≤ b.toNat * 256 ^ n := Nat.le_mul_of_pos_left _ (by omega)
      have := be_lt (pad n []); rw [pad_length] at this
      simp; omega
  | n + 1, _ :: _, [], h => by simp [lex] at h
  | n + 1, a :: as, b :: bs, h => by
    simp only [lex] at h
    simp only [pad, be, pad_length, List.length_cons]
    have hs := be_lt (pad n as); rw [pad_length] at hs
    have ht := be_lt (pad n bs); rw [pad_length] at ht
    by_cases h1 : a < b
    · left
      have : a.toNat + 1 ≤ b.toNat := by have := UInt8.lt_iff_toNat_lt.mp h1; omega
      have : (a.toNat + 1) * 256 ^ n ≤ b.toNat * 256 ^ n := Nat.mul_le_mul_right _ this
      rw [Nat.add_mul, Nat.one_mul] at this; omega
    by_cases h2 : b < a
    · simp [h1, h2] at h
    have hab : a = b := UInt8.le_antisymm (UInt8.not_lt.mp h2) (UInt8.not_lt.mp h1)
    subst hab
    simp only [h1, ↓reduceIte] at h
    rcases pad_mono n as bs h with h' | ⟨h', hl⟩
    · left; omega
    · right; refine ⟨by omega, ?_⟩; omega

theorem enc_mono (s t : List UInt8) (h : lex s t ≠ .gt) : enc 7 s ≤ enc 7 t := by
  unfold enc
  rcases pad_mono 7 s t h with h' | ⟨h', hl⟩
  · have : min s.length 7 ≤ 7 := Nat.min_le_right _ _
    omega
  · omega

theorem enc_lt (s : List UInt8) : enc 7 s < 2 ^ 59 := by
  unfold enc
  have := be_lt (pad 7 s); rw [pad_length] at this
  have : min s.length 7 ≤ 7 := Nat.min_le_right _ _
  have : (256 : Nat) ^ 7 = 2 ^ 56 := by decide
  omega

/-! ## Numbers -/

def clamp (n : Int) : Int := max I64MIN (min I64MAX n)

/-- The integer a number's prefix is built from. -/
def numFloor : Val → Int
  | .int i => clamp i
  | .real .negInf => I64MIN
  | .real .posInf => I64MAX
  | .real (.fin q) => clamp q.floor
  | _ => 0

def numCode (v : Val) : Nat := ((numFloor v + 9223372036854775808) / 4).toNat

theorem clamp_mono {a b : Int} (h : a ≤ b) : clamp a ≤ clamp b := by
  unfold clamp; omega

theorem clamp_range (a : Int) : I64MIN ≤ clamp a ∧ clamp a ≤ I64MAX := by
  unfold clamp I64MIN I64MAX; omega

theorem numFloor_range (v : Val) (hv : v.isNum) : I64MIN ≤ numFloor v ∧ numFloor v ≤ I64MAX := by
  cases v <;> simp [Val.isNum] at hv
  · exact clamp_range _
  · rename_i r
    cases r with
    | fin q => exact clamp_range _
    | _ => simp [numFloor, I64MIN, I64MAX]

theorem numFloor_mono (F : Fmt) (a b : Val) (ha : a.WF F) (hb : b.WF F) (na : a.isNum) (nb : b.isNum)
    (h : order .binary a b ≠ .gt) : numFloor a ≤ numFloor b := by
  cases a <;> cases b <;> simp [Val.isNum] at na nb <;> simp [order, Val.cls, numCmp] at h
  · -- int, int
    rename_i x y; apply clamp_mono; unfold cmp3 at h; split at h <;> (try split at h) <;> simp_all <;> omega
  · -- int, real
    rename_i x r
    cases r with
    | negInf => simp [cmpIntDbl] at h
    | posInf => exact (clamp_range x).2
    | fin q =>
      simp [cmpIntDbl, cmp3] at h; apply clamp_mono
      by_cases hl : q < (x : Rat)
      · have : ¬ (x : Rat) < q := by grind
        simp [this, hl] at h
      · exact Rat.le_floor_iff.mpr (by grind)
  · -- real, int
    rename_i r y
    cases r with
    | negInf => exact (clamp_range y).1
    | posInf => simp [cmpIntDbl] at h
    | fin q =>
      simp [cmpIntDbl, cmp3] at h; apply clamp_mono
      have : q ≤ (y : Rat) := by grind
      have := Rat.floor_monotone this; simpa [Rat.floor_intCast] using this
  · -- real, real
    rename_i r s
    cases r <;> cases s <;> simp [Dbl.cmp, cmp3, Dbl.rank, numFloor, clamp_range] at h ⊢
    all_goals first
      | exact (clamp_range _).1
      | exact (clamp_range _).2
      | (unfold I64MIN I64MAX; omega)
      | (apply clamp_mono; apply Rat.floor_monotone; grind)

theorem numCode_lt (v : Val) (hv : v.isNum) : numCode v < 2 ^ 62 := by
  have := numFloor_range v hv; unfold numCode I64MIN I64MAX at *; omega

/-! ## The prefix -/

def Val.tag : Val → Nat
  | .null => 0
  | .int _ | .real _ => 1
  | .text _ => 2
  | .blob _ => 3

def payload : Val → Nat
  | .null => 0
  | .text s => enc 7 s
  | .blob s => enc 7 s
  | v => numCode v

/-- The ascending prefix (a 64-bit unsigned integer). -/
def key (v : Val) : Nat := v.tag * 2 ^ 62 + payload v

/-- DESC: the complement. -/
def keyDesc (v : Val) : Nat := 2 ^ 64 - 1 - key v

theorem payload_lt (v : Val) : payload v < 2 ^ 62 := by
  cases v with
  | null => simp [payload]
  | int i => exact numCode_lt _ rfl
  | real r => exact numCode_lt _ rfl
  | text s => have := enc_lt s; simp [payload]; omega
  | blob s => have := enc_lt s; simp [payload]; omega

theorem key_lt (v : Val) : key v < 2 ^ 64 := by
  have := payload_lt v
  have : v.tag ≤ 3 := by cases v <;> simp [Val.tag]
  unfold key; omega

/-- **The prefix is monotone**: a ≤ b in SQLite's order gives key a ≤ key b. -/
theorem key_mono (F : Fmt) (a b : Val) (ha : a.WF F) (hb : b.WF F) (h : order .binary a b ≠ .gt) :
    key a ≤ key b := by
  have pa := payload_lt a; have pb := payload_lt b
  by_cases hc : a.cls < b.cls
  · have : a.tag < b.tag := by cases a <;> cases b <;> simp_all [Val.cls, Val.tag]
    unfold key
    have : a.tag * 2 ^ 62 + 2 ^ 62 ≤ b.tag * 2 ^ 62 := by
      have := Nat.mul_le_mul_right (2 ^ 62) (show a.tag + 1 ≤ b.tag by omega)
      rw [Nat.add_mul, Nat.one_mul] at this; exact this
    omega
  by_cases hc' : b.cls < a.cls
  · exfalso; apply h; simp [order, hc, hc']
  cases a <;> cases b <;> simp_all [Val.cls]
  all_goals (unfold key; simp only [Val.tag, payload])
  all_goals first
    | omega
    | (have := numFloor_mono F _ _ ha hb rfl rfl h; unfold numCode; omega)
    | (have := enc_mono _ _ (by simpa [order, Val.cls, Coll.cmp, memcmpLen_eq_lex] using h); omega)
    | (have := enc_mono _ _ (by simpa [order, Val.cls] using h); omega)

/-- **A strict prefix order implies the full order.** -/
theorem key_lt_order (F : Fmt) (a b : Val) (ha : a.WF F) (hb : b.WF F) (h : key a < key b) :
    order .binary a b = .lt := by
  apply Classical.byContradiction; intro hne
  have : order .binary b a ≠ .gt := by
    rw [← order_swap]; intro h'; apply hne; cases ho : order .binary a b <;> simp_all [Ordering.swap]
  have := key_mono F b a hb ha this; omega

/-- The sorter's comparator with the prefix: prefixes first, the full compare only on equal prefixes. -/
def prefixCmp (full : Ordering) (ka kb : Nat) : Ordering :=
  if ka < kb then .lt else if kb < ka then .gt else full

/-- **The prefix comparator is the full comparator** (ascending first key; the rest of the key any KeyInfo): sorting
with it gives exactly the rows in the order SQLite's sorter gives. -/
theorem prefixCmp_asc (F : Fmt) (cs : List (Coll × SortFlags)) (a b : Val) (as bs : List Val)
    (ha : a.WF F) (hb : b.WF F) :
    prefixCmp (keySpec ((.binary, ⟨false, false⟩) :: cs) (a :: as) (b :: bs)) (key a) (key b)
      = keySpec ((.binary, ⟨false, false⟩) :: cs) (a :: as) (b :: bs) := by
  have fo : fieldOrder .binary ⟨false, false⟩ a b = order .binary a b := by
    unfold fieldOrder
    by_cases h1 : a.isNull && b.isNull
    · simp [h1]; cases a <;> cases b <;> simp_all [Val.isNull, order, Val.cls]
    · simp [h1]
  unfold prefixCmp
  split
  · rename_i h; simp [keySpec, fo, key_lt_order F a b ha hb h]
  split
  · rename_i _ h
    have := key_lt_order F b a hb ha h
    have : order .binary a b = .gt := by rw [← order_swap]; simp [this, Ordering.swap]
    simp [keySpec, fo, this]
  · rfl

/-- DESC first key: the complemented prefix. -/
theorem prefixCmp_desc (F : Fmt) (cs : List (Coll × SortFlags)) (a b : Val) (as bs : List Val)
    (ha : a.WF F) (hb : b.WF F) :
    prefixCmp (keySpec ((.binary, ⟨true, false⟩) :: cs) (a :: as) (b :: bs)) (keyDesc a) (keyDesc b)
      = keySpec ((.binary, ⟨true, false⟩) :: cs) (a :: as) (b :: bs) := by
  have fo : fieldOrder .binary ⟨true, false⟩ a b = (order .binary a b).swap := by
    unfold fieldOrder
    by_cases h1 : a.isNull && b.isNull
    · simp [h1]; cases a <;> cases b <;> simp_all [Val.isNull, order, Val.cls, Ordering.swap]
    · simp [h1]
  have la := key_lt a; have lb := key_lt b
  unfold prefixCmp keyDesc
  split
  · rename_i h
    have := key_lt_order F b a hb ha (by omega)
    rw [← order_swap] at this
    simp [keySpec, fo, this]
  split
  · rename_i _ h
    have := key_lt_order F a b ha hb (by omega)
    simp [keySpec, fo, this, Ordering.swap]
  · rfl

/-! ## When ties need the full compare -/

theorem pad_eq_take : ∀ (n : Nat) (s : List UInt8), n ≤ s.length → pad n s = s.take n
  | 0, _, _ => rfl
  | n + 1, [], h => by simp at h
  | n + 1, a :: as, h => by simp [pad, pad_eq_take n as (by simp at h; omega)]

theorem be_inj : ∀ p q : List UInt8, p.length = q.length → be p = be q → p = q
  | [], [], _, _ => rfl
  | a :: as, b :: bs, hl, h => by
    simp only [be, List.length_cons, Nat.add_right_cancel_iff] at hl h
    have ha := be_lt as; have hb := be_lt bs
    rw [hl] at ha h
    have h1 : a.toNat = b.toNat := by
      apply Classical.byContradiction; intro hne
      rcases Nat.lt_or_gt_of_ne hne with c | c
      · have := Nat.mul_le_mul_right (256 ^ bs.length) (show a.toNat + 1 ≤ b.toNat by omega)
        rw [Nat.add_mul, Nat.one_mul] at this; omega
      · have := Nat.mul_le_mul_right (256 ^ bs.length) (show b.toNat + 1 ≤ a.toNat by omega)
        rw [Nat.add_mul, Nat.one_mul] at this; omega
    have : a = b := UInt8.toNat_inj.mp h1
    subst this
    rw [be_inj as bs hl (by omega)]

theorem pad_short : ∀ (n : Nat) (s : List UInt8), s.length ≤ n → pad n s = s ++ List.replicate (n - s.length) 0
  | 0, s, h => by simp at h; simp [h, pad]
  | n + 1, [], _ => by
    simp [pad, pad_short n [] (by simp), List.replicate_succ]
  | n + 1, a :: as, h => by
    simp at h; simp [pad, pad_short n as (by omega)]

/-- **Text ties**: equal prefixes of two strings mean they are equal, or both are at least 7 bytes long and share
their first 7. Only then does the sorter need the full compare. The same holds for blobs. -/
theorem tie_text (s t : List UInt8) (h : enc 7 s = enc 7 t) :
    s = t ∨ (7 ≤ s.length ∧ 7 ≤ t.length ∧ s.take 7 = t.take 7) := by
  unfold enc at h
  have hs : min s.length 7 ≤ 7 := Nat.min_le_right _ _
  have ht : min t.length 7 ≤ 7 := Nat.min_le_right _ _
  have hp : be (pad 7 s) = be (pad 7 t) := by omega
  have hm : min s.length 7 = min t.length 7 := by omega
  have pe := be_inj _ _ (by simp [pad_length]) hp
  by_cases ls : 7 ≤ s.length
  · have lt' : 7 ≤ t.length := by omega
    right; refine ⟨ls, lt', ?_⟩
    rw [← pad_eq_take 7 s ls, ← pad_eq_take 7 t lt', pe]
  · left
    have lens : s.length = t.length := by omega
    rw [pad_short 7 s (by omega), pad_short 7 t (by omega), lens] at pe
    exact List.append_cancel_right pe

/-- **Number ties**: equal prefixes of two numbers mean their (clamped) floors agree after the 2-bit shift: integers
in the same aligned block of 4, a real and the integers around its floor, anything beyond int64 at the same end. -/
theorem tie_num (a b : Val) (ha : a.isNum) (hb : b.isNum) (h : key a = key b) :
    (numFloor a + 9223372036854775808) / 4 = (numFloor b + 9223372036854775808) / 4 := by
  have ra := numFloor_range a ha; have rb := numFloor_range b hb
  cases a <;> cases b <;> simp [Val.isNum] at ha hb <;>
    simp only [key, Val.tag, payload, numCode] at h <;> unfold I64MIN I64MAX at * <;> omega

/-! ## Exact mode: an all-integer first key -/

/-- The biased integer, the whole 64 bits. -/
def keyInt (i : Int) : Nat := (i + 9223372036854775808).toNat

/-- **Exact mode is exact**: on int64s the biased key orders as the integers and ties only equal integers, so equal
prefixes go straight to the later key fields. -/
theorem keyInt_exact (i j : Int) (hi : InI64 i) (hj : InI64 j) :
    (keyInt i < keyInt j ↔ i < j) ∧ (keyInt i = keyInt j ↔ i = j) ∧ keyInt i < 2 ^ 64 := by
  unfold keyInt InI64 at *; omega

theorem exact_mode (cs : List (Coll × SortFlags)) (i j : Int) (as bs : List Val) (hi : InI64 i) (hj : InI64 j) :
    prefixCmp (keySpec cs as bs) (keyInt i) (keyInt j)
      = keySpec ((.binary, ⟨false, false⟩) :: cs) (.int i :: as) (.int j :: bs) := by
  have := keyInt_exact i j hi hj
  unfold prefixCmp
  simp only [keySpec, fieldOrder, Val.isNull, Bool.and_false, Bool.false_or,
    Bool.false_eq_true, order, Val.cls, Nat.lt_irrefl, ↓reduceIte, numCmp, cmp3]
  by_cases h1 : i < j
  · simp [h1, this.1.mpr h1]
  by_cases h2 : j < i
  · have : keyInt j < keyInt i := (keyInt_exact j i hj hi).1.mpr h2
    simp [h1, h2, this, show ¬ keyInt i < keyInt j by omega]
  have : i = j := by omega
  subst this; simp

end Turbo

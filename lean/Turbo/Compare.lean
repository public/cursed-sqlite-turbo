/-
sqlite3MemCompare and sqlite3IntFloatCompare against the documented order.
-/
import Turbo.Value

namespace Turbo

/-- A toy format satisfying `Fmt`'s hypotheses: the assumptions are consistent. -/
def Fmt.toy : Fmt where
  isD q := -9007199254740992 < q ∧ q < 9007199254740992
  big_int := by intro q h1 h2; grind
  i2d i := if -9007199254740992 ≤ i ∧ i ≤ 9007199254740992 then .fin i else .fin 0
  exact_small := by intro i h1 h2; simp [h1, h2]
  exact_repr := by
    intro i ⟨h1, h2⟩
    have a : -9007199254740992 < i := by
      have : ((-9007199254740992 : Int) : Rat) < (i : Rat) := by simpa using h1
      exact Rat.intCast_lt_intCast.mp this
    have b : i < 9007199254740992 := by
      have : (i : Rat) < ((9007199254740992 : Int) : Rat) := by simpa using h2
      exact Rat.intCast_lt_intCast.mp this
    simp; omega

theorem cmp3_lt {α} [LT α] [DecidableRel (α := α) (· < ·)] {a b : α} (h : a < b) : cmp3 a b = .lt := by
  simp [cmp3, h]

theorem cmp3_gt {α} [LT α] [DecidableRel (α := α) (· < ·)] {a b : α} (h : b < a) (h' : ¬ a < b) :
    cmp3 a b = .gt := by
  simp [cmp3, h, h']

theorem cmp3_rat_swap (a b : Rat) : (cmp3 a b).swap = cmp3 b a := by
  unfold cmp3
  by_cases h1 : a < b <;> by_cases h2 : b < a <;> simp [h1, h2, Ordering.swap] <;> grind

theorem cmp3_int_swap (a b : Int) : (cmp3 a b).swap = cmp3 b a := by
  unfold cmp3
  by_cases h1 : a < b <;> by_cases h2 : b < a <;> simp [h1, h2, Ordering.swap] <;> omega

theorem cmp3_nat_swap (a b : Nat) : (cmp3 a b).swap = cmp3 b a := by
  unfold cmp3
  by_cases h1 : a < b <;> by_cases h2 : b < a <;> simp [h1, h2, Ordering.swap] <;> omega

theorem cmp3_rat_eq (a : Rat) : cmp3 a a = .eq := by simp [cmp3, Rat.lt_irrefl]

private theorem cast_le {a b : Int} : ((a : Rat) ≤ (b : Rat)) ↔ a ≤ b := Rat.intCast_le_intCast
private theorem cast_lt {a b : Int} : ((a : Rat) < (b : Rat)) ↔ a < b := Rat.intCast_lt_intCast

/-- **sqlite3IntFloatCompare is exact.** For a 64-bit integer and a non-NaN double, the C algorithm (range checks,
truncation `(i64)r`, then `(double)i` against r) returns the sign of the exact comparison i - r, in every rounding
mode, including beyond 2^53 where `(double)i` rounds. -/
theorem intFloatCompare_exact (F : Fmt) (i : Int) (r : Dbl) (hi : InI64 i) (hr : r.Valid F) :
    sgn (intFloatCompareC F i r) = cmpIntDbl i r := by
  obtain ⟨hlo, hhi⟩ := hi
  cases r with
  | negInf => simp [intFloatCompareC, cmpIntDbl, sgn]
  | posInf => simp [intFloatCompareC, cmpIntDbl, sgn]
  | fin q =>
    simp only [Dbl.Valid] at hr
    have ilo : (-9223372036854775808 : Rat) ≤ (i : Rat) := by
      have := (cast_le (a := -9223372036854775808) (b := i)).mpr hlo; simpa using this
    have ihi : (i : Rat) < 9223372036854775808 := by
      have := (cast_lt (a := i) (b := 9223372036854775808)).mpr hhi; simpa using this
    simp only [intFloatCompareC, cmpIntDbl]
    by_cases h1 : q < -9223372036854775808
    · simp only [h1, ↓reduceIte, sgn]
      have : q < (i : Rat) := by grind
      have : ¬ (i : Rat) < q := by grind
      simp [cmp3, *]
    by_cases h2 : 9223372036854775808 ≤ q
    · simp only [h1, h2, ↓reduceIte, sgn]
      have : (i : Rat) < q := by grind
      simp [cmp3, *]
    simp only [h1, h2, ↓reduceIte]
    -- y = (i64)q, truncation toward zero
    by_cases hq : 0 ≤ q
    · simp only [hq, ↓reduceIte]
      by_cases a : i < q.floor
      · have : (i : Rat) < q := by
          have := (cast_lt).mpr a; have := Rat.floor_le q; grind
        simp [a, sgn, cmp3, this]
      by_cases b : q.floor < i
      · have : q < (i : Rat) := by
          have : q.floor + 1 ≤ i := by omega
          have h := (cast_le).mpr this; have := Rat.lt_floor_add_one q; grind
        have : ¬ (i : Rat) < q := by grind
        simp [sgn, cmp3, *]
      have hy : q.floor = i := by omega
      simp only [a, b, ↓reduceIte]
      by_cases big : 9007199254740992 ≤ q
      · have hint := F.big_int q hr (Or.inr big)
        have hqi : q = (i : Rat) := by rw [← hint, hy]
        rw [F.exact_repr i (hqi ▸ hr), hqi]
        simp [Dbl.cmp, cmp3_rat_eq, sgn]
      · have : i ≤ 9007199254740992 := by
          have := Rat.floor_le q; rw [hy] at this
          have : (i : Rat) < 9007199254740992 := by grind
          have := (cast_lt (a := i) (b := 9007199254740992)).mp (by simpa using this); omega
        have : 0 ≤ i := by rw [← hy]; exact (Rat.le_floor_iff (x := 0)).mpr (by simpa using hq)
        rw [F.exact_small i (by omega) (by omega)]
        simp only [Dbl.cmp]
        unfold cmp3; split <;> (try split) <;> simp_all [sgn]
    · simp only [hq, ↓reduceIte]
      have hq' : q < 0 := by grind
      by_cases a : i < q.ceil
      · have : (i : Rat) < q := Rat.lt_ceil_iff.mp a
        simp [a, sgn, cmp3, this]
      by_cases b : q.ceil < i
      · have : q < (i : Rat) := by
          have := (cast_lt).mpr b; have := Rat.le_ceil (x := q); grind
        have : ¬ (i : Rat) < q := by grind
        simp [sgn, cmp3, *]
      have hy : q.ceil = i := by omega
      simp only [a, b, ↓reduceIte]
      by_cases big : q ≤ -9007199254740992
      · have hint := F.big_int q hr (Or.inl big)
        have hc : q.ceil = q.floor := by
          have := Rat.ceil_intCast q.floor; rw [hint] at this; exact this
        have hqi : q = (i : Rat) := by rw [← hint, ← hc, hy]
        rw [F.exact_repr i (hqi ▸ hr), hqi]
        simp [Dbl.cmp, cmp3_rat_eq, sgn]
      · have : -9007199254740992 ≤ i := by
          have := Rat.le_ceil (x := q); rw [hy] at this
          have : (-9007199254740992 : Rat) < (i : Rat) := by grind
          have := (cast_lt (a := -9007199254740992) (b := i)).mp (by simpa using this); omega
        have : i ≤ 0 := by rw [← hy]; exact Rat.ceil_le_iff.mpr (by simpa using Rat.le_of_lt hq')
        rw [F.exact_small i (by omega) (by omega)]
        simp only [Dbl.cmp]
        unfold cmp3; split <;> (try split) <;> simp_all [sgn]

theorem sgn_neg_swap (x : Int) : sgn (-x) = (sgn x).swap := by
  unfold sgn; split <;> split <;> (try split) <;> (try split) <;> simp_all [Ordering.swap] <;> omega

/-! `memcmp` over the shorter length, then the lengths: the lexicographic order. -/

theorem memcmpLen_cons (a b : UInt8) (as bs : List UInt8) :
    memcmpLen (a :: as) (b :: bs) =
      if a < b then .lt else if b < a then .gt else memcmpLen as bs := by
  unfold memcmpLen
  simp only [List.length_cons, Nat.add_min_add_right, memcmp]
  by_cases h1 : a < b
  · simp [h1]
  by_cases h2 : b < a
  · simp [h1, h2]
  simp only [h1, h2, ↓reduceIte]
  cases memcmp (min as.length bs.length) as bs <;> simp [cmp3]

theorem memcmpLen_eq_lex : ∀ a b : List UInt8, memcmpLen a b = lex a b
  | [], [] => by simp [memcmpLen, memcmp, lex, cmp3]
  | [], _ :: _ => by simp [memcmpLen, memcmp, lex, cmp3]
  | _ :: _, [] => by simp [memcmpLen, memcmp, lex, cmp3]
  | a :: as, b :: bs => by rw [memcmpLen_cons, memcmpLen_eq_lex as bs]; simp [lex]

theorem lex_swap : ∀ a b : List UInt8, (lex a b).swap = lex b a
  | [], [] => rfl
  | [], _ :: _ => rfl
  | _ :: _, [] => rfl
  | a :: as, b :: bs => by
    simp only [lex]
    by_cases h1 : a < b <;> by_cases h2 : b < a
    · exact absurd (UInt8.lt_trans h1 h2) (UInt8.lt_irrefl _)
    · simp [h1, h2, Ordering.swap]
    · simp [h1, h2, Ordering.swap]
    · simp only [h1, h2, ↓reduceIte]; exact lex_swap as bs

/-- **sqlite3MemCompare implements the documented order** (NULL < numbers by exact value < TEXT by collation <
BLOB), for well-formed values. -/
theorem memCompare_spec (F : Fmt) (c : Coll) (a b : Val) (ha : a.WF F) (hb : b.WF F) :
    memCompareC F c a b = order c a b := by
  cases a <;> cases b <;> simp_all [memCompareC, order, Val.cls, numCmp, Val.WF] <;>
    first
    | exact intFloatCompare_exact F _ _ ha hb
    | (rw [sgn_neg_swap, intFloatCompare_exact F _ _ hb ha])
    | exact memcmpLen_eq_lex _ _

end Turbo

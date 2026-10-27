/-
turbo's comparison fast paths (qc/qc.c, qc/qcg.c, qc/qvm.c at c3ebcb0), each modelled as written and proved equal to
SQLite's order (`order`) or to the opcode SQLite would have run, on the preconditions the code checks.
-/
import Turbo.Compare

namespace Turbo

/-! ## Helpers: truncation of a double, `(double)` of the result -/

/-- `(i64)r` for -2^63 ≤ r < 2^63 (C truncates toward zero). -/
def trunc (q : Rat) : Int := if 0 ≤ q then q.floor else q.ceil

private theorem cast_le {a b : Int} : ((a : Rat) ≤ (b : Rat)) ↔ a ≤ b := Rat.intCast_le_intCast
private theorem cast_lt {a b : Int} : ((a : Rat) < (b : Rat)) ↔ a < b := Rat.intCast_lt_intCast

/-- A double that is not an integer has magnitude below 2^53. -/
theorem small_of_frac (F : Fmt) {q : Rat} (hq : F.isD q) (h : (q.floor : Rat) ≠ q) :
    -9007199254740992 < q ∧ q < 9007199254740992 := by
  have := F.big_int q hq
  constructor <;> (apply Classical.byContradiction; intro hn; apply h; apply this; grind)

/-- The truncation of an in-range double converts back exactly, and equals the double iff it is an integer. -/
theorem trunc_exact (F : Fmt) {q : Rat} (hq : F.isD q) :
    F.i2d (trunc q) = .fin (trunc q) ∧ (((trunc q : Int) : Rat) = q ↔ (q.floor : Rat) = q) := by
  by_cases hint : (q.floor : Rat) = q
  · have hc : q.ceil = q.floor := by
      have := Rat.ceil_intCast q.floor; rw [hint] at this; exact this
    have ht : trunc q = q.floor := by unfold trunc; split <;> simp [hc]
    rw [ht]; refine ⟨F.exact_repr _ (by rw [hint]; exact hq), by simp [hint]⟩
  · have ⟨lo, hi⟩ := small_of_frac F hq hint
    refine ⟨F.exact_small _ ?_ ?_, ?_⟩
    · unfold trunc; split
      · have : (0 : Int) ≤ q.floor := (Rat.le_floor_iff (x := 0)).mpr (by simpa)
        omega
      · have := Rat.le_ceil (x := q)
        have : ((-9007199254740992 : Int) : Rat) < (q.ceil : Rat) := by simp; grind
        have := cast_lt.mp this; omega
    · unfold trunc; split
      · have := Rat.floor_le q
        have : (q.floor : Rat) < ((9007199254740992 : Int) : Rat) := by simp; grind
        have := cast_lt.mp this; omega
      · have : q.ceil ≤ (0 : Int) := Rat.ceil_le_iff.mpr (by simp; grind)
        omega
    · constructor
      · intro h; exfalso; apply hint
        unfold trunc at h; split at h
        · exact h
        · rename_i hneg
          -- q = ceil q is an integer, so floor q = q
          have := Rat.floor_intCast q.ceil; rw [h] at this; rw [this]; exact h
      · intro h; exact absurd h hint

/-! ## qvm: the sorter's compare (`qv_cmp`) and the numeric compare (`qv_numcmp`) -/

/-- qv_cmp: two integers in line; two texts under BINARY (or no collation) by `memcmp` and length; otherwise
sqlite3MemCompare. -/
def qvCmp (F : Fmt) (c : Coll) (a b : Val) : Ordering :=
  match a, b with
  | .int x, .int y => cmp3 x y
  | .text s, .text t => if c = .binary then memcmpLen s t else memCompareC F c a b
  | _, _ => memCompareC F c a b

theorem qvCmp_spec (F : Fmt) (c : Coll) (a b : Val) (ha : a.WF F) (hb : b.WF F) :
    qvCmp F c a b = order c a b := by
  rw [← memCompare_spec F c a b ha hb]
  cases a <;> cases b <;> simp [qvCmp, memCompareC]
  intro h; subst h; rfl

/-- qv_numcmp, for values with exactly MEM_Int or exactly MEM_Real (QV_NUM). -/
def qvNumcmp (F : Fmt) : Val → Val → Ordering
  | .int x, .int y => cmp3 x y
  | .int x, .real r => sgn (intFloatCompareC F x r)
  | .real r, .int y => sgn (- intFloatCompareC F y r)
  | .real r, .real s => r.cmp s
  | _, _ => .eq

def Val.isNum : Val → Bool
  | .int _ | .real _ => true
  | _ => false

theorem qvNumcmp_spec (F : Fmt) (a b : Val) (ha : a.WF F) (hb : b.WF F) (na : a.isNum) (nb : b.isNum) :
    qvNumcmp F a b = order .binary a b := by
  rw [← memCompare_spec F .binary a b ha hb]
  cases a <;> cases b <;> simp_all [qvNumcmp, memCompareC, Val.isNum]

/-! ## Comparison opcodes: OP_Eq .. OP_Ge (vdbe.c), qv_compare_op, rg_cmpi, qg_cmp_jump -/

inductive CmpOp where
  | eq | ne | lt | le | gt | ge
  deriving DecidableEq, Repr

/-- What the opcode tests of `res = sqlite3MemCompare(r[P3], r[P1])`. -/
def CmpOp.holds : CmpOp → Ordering → Bool
  | .eq, o => o == .eq
  | .ne, o => o != .eq
  | .lt, o => o == .lt
  | .le, o => o != .gt
  | .gt, o => o == .gt
  | .ge, o => o != .lt

/-- vdbe.c's (and qvm's) aLTb / aEQb / aGTb tables, indexed by opcode. -/
def tblLT : CmpOp → Bool | .ne => true | .eq => false | .gt => false | .le => true | .lt => true | .ge => false
def tblEQ : CmpOp → Bool | .ne => false | .eq => true | .gt => false | .le => true | .lt => false | .ge => true
def tblGT : CmpOp → Bool | .ne => true | .eq => false | .gt => true | .le => false | .lt => false | .ge => true

def byTables (op : CmpOp) (o : Ordering) : Bool :=
  match o with
  | .lt => tblLT op
  | .eq => tblEQ op
  | .gt => tblGT op

theorem tables_ok (op : CmpOp) (o : Ordering) : byTables op o = op.holds o := by
  cases op <;> cases o <;> rfl

/-- Comparison affinities (P5 & SQLITE_AFF_MASK). INTEGER, REAL and FLEXNUM act as NUMERIC here. -/
inductive Aff where
  | none | blob | text | numeric
  deriving DecidableEq, Repr

/-- The conversions the opcode applies, as parameters: applyNumericAffinity of a text (`none`: not a number, the
value stays text) and sqlite3VdbeMemStringify of a number. The theorems hold for every choice. -/
structure Conv where
  toNum : List UInt8 → Option Val
  toText : Val → List UInt8

/-- OP_Eq .. OP_Ge, as vdbe.c runs it (without SQLITE_NULLEQ, which qcg refuses; qvm runs vdbe.c's code for it):
1 = jump. `p3` is r[P3], `p1` r[P1]. -/
def vdbeCmp (F : Fmt) (K : Conv) (op : CmpOp) (aff : Aff) (jumpIfNull : Bool) (c : Coll) (p3 p1 : Val) : Bool :=
  match p3, p1 with
  | .int x, .int y => op.holds (cmp3 x y)
  | .null, _ | _, .null => jumpIfNull
  | a, b =>
    let num (v : Val) : Val := match v with
      | .text s => (K.toNum s).getD v
      | v => v
    let txt (v : Val) : Val := match v with
      | .int _ | .real _ => .text (K.toText v)
      | v => v
    let isStr : Val → Bool := fun v => match v with | .text _ => true | _ => false
    let (a', b') :=
      if aff = .numeric ∧ (isStr a ∨ isStr b) then (num a, num b)
      else if aff = .text ∧ (isStr a ∨ isStr b) then (txt a, txt b)
      else (a, b)
    op.holds (memCompareC F c a' b')

/-- qv_compare_op: two integers, or two plain numbers, in line; anything else goes to vdbe.c's code. -/
def qvCompareOp (F : Fmt) (K : Conv) (op : CmpOp) (aff : Aff) (jin : Bool) (c : Coll) (p3 p1 : Val) : Bool :=
  match p3, p1 with
  | .int x, .int y => byTables op (cmp3 x y)
  | a, b => if a.isNum ∧ b.isNum then byTables op (qvNumcmp F a b) else vdbeCmp F K op aff jin c a b

/-- **qv_compare_op = the opcode**: no affinity applies to two numbers, and numbers need no collation. -/
theorem qvCompareOp_spec (F : Fmt) (K : Conv) (op : CmpOp) (aff : Aff) (jin : Bool) (c : Coll) (p3 p1 : Val) (h3 : p3.WF F) (h1 : p1.WF F) :
    qvCompareOp F K op aff jin c p3 p1 = vdbeCmp F K op aff jin c p3 p1 := by
  unfold qvCompareOp
  split
  · simp [vdbeCmp, tables_ok]
  · rename_i hne
    split
    · rename_i hn
      obtain ⟨na, nb⟩ := hn
      rw [tables_ok, qvNumcmp_spec F _ _ h3 h1 na nb, ← memCompare_spec F .binary _ _ h3 h1]
      cases p3 <;> cases p1 <;> simp_all [Val.isNum, vdbeCmp, memCompareC]
    · rfl

/-- rg_cmpi (a region's speculated integer compare): on two integers it decides as the opcode does; on anything else
it widens to rg_cmp (qv_compare_op). -/
def rgCmpi (F : Fmt) (K : Conv) (op : CmpOp) (aff : Aff) (jin : Bool) (c : Coll) : Val → Val → Bool
  | .int x, .int y => byTables op (cmp3 x y)
  | a, b => qvCompareOp F K op aff jin c a b

theorem rgCmpi_spec (F : Fmt) (K : Conv) (op : CmpOp) (aff : Aff) (jin : Bool) (c : Coll) (p3 p1 : Val) (h3 : p3.WF F) (h1 : p1.WF F) :
    rgCmpi F K op aff jin c p3 p1 = vdbeCmp F K op aff jin c p3 p1 := by
  rw [← qvCompareOp_spec F K op aff jin c p3 p1 h3 h1]
  cases p3 <;> cases p1 <;> rfl

/-- qg_cmp_jump (qcg's filters, F_CMP): NULLs by SQLITE_JUMPIFNULL; two integers; two texts when the affinity is at
most TEXT, by `memcmp` and length; `none` = fall back. The builder admits only BINARY (or no) collation and no P5 flags
beyond the affinity and JUMPIFNULL. -/
def qgCmpJump (op : CmpOp) (aff : Aff) (jin : Bool) : Val → Val → Option Bool
  | .null, _ | _, .null => some jin
  | .int x, .int y => some (op.holds (cmp3 x y))
  | .text s, .text t => if aff ≠ .numeric then some (op.holds (memcmpLen s t)) else none
  | _, _ => none

theorem qgCmpJump_spec (F : Fmt) (K : Conv) (op : CmpOp) (aff : Aff) (jin : Bool) (p3 p1 : Val) (j : Bool)
    (h : qgCmpJump op aff jin p3 p1 = some j) : j = vdbeCmp F K op aff jin .binary p3 p1 := by
  cases p3 <;> cases p1 <;> simp_all [qgCmpJump, vdbeCmp, memCompareC, Coll.cmp] <;>
    (try split at h) <;> simp_all
  all_goals (split <;> simp_all)

/-! ## OP_Compare (qv_cmpvec) and the sorter's per-field direction (qv_keycmp, qg_sort_cmp) -/

structure SortFlags where
  desc : Bool
  bigNull : Bool
  deriving DecidableEq, Repr

/-- vdbeRecordCompareWithSkip's rule, which qv_keycmp and qg_sort_cmp copy: with flags set, negate unless BIGNULL is
set and DESC equals "either side is NULL". -/
def flipRC (f : SortFlags) (anyNull : Bool) : Bool :=
  (f.desc || f.bigNull) && (!f.bigNull || f.desc != anyNull)

/-- OP_Compare's rule (vdbe.c, qv_cmpvec): negate for BIGNULL with a NULL side, then negate for DESC. -/
def flipCmp (f : SortFlags) (anyNull : Bool) : Bool :=
  (f.bigNull && anyNull) != f.desc

theorem flip_same (f : SortFlags) (n : Bool) : flipRC f n = flipCmp f n := by
  cases f with | mk d b => cases d <;> cases b <;> cases n <;> rfl

def Val.isNull : Val → Bool | .null => true | _ => false
@[simp] theorem Val.isNull_null : Val.null.isNull = true := rfl

/-- The ORDER BY semantics: per field, the value order under the field's collation, reversed for DESC; NULLs first,
or last with NULLS LAST on ASC / NULLS FIRST on DESC (BIGNULL). -/
def fieldOrder (c : Coll) (f : SortFlags) (a b : Val) : Ordering :=
  if a.isNull && b.isNull then .eq
  else if f.bigNull && (a.isNull || b.isNull) then
    -- BIGNULL: NULL is larger than everything, then DESC reverses
    (if a.isNull then Ordering.gt else Ordering.lt) |> fun o => if f.desc then o.swap else o
  else
    let o := order c a b
    if f.desc then o.swap else o

def keyCmp (F : Fmt) (cs : List (Coll × SortFlags)) (a b : List Val) : Ordering :=
  match cs, a, b with
  | (c, f) :: cs, x :: xs, y :: ys =>
    let o := qvCmp F c x y
    if o = .eq then keyCmp F cs xs ys else if flipRC f (x.isNull || y.isNull) then o.swap else o
  | _, _, _ => .eq

def keySpec (cs : List (Coll × SortFlags)) (a b : List Val) : Ordering :=
  match cs, a, b with
  | (c, f) :: cs, x :: xs, y :: ys =>
    let o := fieldOrder c f x y
    if o = .eq then keySpec cs xs ys else o
  | _, _, _ => .eq

theorem order_null_l (c : Coll) (b : Val) (hb : b.isNull = false) : order c .null b = .lt := by
  cases b <;> simp_all [order, Val.cls, Val.isNull]
theorem order_null_r (c : Coll) (a : Val) (ha : a.isNull = false) : order c a .null = .gt := by
  cases a <;> simp_all [order, Val.cls, Val.isNull]

/-- One field: SQLite's flip rule applied to the value order is the ORDER BY order of that field. -/
theorem field_step (c : Coll) (f : SortFlags) (x y : Val) (R : Ordering) :
    (if order c x y = .eq then R else if flipRC f (x.isNull || y.isNull) then (order c x y).swap else order c x y)
      = (if fieldOrder c f x y = .eq then R else fieldOrder c f x y) := by
  obtain ⟨d, b⟩ := f
  cases hx : x.isNull <;> cases hy : y.isNull
  · simp only [fieldOrder, hx, hy, Bool.false_or, Bool.and_false, ite_false, Bool.false_eq_true,
      flipRC, bne]
    cases d <;> cases b <;> cases order c x y <;> rfl
  · cases y <;> simp [Val.isNull] at hy
    cases d <;> cases b <;> simp [fieldOrder, flipRC, hx, Ordering.swap, order_null_r c x hx]
  · cases x <;> simp [Val.isNull] at hx
    cases d <;> cases b <;> simp [fieldOrder, flipRC, hy, Ordering.swap, order_null_l c y hy]
  · cases x <;> simp [Val.isNull] at hx
    cases y <;> simp [Val.isNull] at hy
    simp [order, Val.cls, fieldOrder, Val.isNull]

/-- **qv_keycmp (and qg_sort_cmp, the same code) sort by the ORDER BY semantics**, including NULLS FIRST / LAST. -/
theorem keyCmp_spec (F : Fmt) (cs : List (Coll × SortFlags)) (a b : List Val)
    (ha : ∀ v ∈ a, v.WF F) (hb : ∀ v ∈ b, v.WF F) : keyCmp F cs a b = keySpec cs a b := by
  induction cs generalizing a b with
  | nil => cases a <;> cases b <;> simp [keyCmp, keySpec]
  | cons cf cs ih =>
    obtain ⟨c, f⟩ := cf
    cases a with
    | nil => simp [keyCmp, keySpec]
    | cons x xs =>
      cases b with
      | nil => simp [keyCmp, keySpec]
      | cons y ys =>
        have hx := ha x (by simp); have hy := hb y (by simp)
        have ih' := ih xs ys (fun v h => ha v (by simp [h])) (fun v h => hb v (by simp [h]))
        simp only [keyCmp, keySpec, qvCmp_spec F c x y hx hy, ih']
        exact field_step c f x y _

/-! ## qc's integer index probe (qc_idxkey_at's first field, qc_idx_cmp_kind) -/

def I64MIN : Int := -9223372036854775808
def I64MAX : Int := 9223372036854775807

/-- qc_idxkey_at: the first field of an index cell as (kind, key): 1 = an integer value (integral reals too), 0 = never
equal but among the numbers (NULL: INT64_MIN; a non-integral real: its floor; reals beyond the int64 range: the
nearer end), 2 = text or blob. -/
def idxKey (F : Fmt) : Val → Int × Int
  | .null => (0, I64MIN)
  | .int i => (1, i)
  | .real .negInf => (0, I64MIN)
  | .real .posInf => (0, I64MAX)
  | .real (.fin r) =>
    if 9223372036854775808 ≤ r then (0, I64MAX)
    else if r < -9223372036854775808 then (0, I64MIN)
    else
      let f0 := trunc r
      let f := if (F.i2d f0).cmp (.fin r) = .gt then f0 - 1 else f0
      (if (F.i2d f).cmp (.fin r) = .eq then 1 else 0, f)
  | .text _ | .blob _ => (2, 0)

/-- qc_idx_cmp_kind (2 = not handled is not reachable from a well-formed value). -/
def idxCmpKind (kk : Int × Int) (key : Int) : Int :=
  let (kind, k) := kk
  if kind < 0 then 2
  else if kind = 2 then 1
  else if kind = 1 then (if k < key then -1 else if key < k then 1 else 0)
  else if k = I64MIN then -1
  else if key ≤ k then 1 else -1

private theorem dcmp_fin (a b : Rat) : (Dbl.fin a).cmp (.fin b) = cmp3 a b := rfl

theorem idxKey_int (F : Fmt) (q : Rat) (hv : F.isD q) (h1 : ¬ 9223372036854775808 ≤ q)
    (h2 : ¬ q < -9223372036854775808) (hint : (q.floor : Rat) = q) : idxKey F (.real (.fin q)) = (1, q.floor) := by
  obtain ⟨tex, tiff⟩ := trunc_exact F hv
  have ht : ((trunc q : Int) : Rat) = q := tiff.mpr hint
  have htf : trunc q = q.floor := Rat.intCast_inj.mp (by rw [ht, hint])
  simp only [idxKey, h1, h2, ↓reduceIte, tex, dcmp_fin, ht, cmp3_rat_eq, reduceCtorEq]
  simp [htf]

theorem idxKey_frac (F : Fmt) (q : Rat) (hv : F.isD q) (h1 : ¬ 9223372036854775808 ≤ q)
    (h2 : ¬ q < -9223372036854775808) (hint : (q.floor : Rat) ≠ q) : idxKey F (.real (.fin q)) = (0, q.floor) := by
  obtain ⟨tex, tiff⟩ := trunc_exact F hv
  have ⟨lo, hi⟩ := small_of_frac F hv hint
  have fl1 := Rat.floor_le q
  have fl2 := Rat.lt_floor_add_one q
  have flt : (q.floor : Rat) < q := by grind
  have hfl : (if cmp3 ((trunc q : Int) : Rat) q = .gt then trunc q - 1 else trunc q) = q.floor := by
    unfold trunc cmp3
    by_cases hq : 0 ≤ q
    · have : ¬ q < (q.floor : Rat) := by grind
      simp [hq, flt]
    · have hc : (q.ceil : Rat) ≠ q := by
        intro h; apply hint; have := Rat.floor_intCast q.ceil; rw [h] at this; rw [this]; exact h
      have c1 : q < (q.ceil : Rat) := by have := Rat.le_ceil (x := q); grind
      have c2 : ¬ (q.ceil : Rat) < q := by grind
      simp only [hq, ↓reduceIte, c1, c2]
      have a3 : q.ceil ≤ q.floor + 1 := Rat.ceil_le_iff.mpr (by simp; grind)
      have a4 : q.floor < q.ceil := cast_lt.mp (by grind)
      omega
  have hfe : F.i2d q.floor = .fin (q.floor : Rat) := by
    apply F.exact_small
    · have : ((-9007199254740992 : Int) : Rat) < ((q.floor + 1 : Int) : Rat) := by simp at *; grind
      have := cast_lt.mp this; omega
    · have : ((q.floor : Int) : Rat) < ((9007199254740992 : Int) : Rat) := by simp at *; grind
      have := cast_lt.mp this; omega
  have hne : cmp3 (q.floor : Rat) q = .lt := cmp3_lt flt
  simp only [idxKey, h1, h2, ↓reduceIte, tex, dcmp_fin]
  rw [hfl, hfe, dcmp_fin, hne]
  simp

/-- **The integer index probe orders a cell's first field as SQLite does** against an integer key: NULL first,
numbers by exact value (an integral real equals its integer), text and blobs after. -/
theorem idxCmp_spec (F : Fmt) (v : Val) (key : Int) (hv : v.WF F) (hk : InI64 key) :
    sgn (idxCmpKind (idxKey F v) key) = order .binary v (.int key) := by
  obtain ⟨klo, khi⟩ := hk
  have kq1 : (-9223372036854775808 : Rat) ≤ (key : Rat) := by
    have := (cast_le (a := -9223372036854775808) (b := key)).mpr klo; simpa using this
  have kq2 : (key : Rat) < 9223372036854775808 := by
    have := (cast_lt (a := key) (b := 9223372036854775808)).mpr khi; simpa using this
  have kmax : key ≤ I64MAX := by unfold I64MAX; omega
  cases v with
  | null => simp [idxKey, idxCmpKind, I64MIN, sgn, order, Val.cls]
  | int i =>
    simp only [idxKey, idxCmpKind, order, Val.cls, numCmp, cmp3]
    by_cases a : i < key <;> by_cases b : key < i <;> simp [a, b, sgn]
  | text s => simp [idxKey, idxCmpKind, sgn, order, Val.cls]
  | blob s => simp [idxKey, idxCmpKind, sgn, order, Val.cls]
  | real r =>
    cases r with
    | negInf => simp [idxKey, idxCmpKind, I64MIN, sgn, order, Val.cls, numCmp, cmpIntDbl, Ordering.swap]
    | posInf =>
      have k' : key ≤ 9223372036854775807 := by omega
      simp [idxKey, idxCmpKind, I64MIN, I64MAX, sgn, order, Val.cls, numCmp, cmpIntDbl, Ordering.swap, k']
    | fin q =>
      simp only [Val.WF, Dbl.Valid] at hv
      simp only [order, Val.cls, Nat.lt_irrefl, ↓reduceIte, numCmp, cmpIntDbl]
      by_cases h1 : 9223372036854775808 ≤ q
      · simp only [idxKey, h1, ↓reduceIte, idxCmpKind, I64MAX, I64MIN]
        have : (key : Rat) < q := by grind
        have k' : key ≤ 9223372036854775807 := by omega
        simp [sgn, cmp3, Ordering.swap, this, k']
      by_cases h2 : q < -9223372036854775808
      · simp only [idxKey, h1, h2, ↓reduceIte, idxCmpKind, I64MIN]
        have : q < (key : Rat) := by grind
        have : ¬ (key : Rat) < q := by grind
        simp [sgn, cmp3, Ordering.swap, *]
      by_cases hint : (q.floor : Rat) = q
      · rw [idxKey_int F q hv h1 h2 hint]
        simp only [idxCmpKind]
        by_cases a : q.floor < key
        · have : q < (key : Rat) := by have := cast_lt.mpr a; grind
          have : ¬ (key : Rat) < q := by grind
          simp [sgn, cmp3, Ordering.swap, *]
        by_cases b : key < q.floor
        · have : (key : Rat) < q := by have := cast_lt.mpr b; grind
          simp [sgn, cmp3, Ordering.swap, *]
        have : q.floor = key := by omega
        have : q = (key : Rat) := by rw [← hint, this]
        subst this; simp [sgn, cmp3, Ordering.swap, Rat.lt_irrefl]
      · rw [idxKey_frac F q hv h1 h2 hint]
        have ⟨lo, hi⟩ := small_of_frac F hv hint
        have nmin : q.floor ≠ I64MIN := by
          intro h
          have : ((q.floor : Int) : Rat) = -9223372036854775808 := by rw [h]; simp [I64MIN]
          have := Rat.floor_le q; have := Rat.lt_floor_add_one q
          simp at *; grind
        have flt : (q.floor : Rat) < q := by have := Rat.floor_le q; grind
        simp only [idxCmpKind, nmin]
        by_cases kf : key ≤ q.floor
        · have : (key : Rat) < q := by have := cast_le.mpr kf; grind
          simp [kf, sgn, cmp3, Ordering.swap, this]
        · have : q < (key : Rat) := by
            have : q.floor + 1 ≤ key := by omega
            have := cast_le.mpr this; have := Rat.lt_floor_add_one q; grind
          have : ¬ (key : Rat) < q := by grind
          simp [sgn, cmp3, Ordering.swap, *]

/-! ## qv_idxcmp's jump: OP_IdxLE / IdxGT / IdxLT / IdxGE -/

/-- The opcodes, by their numbers in SQLite 3.54.1 (`OP_IdxLE` 40, `OP_IdxGT` 41, `OP_IdxLT` 42, `OP_IdxGE` 45). -/
def opIdxLE : Nat := 40
def opIdxGT : Nat := 41
def opIdxLT : Nat := 42
def opIdxGE : Nat := 45

/-- qv_idxcmp's (and vdbe.c's) encoding: `c` the sign of (index fields) - (key) over the compared fields, equal giving
`default_rc` (-1 for IdxLE and IdxGT, 0 otherwise); then negate for LE/LT (the opcode's parity), else add one; jump
when positive. -/
def idxJump (op : Nat) (c : Int) : Bool :=
  let res := if c ≠ 0 then c else (if op < opIdxLT then -1 else 0)
  let res := if op % 2 = opIdxLT % 2 then -res else res + 1
  0 < res

/-- **The encoding means what the opcodes say**: IdxLE jumps when the index entry is ≤ the key, IdxGT when >, IdxLT
when <, IdxGE when ≥ (over the compared prefix). -/
theorem idxJump_spec (c : Int) (hc : c = -1 ∨ c = 0 ∨ c = 1) :
    idxJump opIdxLE c = decide (c ≤ 0) ∧ idxJump opIdxGT c = decide (0 < c) ∧
    idxJump opIdxLT c = decide (c < 0) ∧ idxJump opIdxGE c = decide (0 ≤ c) := by
  rcases hc with h | h | h <;> subst h <;> decide

/-! ## qcg: the index order of NULL / INTEGER / TEXT (qg_order), min() / max() steps (qg_aggstep) -/

def Val.qgSortable : Val → Bool
  | .null | .int _ | .text _ => true
  | _ => false

def ordInt : Ordering → Int
  | .lt => -1
  | .eq => 0
  | .gt => 1

@[simp] theorem sgn_ordInt (o : Ordering) : sgn (ordInt o) = o := by cases o <;> rfl

/-- qg_order. -/
def qgOrder (a b : Val) : Int :=
  let cl : Val → Int := fun v => match v with | .null => 0 | .int _ => 1 | _ => 2
  if cl a ≠ cl b then cl a - cl b
  else match a, b with
    | .int x, .int y => if x < y then -1 else if y < x then 1 else 0
    | .text s, .text t => ordInt (memcmpLen s t)
    | _, _ => 0

theorem qgOrder_spec (a b : Val) (ha : a.qgSortable) (hb : b.qgSortable) :
    sgn (qgOrder a b) = order .binary a b := by
  cases a <;> cases b <;> simp_all [Val.qgSortable, qgOrder, order, Val.cls, numCmp, Coll.cmp]
  all_goals first
    | rfl
    | (unfold sgn cmp3; split <;> (try split) <;> (try split) <;> (try split) <;> simp_all <;> omega)

/-- qg_aggstep's compare of a new value x with the current min/max (both INTEGER or TEXT; NULLs never reach it). -/
def qgAggCmp (x cur : Val) : Int :=
  match x, cur with
  | .int a, .int b => if a < b then -1 else if b < a then 1 else 0
  | .text s, .text t => ordInt (memcmpLen s t)
  | .int _, _ => -1
  | _, _ => 1

def Val.isIntOrText : Val → Bool
  | .int _ | .text _ => true
  | _ => false

theorem qgAggCmp_spec (x cur : Val) (hx : x.isIntOrText) (hc : cur.isIntOrText) :
    sgn (qgAggCmp x cur) = order .binary x cur := by
  cases x <;> cases cur <;> simp_all [Val.isIntOrText, qgAggCmp, order, Val.cls, numCmp, Coll.cmp]
  all_goals first
    | rfl
    | (unfold sgn cmp3; split <;> (try split) <;> (try split) <;> (try split) <;> simp_all <;> omega)

/-! ## qvm's hash sets (DISTINCT): qv_hk_mem / qv_hk_val, qv_hk_eq -/

/-- A hash-set key field: c = 0 null, 1 a number with an integer value, 2 another real, 3 text, 4 blob. -/
inductive Hk where
  | null
  | num (i : Int)
  | real (r : Dbl)
  | text (s : List UInt8)
  | blob (b : List UInt8)
  deriving DecidableEq, Repr

/-- qv_hk_num: a real in [-2^63, 2^63) whose `(double)(i64)r == r` is keyed as that integer. -/
def hkOf (F : Fmt) : Val → Hk
  | .null => .null
  | .int i => .num i
  | .real (.fin r) =>
    if -9223372036854775808 ≤ r ∧ r < 9223372036854775808 ∧ (F.i2d (trunc r)).cmp (.fin r) = .eq then .num (trunc r)
    else .real (.fin r)
  | .real r => .real r
  | .text s => .text s
  | .blob b => .blob b

theorem lex_eq_iff : ∀ a b : List UInt8, lex a b = .eq ↔ a = b
  | [], [] => by simp [lex]
  | [], _ :: _ => by simp [lex]
  | _ :: _, [] => by simp [lex]
  | a :: as, b :: bs => by
    simp only [lex, List.cons.injEq]
    by_cases h1 : a < b
    · simp [h1]; intro h; subst h; exact absurd h1 (UInt8.lt_irrefl _)
    by_cases h2 : b < a
    · simp [h1, h2]; intro h; subst h; exact absurd h2 (UInt8.lt_irrefl _)
    simp only [h1, h2, ↓reduceIte, lex_eq_iff as bs]
    have : a = b := by
      have := UInt8.le_antisymm (UInt8.not_lt.mp h2) (UInt8.not_lt.mp h1); exact this
    simp [this]

theorem dbl_cmp_eq (a b : Dbl) : a.cmp b = .eq ↔ a = b := by
  cases a <;> cases b <;> simp [Dbl.cmp, cmp3, Dbl.rank]
  rename_i x y
  constructor
  · intro h; split at h <;> (try split at h) <;> simp_all; grind
  · intro h; subst h; simp [Rat.lt_irrefl]

/-- The key of a finite real: an in-range integer exactly when the real is one. -/
theorem hk_real (F : Fmt) (q : Rat) (hq : F.isD q) :
    (∃ i, InI64 i ∧ (i : Rat) = q ∧ hkOf F (.real (.fin q)) = .num i) ∨
    ((∀ i : Int, InI64 i → (i : Rat) ≠ q) ∧ hkOf F (.real (.fin q)) = .real (.fin q)) := by
  obtain ⟨tex, tiff⟩ := trunc_exact F hq
  simp only [hkOf, tex, dcmp_fin]
  by_cases hr : -9223372036854775808 ≤ q ∧ q < 9223372036854775808 ∧ cmp3 ((trunc q : Int) : Rat) q = .eq
  · left
    obtain ⟨lo, hi, he⟩ := hr
    have ht : ((trunc q : Int) : Rat) = q := by
      unfold cmp3 at he; split at he <;> (try split at he) <;> simp_all; grind
    refine ⟨trunc q, ⟨?_, ?_⟩, ht, by simp [lo, hi, he]⟩
    · have : ((-9223372036854775808 : Int) : Rat) ≤ ((trunc q : Int) : Rat) := by rw [ht]; simpa using lo
      exact cast_le.mp this
    · have : ((trunc q : Int) : Rat) < ((9223372036854775808 : Int) : Rat) := by rw [ht]; simpa using hi
      exact cast_lt.mp this
  · right
    refine ⟨?_, by simp [hr]⟩
    intro i ⟨ilo, ihi⟩ hiq
    apply hr
    have lo : (-9223372036854775808 : Rat) ≤ q := by
      rw [← hiq]; have := cast_le.mpr ilo; simpa using this
    have hi : q < 9223372036854775808 := by
      rw [← hiq]; have := cast_lt.mpr ihi; simpa using this
    have hint : (q.floor : Rat) = q := by rw [← hiq]; simp [Rat.floor_intCast]
    refine ⟨lo, hi, ?_⟩
    rw [tiff.mpr hint]; exact cmp3_rat_eq q

theorem cmp3_eq_iff_rat (a b : Rat) : cmp3 a b = .eq ↔ a = b := by
  unfold cmp3; constructor
  · intro h; split at h <;> (try split at h) <;> simp_all; grind
  · intro h; subst h; simp [Rat.lt_irrefl]

theorem cmp3_eq_iff_int (a b : Int) : cmp3 a b = .eq ↔ a = b := by
  unfold cmp3; constructor
  · intro h; split at h <;> (try split at h) <;> simp_all; omega
  · intro h; subst h; simp

theorem hk_real' (F : Fmt) (r : Dbl) (hr : r.Valid F) :
    (∃ i, InI64 i ∧ r = .fin i ∧ hkOf F (.real r) = .num i) ∨
    ((∀ i : Int, InI64 i → r ≠ .fin i) ∧ hkOf F (.real r) = .real r) := by
  cases r with
  | negInf => right; simp [hkOf]
  | posInf => right; simp [hkOf]
  | fin q =>
    rcases hk_real F q hr with ⟨i, hi, hq, hk⟩ | ⟨hn, hk⟩
    · left; exact ⟨i, hi, by rw [hq], hk⟩
    · right; refine ⟨fun i hi h => hn i hi ?_, hk⟩; simp at h; exact h.symm

theorem cmpIntDbl_eq_iff (i : Int) (r : Dbl) : cmpIntDbl i r = .eq ↔ r = .fin i := by
  cases r <;> simp [cmpIntDbl, cmp3_eq_iff_rat]
  constructor <;> intro h <;> exact h.symm

/-- **The hash set's key equality is the index's equality** (BINARY): two keys are equal exactly when
sqlite3VdbeRecordCompare would call the values equal, so DISTINCT through the hash set keeps the same rows. -/
theorem hk_eq_iff (F : Fmt) (a b : Val) (ha : a.WF F) (hb : b.WF F) :
    hkOf F a = hkOf F b ↔ order .binary a b = .eq := by
  have swapEq : ∀ o : Ordering, o.swap = .eq ↔ o = .eq := by intro o; cases o <;> simp [Ordering.swap]
  cases a with
  | real r =>
    rcases hk_real' F r ha with ⟨i, hi, hr, hk⟩ | ⟨hn, hk⟩ <;> rw [hk] <;>
    cases b with
    | real s =>
      rcases hk_real' F s hb with ⟨j, hj, hs, hk'⟩ | ⟨hn', hk'⟩ <;> rw [hk'] <;>
        simp [order, Val.cls, numCmp, dbl_cmp_eq] <;> subst_vars <;> simp_all
      all_goals (try (intro h; subst h; exact hn' i hi rfl))
    | int j =>
      simp [hkOf, order, Val.cls, numCmp, swapEq, cmpIntDbl_eq_iff] <;> subst_vars
      all_goals first | done | exact hn j hb | simp_all
    | _ => simp [hkOf, order, Val.cls]
  | int i =>
    cases b with
    | real s =>
      rcases hk_real' F s hb with ⟨j, hj, hs, hk'⟩ | ⟨hn', hk'⟩ <;> rw [hk'] <;>
        simp [hkOf, order, Val.cls, numCmp, cmpIntDbl_eq_iff]
      · subst hs; constructor
        · intro h; subst h; rfl
        · intro h; simp at h; exact h.symm
      · exact hn' i ha
    | int j => simp [hkOf, order, Val.cls, numCmp, cmp3_eq_iff_int]
    | _ => simp [hkOf, order, Val.cls]
  | _ =>
    cases b with
    | real r => rcases hk_real' F r hb with ⟨j, _, _, hk'⟩ | ⟨_, hk'⟩ <;> rw [hk'] <;> simp [hkOf, order, Val.cls]
    | _ => simp [hkOf, order, Val.cls, Coll.cmp, memcmpLen_eq_lex, lex_eq_iff]

end Turbo

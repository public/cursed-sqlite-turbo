/-
Sorting: SQLite's value order is a total preorder (BINARY), so is the ORDER BY key order built from it, and qvm's
sorter (qv_sort, qc/qvm.c: a bottom-up merge sort of row indices, the earlier row first on ties) returns exactly the
stable sort of the rows by that order: `List.mergeSort` of core Lean, whose stability is `List.mergeSort_zipIdx`.
-/
import Turbo.SortKey

namespace Turbo

/-! ## The value order is a total preorder (BINARY) -/

/-- A number's exact value. -/
def Val.num : Val → Dbl
  | .int i => .fin i
  | .real r => r
  | _ => .fin 0

theorem cmp3_int_rat (a b : Int) : cmp3 a b = cmp3 (a : Rat) (b : Rat) := by
  unfold cmp3
  simp only [Rat.intCast_lt_intCast]

/-- Two numbers compare by their exact values. -/
theorem numCmp_eq (a b : Val) (ha : a.isNum) (hb : b.isNum) : numCmp a b = a.num.cmp b.num := by
  cases a <;> cases b <;> simp [Val.isNum] at ha hb <;> simp only [numCmp, Val.num]
  · rw [cmp3_int_rat]; rfl
  · rename_i i r; cases r <;> rfl
  · rename_i r i
    rw [show (cmpIntDbl i r).swap = ((Dbl.fin i).cmp r).swap by cases r <;> rfl, dbl_cmp_swap]

theorem cmp3_rat_le (a b : Rat) : cmp3 a b ≠ .gt ↔ a ≤ b := by
  unfold cmp3
  by_cases x1 : a < b
  · simp [x1]; grind
  · by_cases x2 : b < a
    · simp [x1, x2]; grind
    · simp [x1, x2]; grind

theorem cmp3_nat_le (a b : Nat) : cmp3 a b ≠ .gt ↔ a ≤ b := by
  unfold cmp3
  by_cases x1 : a < b
  · simp [x1]; omega
  · by_cases x2 : b < a <;> simp [x1, x2] <;> omega

theorem dbl_trans {a b c : Dbl} (h1 : a.cmp b ≠ .gt) (h2 : b.cmp c ≠ .gt) : a.cmp c ≠ .gt := by
  cases a <;> cases b <;> cases c <;> simp only [Dbl.cmp, Dbl.rank] at * <;>
    first
    | (rw [cmp3_rat_le] at *; exact Rat.le_trans h1 h2)
    | (rw [cmp3_nat_le] at *; omega)
    | (rw [cmp3_nat_le] at h1; omega)
    | (rw [cmp3_nat_le] at h2; omega)

theorem lex_cons (x y : UInt8) (xs ys : List UInt8) :
    lex (x :: xs) (y :: ys) ≠ .gt ↔ x < y ∨ (x = y ∧ lex xs ys ≠ .gt) := by
  simp only [lex]
  by_cases a1 : x < y
  · simp [a1]
  · by_cases a2 : y < x
    · simp [a1, a2]; intro h; subst h; exact (UInt8.lt_irrefl _ a2).elim
    · have : x = y := UInt8.le_antisymm (UInt8.not_lt.mp a2) (UInt8.not_lt.mp a1)
      simp [this]

theorem lex_trans : ∀ {a b c : List UInt8}, lex a b ≠ .gt → lex b c ≠ .gt → lex a c ≠ .gt
  | [], [], _, _, h => h
  | [], _ :: _, c, _, _ => by cases c <;> simp [lex]
  | _ :: _, [], _, h, _ => by simp [lex] at h
  | _ :: _, _ :: _, [], _, h => by simp [lex] at h
  | x :: xs, y :: ys, z :: zs, h1, h2 => by
    rw [lex_cons] at *
    rcases h1 with a | ⟨rfl, a⟩ <;> rcases h2 with b | ⟨rfl, b⟩
    · left; exact UInt8.lt_trans a b
    · left; exact a
    · left; exact b
    · right; exact ⟨rfl, lex_trans a b⟩

/-- The order within a storage class. -/
def within (a b : Val) : Ordering :=
  match a, b with
  | .text s, .text t => lex s t
  | .blob s, .blob t => lex s t
  | .null, .null => .eq
  | a, b => a.num.cmp b.num

theorem order_same (a b : Val) (h : a.cls = b.cls) : order .binary a b = within a b := by
  cases a <;> cases b <;> simp [Val.cls] at h <;>
    simp [order, Val.cls, within, Coll.cmp, memcmpLen_eq_lex] <;>
    rw [numCmp_eq _ _ rfl rfl]

theorem order_ne_gt (a b : Val) : order .binary a b ≠ .gt ↔ a.cls < b.cls ∨ (a.cls = b.cls ∧ within a b ≠ .gt) := by
  by_cases h1 : a.cls < b.cls
  · simp [order, h1]
  by_cases h2 : b.cls < a.cls
  · simp [order, h1, h2]; omega
  have h : a.cls = b.cls := by omega
  rw [order_same a b h]; simp [h]

theorem within_trans (a b c : Val) (hab : a.cls = b.cls) (hbc : b.cls = c.cls) (h1 : within a b ≠ .gt)
    (h2 : within b c ≠ .gt) : within a c ≠ .gt := by
  cases a <;> cases b <;> simp [Val.cls] at hab <;> cases c <;> simp [Val.cls] at hbc <;>
    simp only [within] at * <;>
    first
    | exact lex_trans h1 h2
    | exact dbl_trans h1 h2
    | simp

/-- **SQLite's order is transitive** (BINARY): with antisymmetry (`order_swap`), a total preorder. -/
theorem order_trans (a b c : Val) (h1 : order .binary a b ≠ .gt) (h2 : order .binary b c ≠ .gt) :
    order .binary a c ≠ .gt := by
  rw [order_ne_gt] at *
  rcases h1 with h1 | ⟨e1, w1⟩ <;> rcases h2 with h2 | ⟨e2, w2⟩
  · left; omega
  · left; omega
  · left; omega
  · right; exact ⟨by omega, within_trans a b c e1 e2 w1 w2⟩

/-! ## Total preorders -/

/-- A comparator that is a total preorder: antisymmetric (`swap`) and transitive. -/
structure TP {α} (f : α → α → Ordering) : Prop where
  swap : ∀ a b, f b a = (f a b).swap
  trans : ∀ a b c, f a b ≠ .gt → f b c ≠ .gt → f a c ≠ .gt

theorem swap_ne_gt (o : Ordering) : o.swap ≠ .gt ↔ o ≠ .lt := by cases o <;> simp [Ordering.swap]

theorem TP.lt_le {α} {f : α → α → Ordering} (t : TP f) {a b c : α} (h1 : f a b = .lt) (h2 : f b c ≠ .gt) :
    f a c = .lt := by
  apply Classical.byContradiction; intro h
  have : f c a ≠ .gt := by rw [t.swap, swap_ne_gt]; exact h
  have := t.trans b c a h2 this
  rw [t.swap, swap_ne_gt] at this; exact this h1

theorem TP.le_lt {α} {f : α → α → Ordering} (t : TP f) {a b c : α} (h1 : f a b ≠ .gt) (h2 : f b c = .lt) :
    f a c = .lt := by
  apply Classical.byContradiction; intro h
  have : f c a ≠ .gt := by rw [t.swap, swap_ne_gt]; exact h
  have := t.trans c a b this h1
  rw [t.swap, swap_ne_gt] at this; exact this h2

theorem TP.eq_eq {α} {f : α → α → Ordering} (t : TP f) {a b c : α} (h1 : f a b = .eq) (h2 : f b c = .eq) :
    f a c = .eq := by
  have x := t.trans a b c (by simp [h1]) (by simp [h2])
  have y : f c a ≠ .gt := t.trans c b a (by rw [t.swap, h2]; simp [Ordering.swap]) (by rw [t.swap, h1]; simp [Ordering.swap])
  rw [t.swap, swap_ne_gt] at y
  cases h : f a c <;> simp_all

theorem order_rev (a b : Val) : order .binary a b ≠ .lt ↔ order .binary b a ≠ .gt := by
  rw [← order_swap b a]; cases order .binary b a <;> simp [Ordering.swap]

theorem order_tp : TP (order .binary) := ⟨fun a b => (order_swap a b).symm, order_trans⟩

theorem nullOr (v : Val) : v = .null ∨ v.isNull = false := by cases v <;> simp [Val.isNull]

theorem order_nn : order .binary .null .null = .eq := by simp [order, Val.cls]

/-- A field's ORDER BY order (BINARY, any DESC / NULLS FIRST / LAST) is a total preorder. -/
theorem fieldOrder_tp (f : SortFlags) : TP (fieldOrder .binary f) := by
  obtain ⟨d, bn⟩ := f
  constructor
  · intro a b
    cases ha : a.isNull <;> cases hb : b.isNull <;>
      simp [fieldOrder, ha, hb] <;> cases d <;> cases bn <;> simp [Ordering.swap] <;>
      first | rfl | (rw [← order_swap]; cases order .binary a b <;> rfl) | skip
  · intro a b c h1 h2
    have ot := order_trans
    rcases nullOr a with rfl | ha <;> rcases nullOr b with rfl | hb <;> rcases nullOr c with rfl | hc <;>
      simp [fieldOrder, *, order_null_l, order_null_r] at h1 h2 ⊢ <;>
      cases d <;> cases bn <;> simp at h1 h2 ⊢ <;>
      first
      | exact ot a b c h1 h2
      | exact (order_rev a c).mpr (ot c b a ((order_rev b c).mp h2) ((order_rev a b).mp h1))
      | skip

/-! ## The ORDER BY key order -/

abbrev Keys := List (Coll × SortFlags)

/-- BINARY collations throughout (the sort-key and transitivity proofs are for BINARY). -/
def Keys.binary (cs : Keys) : Prop := ∀ x ∈ cs, x.1 = .binary

theorem keySpec_swap : ∀ (cs : Keys) (a b : List Val), cs.binary → keySpec cs b a = (keySpec cs a b).swap
  | [], _, _, _ => by simp [keySpec, Ordering.swap]
  | _ :: _, [], _, _ => by cases ‹List Val› <;> simp [keySpec, Ordering.swap]
  | _ :: _, _ :: _, [], _ => by simp [keySpec, Ordering.swap]
  | (c, f) :: cs, x :: xs, y :: ys, hb => by
    have hc : c = .binary := hb (c, f) (by simp)
    subst hc
    have ih := keySpec_swap cs xs ys (fun z hz => hb z (by simp [hz]))
    have fs := (fieldOrder_tp f).swap x y
    simp only [keySpec, fs, ih]
    cases fieldOrder .binary f x y <;> simp [Ordering.swap]

theorem keySpec_trans : ∀ (cs : Keys) (a b c : List Val), cs.binary → a.length = cs.length → b.length = cs.length →
    c.length = cs.length → keySpec cs a b ≠ .gt → keySpec cs b c ≠ .gt → keySpec cs a c ≠ .gt
  | [], _, _, _, _, _, _, _, _, _ => by simp [keySpec]
  | (cl, f) :: cs, x :: xs, y :: ys, z :: zs, hb, la, lb, lc, h1, h2 => by
    have hc : cl = .binary := hb (cl, f) (by simp)
    subst hc
    have t := fieldOrder_tp f
    have ih := keySpec_trans cs xs ys zs (fun w hw => hb w (by simp [hw])) (by simpa using la) (by simpa using lb)
      (by simpa using lc)
    simp only [keySpec] at *
    cases e1 : fieldOrder .binary f x y <;> cases e2 : fieldOrder .binary f y z <;> simp only [e1, e2] at h1 h2 <;>
      simp at h1 h2
    all_goals first
      | (have h := t.lt_le (c := z) e1 (by simp [e2]); simp [h])
      | (have h := t.le_lt (a := x) (by simp [e1]) e2; simp [h])
      | (have h := t.eq_eq e1 e2; simp [h]; exact ih h1 h2)
  | (_, _) :: _, [], _, _, _, la, _, _, _, _ => by simp at la
  | (_, _) :: _, _ :: _, [], _, _, _, lb, _, _, _ => by simp at lb
  | (_, _) :: _, _ :: _, _ :: _, [], _, _, _, lc, _, _ => by simp at lc

/-! ## qv_sort, as written

`qv_sort` sorts the indices 0..n-1 of the sorter's rows: for w = 1, 2, 4, ... while w < n, merge each pair of runs
[lo, lo+w) and [lo+w, lo+2w) (clamped to n), taking the left run's index while `qv_keycmp(left, right) <= 0`. -/

/-- One pass at width w over the index array (`merge` is the C loop: the left on `le`, then the rest of each). -/
def mergePass (le : Nat → Nat → Bool) (w : Nat) (xs : List Nat) : List Nat :=
  if _h : xs = [] ∨ w = 0 then xs
  else List.merge (xs.take w) ((xs.drop w).take w) le ++ mergePass le w (xs.drop (2 * w))
termination_by xs.length
decreasing_by
  have : xs ≠ [] := fun e => _h (Or.inl e)
  have : 0 < xs.length := List.length_pos_iff.mpr this
  simp only [List.length_drop]; omega

/-- `for (w = 1; w < n; w *= 2)`, with fuel n (2^n ≥ n passes are never needed). -/
def qvSortLoop (le : Nat → Nat → Bool) (n : Nat) : Nat → Nat → List Nat → List Nat
  | 0, _, ix => ix
  | f + 1, w, ix => if w < n then qvSortLoop le n f (2 * w) (mergePass le w ix) else ix

def qvSort (le : Nat → Nat → Bool) (n : Nat) : List Nat := qvSortLoop le n n 1 (List.range n)

section
variable (le : Nat → Nat → Bool)

/-- The order the sort actually produces: the comparator, then the original position. -/
def L (i j : Nat) : Bool := List.zipIdxLE le (i, i) (j, j)

theorem merge_cross : ∀ (l1 l2 : List Nat), (∀ x ∈ l1, ∀ y ∈ l2, x < y) → List.merge l1 l2 le = List.merge l1 l2 (L le)
  | [], _, _ => by simp
  | _ :: _, [], _ => by simp
  | x :: xs, y :: ys, h => by
    rw [List.cons_merge_cons, List.cons_merge_cons]
    have hxy : L le x y = le x y := by
      have := h x (by simp) y (by simp)
      simp only [L, List.zipIdxLE]; split <;> simp_all; omega
    rw [hxy]
    split
    · rw [merge_cross xs (y :: ys) (fun a ha b hb => h a (by simp [ha]) b hb)]
    · rw [merge_cross (x :: xs) ys (fun a ha b hb => h a ha b (by simp [hb]))]

/-- Runs of width w (all but the last exactly w, none empty). -/
def Shaped (w : Nat) : List (List Nat) → Prop
  | [] => True
  | [b] => 0 < b.length ∧ b.length ≤ w
  | b :: c :: bs => b.length = w ∧ Shaped w (c :: bs)

def pairMerge : List (List Nat) → List (List Nat)
  | b :: c :: bs => List.merge b c le :: pairMerge bs
  | bs => bs

theorem mergePass_flatten (w : Nat) (hw : 0 < w) : ∀ bs : List (List Nat), Shaped w bs →
    mergePass le w bs.flatten = (pairMerge le bs).flatten
  | [], _ => by simp [mergePass, pairMerge]
  | [b], ⟨h1, h2⟩ => by
    rw [mergePass]
    have hne : ¬ (b = [] ∨ w = 0) := by
      intro h; rcases h with h | h
      · subst h; simp at h1
      · omega
    simp only [List.flatten_cons, List.flatten_nil, List.append_nil, hne, ↓reduceDIte, pairMerge]
    rw [List.take_of_length_le h2, List.drop_eq_nil_of_le h2, List.drop_eq_nil_of_le (by omega)]
    simp [mergePass]
  | [b, c], ⟨h1, h2, h3⟩ => by
    rw [mergePass]
    have hne : ¬ ((b ++ c) = [] ∨ w = 0) := by intro h; rcases h with h | h <;> simp_all
    simp only [List.flatten_cons, List.flatten_nil, List.append_nil, hne, ↓reduceDIte, pairMerge]
    rw [List.take_left' h1, List.drop_left' h1, List.take_of_length_le h3,
      List.drop_eq_nil_of_le (by simp; omega)]
    simp [mergePass]
  | b :: c :: d :: bs, ⟨h1, h2, hs⟩ => by
    rw [mergePass]
    have hne : ¬ ((b :: c :: d :: bs).flatten = [] ∨ w = 0) := by
      intro h; rcases h with h | h
      · simp at h; rw [h.1] at h1; simp at h1; omega
      · omega
    simp only [List.flatten_cons] at hne
    simp only [hne, ↓reduceDIte, pairMerge, List.flatten_cons]
    rw [List.take_left' h1, List.drop_left' h1, List.take_left' h2,
      show 2 * w = b.length + c.length by omega, ← List.drop_drop, List.drop_left' rfl, List.drop_left' rfl]
    have := mergePass_flatten w hw (d :: bs) hs
    simp only [List.flatten_cons] at this
    rw [this]

theorem shaped_pairMerge (w : Nat) : ∀ bs : List (List Nat), Shaped w bs → Shaped (2 * w) (pairMerge le bs)
  | [], _ => by simp [pairMerge, Shaped]
  | [b], ⟨h1, h2⟩ => by simp [pairMerge, Shaped]; omega
  | [b, c], ⟨h1, h2, h3⟩ => by simp [pairMerge, Shaped]; omega
  | b :: c :: d :: bs, ⟨h1, h2, hs⟩ => by
    have ih := shaped_pairMerge w (d :: bs) hs
    show Shaped (2 * w) (List.merge b c le :: pairMerge le (d :: bs))
    cases hp : pairMerge le (d :: bs) with
    | nil => cases bs <;> simp [pairMerge] at hp
    | cons e es => rw [hp] at ih; exact ⟨by simp; omega, ih⟩

/-- The invariant: every run sorted by `L`, and every index in a run below every index in a later one. -/
structure RunInv (bs : List (List Nat)) : Prop where
  sorted : ∀ b ∈ bs, b.Pairwise (fun i j => L le i j = true)
  ordered : bs.Pairwise (fun b c => ∀ x ∈ b, ∀ y ∈ c, x < y)

theorem pairMerge_mem : ∀ (bs : List (List Nat)) (b : List Nat), b ∈ pairMerge le bs →
    ∃ c ∈ bs, ∃ d, (d = [] ∨ d ∈ bs) ∧ ∀ x, x ∈ b ↔ x ∈ c ∨ x ∈ d
  | [], _, h => by simp [pairMerge] at h
  | [c], b, h => by simp [pairMerge] at h; exact ⟨c, by simp, [], by simp, by simp [h]⟩
  | c :: d :: bs, b, h => by
    simp only [pairMerge, List.mem_cons] at h
    rcases h with rfl | h
    · exact ⟨c, by simp, d, by simp, fun x => List.mem_merge⟩
    · obtain ⟨c', hc', d', hd', hx⟩ := pairMerge_mem bs b h
      exact ⟨c', by simp [hc'], d', by rcases hd' with h | h <;> simp [h], hx⟩

theorem runInv_pairMerge (trans : ∀ a b c, L le a b → L le b c → L le a c) (total : ∀ a b, L le a b || L le b a) :
    ∀ bs : List (List Nat), RunInv le bs → RunInv le (pairMerge le bs)
  | [], h => by simpa [pairMerge] using h
  | [b], h => by simpa [pairMerge] using h
  | b :: c :: bs, ⟨hs, ho⟩ => by
    have ho' := List.pairwise_cons.mp ho
    have ho'' := List.pairwise_cons.mp ho'.2
    have ih := runInv_pairMerge trans total bs ⟨fun x hx => hs x (by simp [hx]), ho''.2⟩
    have cross : ∀ x ∈ b, ∀ y ∈ c, x < y := ho'.1 c (by simp)
    refine ⟨?_, ?_⟩
    · intro m hm
      simp only [pairMerge, List.mem_cons] at hm
      rcases hm with rfl | hm
      · rw [merge_cross le b c cross]
        exact List.pairwise_merge trans total b c (hs b (by simp)) (hs c (by simp))
      · exact ih.1 m hm
    · simp only [pairMerge]
      refine List.Pairwise.cons ?_ ih.2
      intro m hm x hx y hy
      obtain ⟨c', hc', d', hd', hmy⟩ := pairMerge_mem le bs m hm
      rw [List.mem_merge] at hx
      have hy' := (hmy y).mp hy
      have later : ∀ z ∈ b ++ c, ∀ e ∈ bs, ∀ y ∈ e, z < y := by
        intro z hz e he y hy
        rcases List.mem_append.mp hz with hz | hz
        · exact ho'.1 e (by simp [he]) z hz y hy
        · exact ho''.1 e he z hz y hy
      rcases hy' with hy' | hy'
      · exact later x (by rcases hx with h | h <;> simp [h]) c' hc' y hy'
      · rcases hd' with rfl | hd'
        · simp at hy'
        · exact later x (by rcases hx with h | h <;> simp [h]) d' hd' y hy'

theorem perm_pairMerge : ∀ bs : List (List Nat), (pairMerge le bs).flatten.Perm bs.flatten
  | b :: c :: bs => by
    simp only [pairMerge, List.flatten_cons, ← List.append_assoc]
    exact List.Perm.append (List.merge_perm_append le) (perm_pairMerge bs)
  | [] => by simp [pairMerge]
  | [_] => by simp [pairMerge]

theorem shaped_head (w : Nat) (hw : 0 < w) (c : List Nat) (rest : List (List Nat)) (h : Shaped w (c :: rest)) :
    0 < c.length := by
  cases rest with
  | nil => exact h.1
  | cons _ _ => rw [h.1]; exact hw

theorem shaped_one (w n : Nat) (hw : 0 < w) (bs : List (List Nat)) (hs : Shaped w bs) (hl : bs.flatten.length = n)
    (hn : n ≤ w) : bs.length ≤ 1 := by
  match bs, hs with
  | [], _ => simp
  | [_], _ => simp
  | b :: c :: rest, ⟨h1, h2⟩ =>
    exfalso
    have := shaped_head w hw c rest h2
    simp at hl; omega

theorem qvSortLoop_runs (trans : ∀ a b c, L le a b → L le b c → L le a c) (total : ∀ a b, L le a b || L le b a)
    (n : Nat) : ∀ (f w : Nat) (bs : List (List Nat)), 0 < w → n ≤ w * 2 ^ f → Shaped w bs → RunInv le bs →
      bs.flatten.length = n → ∃ cs, qvSortLoop le n f w bs.flatten = cs.flatten ∧ cs.length ≤ 1 ∧ RunInv le cs ∧
        cs.flatten.Perm bs.flatten := by
  intro f
  induction f with
  | zero =>
    intro w bs hw hn hs hr hl
    exact ⟨bs, rfl, shaped_one w n hw bs hs hl (by simpa using hn), hr, List.Perm.refl _⟩
  | succ f ih =>
    intro w bs hw hn hs hr hl
    simp only [qvSortLoop]
    split
    · rw [mergePass_flatten le w hw bs hs]
      obtain ⟨cs, h1, h2, h3, h4⟩ := ih (2 * w) (pairMerge le bs) (by omega) (by rw [Nat.pow_succ] at hn; grind)
        (shaped_pairMerge le w bs hs) (runInv_pairMerge le trans total bs hr)
        (by rw [(perm_pairMerge le bs).length_eq, hl])
      exact ⟨cs, h1, h2, h3, h4.trans (perm_pairMerge le bs)⟩
    · exact ⟨bs, rfl, shaped_one w n hw bs hs hl (by omega), hr, List.Perm.refl _⟩

/-- **qv_sort sorts by the comparator, ties in their original order**: its index list is a permutation of 0..n-1
sorted by `L` (the comparator, then the position). -/
theorem qvSort_sorted (trans : ∀ a b c, L le a b → L le b c → L le a c) (total : ∀ a b, L le a b || L le b a)
    (n : Nat) : (qvSort le n).Perm (List.range n) ∧ (qvSort le n).Pairwise (fun i j => L le i j = true) := by
  let bs := (List.range n).map fun i => [i]
  have hflat : bs.flatten = List.range n := by
    simp only [bs]; induction n with
    | zero => simp
    | succ n ih => simp [List.range_succ, List.flatten_append, ih]
  have hs : Shaped 1 bs := by
    simp only [bs]; generalize List.range n = l
    induction l with
    | nil => trivial
    | cons x l ih => cases l with
      | nil => simp [Shaped]
      | cons y l => exact ⟨rfl, ih⟩
  have hr : RunInv le bs := by
    refine ⟨fun b hb => by simp [bs] at hb; obtain ⟨_, _, rfl⟩ := hb; simp, ?_⟩
    simp only [bs, List.pairwise_map]
    refine (List.pairwise_lt_range).imp ?_
    intro a b h x hx y hy; simp at hx hy; omega
  have hn : n ≤ 1 * 2 ^ n := by have := Nat.lt_two_pow_self (n := n); omega
  obtain ⟨cs, h1, h2, h3, h4⟩ := qvSortLoop_runs le trans total n n 1 bs (by omega) hn hs hr (by simp [hflat])
  unfold qvSort
  rw [← hflat, h1]
  refine ⟨by rw [hflat] at h4; rw [hflat]; exact h4, ?_⟩
  match cs, h2, h3 with
  | [], _, _ => simp
  | [c], _, h => simpa using h.sorted c (by simp)

end

theorem L_antisymm (le : Nat → Nat → Bool) (a b : Nat) (h1 : L le a b = true) (h2 : L le b a = true) : a = b := by
  simp only [L, List.zipIdxLE] at h1 h2
  split at h1 <;> split at h2 <;> simp_all <;> (try split at h1) <;> (try simp_all) <;> omega

theorem zipIdx_range {α} (l : List α) (f : Nat → α) (hf : ∀ i (h : i < l.length), f i = l[i]) :
    (List.range l.length).map (fun i => (f i, i)) = l.zipIdx := by
  apply List.ext_getElem (by simp)
  intro i h1 h2
  simp at h1
  simp [hf i h1]

/-- **qvm's sorter is the stable sort by the ORDER BY order**: sorting rows by their key fields (BINARY collations,
any DESC / NULLS FIRST / LAST) through `qv_sort` gives exactly `List.mergeSort` of the rows by that order (whose
stability is `List.mergeSort_zipIdx`: rows with equal keys stay in their insertion order). With `keyCmp_spec`
(qv_keycmp is `keySpec`), this is the chain from ORDER BY to qvm's output order. (`row` reads an index past the end as
the first row; qv_sort never compares one.) -/
theorem qvSort_stable (cs : Keys) (rows : List (List Val)) (hb : cs.binary)
    (hl : ∀ r ∈ rows, r.length = cs.length) :
    let row : Nat → List Val := fun i => rows.getD i (rows.headD [])
    let le' : List Val → List Val → Bool := fun a b => keySpec cs a b != .gt
    (qvSort (fun i j => le' (row i) (row j)) rows.length).map row = rows.mergeSort le' := by
  intro row le'
  cases hr : rows with
  | nil => simp [qvSort, qvSortLoop]
  | cons r0 rs =>
  rw [← hr]
  have rowMem : ∀ i, row i ∈ rows := by
    intro i; simp only [row, List.getD_eq_getElem?_getD]
    by_cases h : i < rows.length
    · simp [List.getElem?_eq_getElem h]
    · rw [List.getElem?_eq_none (by omega)]; simp [hr]
  let le : Nat → Nat → Bool := fun i j => le' (row i) (row j)
  have trN : ∀ a b c, le a b → le b c → le a c := by
    intro a b c h1 h2
    simp only [le, le', bne_iff_ne, ne_eq] at *
    exact keySpec_trans cs _ _ _ hb (hl _ (rowMem a)) (hl _ (rowMem b)) (hl _ (rowMem c)) h1 h2
  have toN : ∀ a b, le a b || le b a := by
    intro a b; simp only [le, le', Bool.or_eq_true, bne_iff_ne, ne_eq]
    rw [keySpec_swap cs (row a) (row b) hb]; cases keySpec cs (row a) (row b) <;> simp [Ordering.swap]
  have trL : ∀ a b c, L le a b → L le b c → L le a c := fun a b c => List.zipIdxLE_trans trN (a, a) (b, b) (c, c)
  have toL : ∀ a b, L le a b || L le b a := fun a b => List.zipIdxLE_total toN (a, a) (b, b)
  obtain ⟨p1, s1⟩ := qvSort_sorted le trL toL rows.length
  have p2 := List.mergeSort_perm (List.range rows.length) (L le)
  have s2 := List.pairwise_mergeSort trL toL (List.range rows.length)
  have heq : qvSort le rows.length = (List.range rows.length).mergeSort (L le) :=
    List.Perm.eq_of_pairwise (fun a b _ _ h1 h2 => L_antisymm le a b h1 h2) s1 s2 (p1.trans p2.symm)
  show (qvSort le rows.length).map row = rows.mergeSort le'
  rw [heq]
  have hm := List.map_mergeSort (l := List.range rows.length) (r := L le) (s := List.zipIdxLE le')
    (f := fun i => (row i, i)) (fun a _ b _ => rfl)
  have hz : (List.range rows.length).map (fun i => (row i, i)) = rows.zipIdx :=
    zipIdx_range rows row (fun i h => by simp [row, List.getD_eq_getElem?_getD, List.getElem?_eq_getElem h])
  rw [hz] at hm
  have := congrArg (List.map Prod.fst) hm
  rw [List.map_map, List.mergeSort_zipIdx] at this
  rw [← this]; rfl

end Turbo

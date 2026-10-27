/-
qvm's top-N sorter (QVC_TOPN, qc/qvm.c and qc/qvm_run.h at e5d68ff): the ephemeral index of SQLite's ORDER BY ... LIMIT
program held as a sorted array. Its IdxInsert is a binary search (a first-entry fast path, then lo/hi halving, an equal
key replacing the entry as a B-tree does); Last is the last entry, Delete removes the cursor's entry.

Proved: the insertion, as written, is ordered insertion into the index (`binIns_eq`), so the array is the index. And
the program SQLite generates around it (pushOntoSorter: insert while fewer than N entries, else compare the new key with
the largest by IdxLE, and delete the largest before inserting a smaller one) keeps exactly the first N rows of the
stable sort (`topN_correct`); the sequence number it puts in each key makes the keys distinct.
-/
import Turbo.Sort

namespace Turbo.TopN

theorem cmp3_trans_nat' {a b c : Nat} (h1 : cmp3 a b ≠ .gt) (h2 : cmp3 b c ≠ .gt) : cmp3 a c ≠ .gt := by
  rw [cmp3_nat_le] at *; omega

variable {α : Type} (cmp : α → α → Ordering)

/-- Strictly increasing (an index's keys are distinct). -/
def Sorted (l : List α) : Prop := l.Pairwise fun a b => cmp a b = .lt

/-- The B-tree's insertion of key x: before the first entry not below x; an equal entry is replaced. -/
def ordIns (x : α) : List α → List α
  | [] => [x]
  | y :: ys =>
    match cmp y x with
    | .lt => y :: ordIns x ys
    | .eq => x :: ys
    | .gt => x :: y :: ys

/-- The binary search, as written: `while (lo < hi) { m = (lo + hi) >> 1; c = xc(rec[m], u); if (c < 0) lo = m + 1;
else { hi = m; eq = !c; } }`, from (lo, hi, eq). -/
def search (l : List α) (x : α) : Nat → Nat → Nat → Bool → Nat × Bool
  | 0, lo, _, eq => (lo, eq)
  | f + 1, lo, hi, eq =>
    if lo < hi then
      let m := (lo + hi) / 2
      let c := cmp (l[m]?.getD x) x
      if c = .lt then search l x f (m + 1) hi eq else search l x f lo m (c == .eq)
    else (lo, eq)

/-- IdxInsert, as written: the fast path `if (hi && (c = xc(rec[0], u)) >= 0) { hi = 0; eq = !c; }`, the search, then
`if (eq && lo < T->n)` replace, else insert at lo (memmove). -/
def binIns (x : α) (l : List α) : List α :=
  let (lo0, hi0, eq0) : Nat × Nat × Bool :=
    match l with
    | [] => (0, 0, false)
    | y :: _ => if cmp y x ≠ .lt then (0, 0, cmp y x == .eq) else (0, l.length, false)
  let (lo, eq) := search cmp l x (l.length + 1) lo0 hi0 eq0
  if eq ∧ lo < l.length then l.set lo x else l.insertIdx lo x

/-! ## The binary search is the B-tree's insertion -/

/-- Where x goes: the number of entries below it. -/
def pos (x : α) (l : List α) : Nat := (l.takeWhile fun y => cmp y x == .lt).length

theorem ordIns_eq (x : α) : ∀ l : List α, ordIns cmp x l =
    if ∃ h : pos cmp x l < l.length, cmp l[pos cmp x l] x = .eq then l.set (pos cmp x l) x else l.insertIdx (pos cmp x l) x
  | [] => by simp [ordIns, pos]
  | y :: ys => by
    have ih := ordIns_eq x ys
    unfold ordIns pos
    cases hc : cmp y x with
    | lt =>
      simp only [List.takeWhile_cons, hc, beq_self_eq_true, ↓reduceIte, List.length_cons, Nat.add_lt_add_iff_right,
        List.getElem_cons_succ]
      rw [ih]; unfold pos
      split <;> simp
    | eq => simp [hc]
    | gt => simp [hc]

theorem pos_spec (x : α) (l : List α) (lo : Nat) (h1 : ∀ i (_hi : i < lo), i < l.length ∧ ∀ (hl : i < l.length), cmp l[i] x = .lt)
    (h2 : ∀ (hl : lo < l.length), cmp l[lo] x ≠ .lt) (hle : lo ≤ l.length) : pos cmp x l = lo := by
  induction l generalizing lo with
  | nil => simp [pos]; simp at hle; omega
  | cons y ys ih =>
    cases lo with
    | zero => have := h2 (by simp); simp at this; simp [pos, this]
    | succ lo =>
      have hy := (h1 0 (by omega)).2 (by simp)
      simp at hy
      simp only [pos, List.takeWhile_cons, hy, beq_self_eq_true, ↓reduceIte, List.length_cons, Nat.add_right_cancel_iff]
      exact ih lo (fun i hi => ⟨by have := (h1 (i + 1) (by omega)).1; simp at this; omega,
        fun hl => by have := (h1 (i + 1) (by omega)).2 (by simp; omega); rw [List.getElem_cons_succ] at this; exact this⟩)
        (fun hl => by have := h2 (by simp; omega); rw [List.getElem_cons_succ] at this; exact this) (by simp at hle; omega)

variable {cmp}

theorem sorted_lt {l : List α} (hs : Sorted cmp l) {i j : Nat} (hij : i < j) (hj : j < l.length) :
    cmp l[i] l[j] = .lt := List.pairwise_iff_getElem.mp hs i j (by omega) hj hij

/-- The search keeps the invariant and ends where x goes. -/
theorem search_spec (t : TP cmp) (l : List α) (hs : Sorted cmp l) (x : α) : ∀ (f lo hi : Nat) (eq : Bool),
    lo ≤ hi → hi ≤ l.length → hi - lo < f →
    (∀ i (_h : i < lo) (hl : i < l.length), cmp l[i] x = .lt) → (∀ i (_h1 : hi ≤ i) (h2 : i < l.length), cmp l[i] x ≠ .lt) →
    (eq = true ↔ ∃ h : hi < l.length, cmp l[hi] x = .eq) →
    search cmp l x f lo hi eq = (pos cmp x l, decide (∃ h : pos cmp x l < l.length, cmp l[pos cmp x l] x = .eq)) := by
  intro f
  induction f with
  | zero => intro lo hi eq _ _ h; omega
  | succ f ih =>
    intro lo hi eq h1 h2 h3 hlo hhi heq
    unfold search
    by_cases hlh : lo < hi
    · simp only [hlh, ↓reduceIte]
      have hm : (lo + hi) / 2 < l.length := by omega
      rw [List.getElem?_eq_getElem hm]; simp only [Option.getD_some]
      by_cases hc : cmp l[(lo + hi) / 2] x = .lt
      · simp only [hc, ↓reduceIte]
        apply ih _ hi eq (by omega) h2 (by omega) _ hhi heq
        intro i hi' hil
        by_cases e : i = (lo + hi) / 2
        · subst e; exact hc
        · by_cases hl : i < lo
          · exact hlo i hl hil
          · exact t.lt_le (sorted_lt hs (by omega) hm) (by simp [hc])
      · simp only [hc, ↓reduceIte]
        apply ih lo _ _ (by omega) (by omega) (by omega) hlo
        · intro i hi1 hi2
          by_cases e : i = (lo + hi) / 2
          · subst e; exact hc
          · intro hlt
            have := t.lt_le (sorted_lt hs (show (lo + hi) / 2 < i by omega) hi2) (show cmp l[i] x ≠ .gt by simp [hlt])
            exact hc this
        · simp [hm]
    · have e : lo = hi := by omega
      subst e
      simp only [hlh, ↓reduceIte]
      have hp : pos cmp x l = lo := pos_spec cmp x l lo (fun i hi => ⟨by omega, fun hl => hlo i hi hl⟩)
        (fun hl => hhi lo (Nat.le_refl _) hl) h2
      rw [hp]
      cases eq <;> simp_all

/-- **IdxInsert on the array is the B-tree's insertion** (into a sorted index; distinct entries). -/
theorem binIns_eq (t : TP cmp) (x : α) (l : List α) (hs : Sorted cmp l) : binIns cmp x l = ordIns cmp x l := by
  rw [ordIns_eq]
  unfold binIns
  have fin : ∀ lo0 hi0 eq0, lo0 ≤ hi0 → hi0 ≤ l.length →
      (∀ i (h : i < lo0) (hl : i < l.length), cmp l[i] x = .lt) → (∀ i (h1 : hi0 ≤ i) (h2 : i < l.length), cmp l[i] x ≠ .lt) →
      (eq0 = true ↔ ∃ h : hi0 < l.length, cmp l[hi0] x = .eq) →
      (let (lo, eq) := search cmp l x (l.length + 1) lo0 hi0 eq0
       if eq ∧ lo < l.length then l.set lo x else l.insertIdx lo x) =
      (if ∃ h : pos cmp x l < l.length, cmp l[pos cmp x l] x = .eq then l.set (pos cmp x l) x
       else l.insertIdx (pos cmp x l) x) := by
    intro lo0 hi0 eq0 a b c d e
    rw [search_spec t l hs x _ lo0 hi0 eq0 a b (by omega) c d e]
    simp only
    by_cases hp : pos cmp x l < l.length
    · split <;> split <;> simp_all
    · have : ¬ ∃ h : pos cmp x l < l.length, cmp l[pos cmp x l] x = .eq := fun ⟨h, _⟩ => hp h
      simp [hp]
  cases l with
  | nil => simp [pos, search]
  | cons y ys =>
    simp only
    by_cases hy : cmp y x ≠ .lt
    · simp only [hy, ne_eq, not_false_eq_true, ↓reduceIte]
      have dd : ∀ i (h1 : 0 ≤ i) (hi : i < (y :: ys).length), cmp (y :: ys)[i] x ≠ .lt := by
        intro i _ hi hlt
        cases i with
        | zero => exact hy (by simpa using hlt)
        | succ i =>
          have := t.lt_le (sorted_lt hs (show 0 < i + 1 by omega) hi) (show cmp (y :: ys)[i + 1] x ≠ .gt by rw [hlt]; simp)
          exact hy (by simpa using this)
      have ee : (cmp y x == .eq) = true ↔ ∃ h : 0 < (y :: ys).length, cmp (y :: ys)[0] x = .eq := by simp
      exact fin 0 0 (cmp y x == .eq) (by omega) (by simp) (fun i h _ => by omega) dd ee
    · simp only [hy, ↓reduceIte]
      exact fin 0 _ false (by omega) (Nat.le_refl _) (fun i h _ => by omega) (fun i h1 h2 => by omega) (by simp)

/-! ## The ORDER BY ... LIMIT N program keeps the first N rows of the stable sort -/

theorem ordIns_perm (x : α) : ∀ l : List α, (∀ y ∈ l, cmp y x ≠ .eq) → (ordIns cmp x l).Perm (x :: l)
  | [], _ => by simp [ordIns]
  | y :: ys, h => by
    unfold ordIns
    cases hc : cmp y x with
    | lt => exact ((ordIns_perm x ys (fun z hz => h z (by simp [hz]))).cons y).trans (List.Perm.swap x y ys)
    | eq => exact absurd hc (h y (by simp))
    | gt => exact List.Perm.refl _

theorem ordIns_sorted (t : TP cmp) (x : α) : ∀ l : List α, Sorted cmp l → (∀ y ∈ l, cmp y x ≠ .eq) →
    Sorted cmp (ordIns cmp x l)
  | [], _, _ => by simp [ordIns, Sorted]
  | y :: ys, hs, h => by
    have hs' := List.pairwise_cons.mp hs
    unfold ordIns
    cases hc : cmp y x with
    | lt =>
      refine List.pairwise_cons.mpr ⟨?_, ordIns_sorted t x ys hs'.2 (fun z hz => h z (by simp [hz]))⟩
      intro z hz
      rcases List.mem_cons.mp ((ordIns_perm x ys (fun z hz => h z (by simp [hz]))).mem_iff.mp hz) with rfl | hz
      · exact hc
      · exact hs'.1 z hz
    | eq => exact absurd hc (h y (by simp))
    | gt =>
      refine List.pairwise_cons.mpr ⟨?_, hs⟩
      intro z hz
      rcases List.mem_cons.mp hz with rfl | hz
      · rw [t.swap]; simp [hc, Ordering.swap]
      · exact t.lt_le (by rw [t.swap, hc]; rfl) (by simp [hs'.1 z hz])

theorem take_ordIns_ge (x : α) : ∀ (N : Nat) (l : List α), N ≤ l.length →
    (∀ i (_h : i < N) (hl : i < l.length), cmp l[i] x = .lt) → (ordIns cmp x l).take N = l.take N
  | 0, _, _, _ => by simp
  | _ + 1, [], hN, _ => by simp at hN
  | M + 1, y :: ys, hN, h => by
    have hy : cmp y x = .lt := by have := h 0 (by omega) (by simp); rwa [List.getElem_cons_zero] at this
    simp only [ordIns, hy, List.take_succ_cons]
    rw [take_ordIns_ge x M ys (by simp at hN; omega)
      (fun i hi hl => by have := h (i + 1) (by omega) (by simp; omega); rwa [List.getElem_cons_succ] at this)]

theorem take_ordIns_lt (t : TP cmp) (x : α) : ∀ (N : Nat) (l : List α), Sorted cmp l → (∀ y ∈ l, cmp y x ≠ .eq) →
    ∀ (hN : 1 ≤ N) (hl : N ≤ l.length), cmp l[N - 1] x = .gt →
      (ordIns cmp x l).take N = ordIns cmp x (l.take (N - 1))
  | 0, _, _, _, hN, _, _ => by omega
  | _ + 1, [], _, _, _, hl, _ => by simp at hl
  | M + 1, y :: ys, hs, hne, _, hl, hg => by
    have hs' := List.pairwise_cons.mp hs
    cases hc : cmp y x with
    | lt =>
      cases M with
      | zero => simp at hg; rw [hc] at hg; cases hg
      | succ M =>
        simp only [ordIns, hc, List.take_succ_cons, Nat.add_sub_cancel]
        have := take_ordIns_lt t x (M + 1) ys hs'.2 (fun z hz => hne z (by simp [hz])) (by omega) (by simp at hl; omega)
          (by have := hg; simp only [Nat.add_sub_cancel, List.getElem_cons_succ] at this; simpa using this)
        rw [this]; simp
    | eq => exact absurd hc (hne y (by simp))
    | gt =>
      cases M with
      | zero => simp [ordIns, hc]
      | succ M => simp [ordIns, hc, List.take_succ_cons]

section Program
variable {β : Type} (kcmp : β → β → Ordering)

/-- The index's order on (key, sequence): the record compare over the ORDER BY fields, then the sequence number. -/
def E (a b : β × Nat) : Ordering :=
  match kcmp a.1 b.1 with
  | .eq => cmp3 a.2 b.2
  | o => o

theorem E_tp (t : TP kcmp) : TP (E kcmp) := by
  constructor
  · intro a b
    unfold E; rw [t.swap a.1 b.1]
    cases kcmp a.1 b.1 <;> simp only [Ordering.swap]
    exact (cmp3_nat_swap a.2 b.2).symm
  · intro a b c h1 h2
    unfold E at *
    cases e1 : kcmp a.1 b.1 <;> cases e2 : kcmp b.1 c.1 <;> simp only [e1, e2] at h1 h2 <;> simp at h1 h2
    · rw [t.lt_le e1 (by simp [e2])]; simp
    · rw [t.lt_le e1 (by simp [e2])]; simp
    · rw [t.le_lt (by simp [e1]) e2]; simp
    · rw [t.eq_eq e1 e2]; exact cmp3_trans_nat' h1 h2

/-- One row of `pushOntoSorter`'s loop (SQLite's select.c) on qvm's array: OP_IfNotZero on the LIMIT counter, else
OP_Last; OP_IdxLE against the new key's ORDER BY fields (skip the row when the largest entry is not above it); OP_Delete
of the largest; then OP_IdxInsert. -/
def step (_N : Nat) (st : Nat × List (β × Nat)) (r : β × Nat) : Nat × List (β × Nat) :=
  if st.1 ≠ 0 then (st.1 - 1, binIns (E kcmp) r st.2)
  else match st.2.getLast? with
    | none => (0, binIns (E kcmp) r st.2)
    | some last => if kcmp last.1 r.1 ≠ .gt then (0, st.2) else (0, binIns (E kcmp) r st.2.dropLast)

/-- All rows, inserted in order: the full index. -/
def insSort (l : List (β × Nat)) : List (β × Nat) := l.foldl (fun S x => ordIns (E kcmp) x S) []

variable {kcmp}

theorem E_new (y x : β × Nat) (h : y.2 < x.2) :
    (E kcmp y x = .lt ↔ kcmp y.1 x.1 ≠ .gt) ∧ (E kcmp y x = .gt ↔ kcmp y.1 x.1 = .gt) ∧ E kcmp y x ≠ .eq := by
  unfold E
  have : cmp3 y.2 x.2 = .lt := cmp3_lt h
  cases kcmp y.1 x.1 <;> simp [this]

theorem foldl_props (t : TP kcmp) : ∀ (l acc pre : List (β × Nat)), Sorted (E kcmp) acc → acc.Perm pre →
    (pre ++ l).Pairwise (fun a b => a.2 < b.2) →
    Sorted (E kcmp) (l.foldl (fun S x => ordIns (E kcmp) x S) acc) ∧
      (l.foldl (fun S x => ordIns (E kcmp) x S) acc).Perm (pre ++ l)
  | [], acc, pre, hs, hp, _ => by simpa using ⟨hs, hp⟩
  | x :: xs, acc, pre, hs, hp, hpw => by
    have hpw' := List.pairwise_append.mp hpw
    have fresh : ∀ y ∈ acc, E kcmp y x ≠ .eq := by
      intro y hy; exact (E_new y x (hpw'.2.2 y (hp.mem_iff.mp hy) x (by simp))).2.2
    simp only [List.foldl_cons]
    have := foldl_props t xs (ordIns (E kcmp) x acc) (pre ++ [x]) (ordIns_sorted (E_tp kcmp t) x acc hs fresh)
      (((ordIns_perm x acc fresh).trans (hp.cons x)).trans (List.perm_append_singleton x pre).symm)
      (by simpa using hpw)
    simpa using this

theorem insSort_props (t : TP kcmp) (l : List (β × Nat)) (h : l.Pairwise (fun a b => a.2 < b.2)) :
    Sorted (E kcmp) (insSort kcmp l) ∧ (insSort kcmp l).Perm l := by
  have := foldl_props t l [] [] (by simp [Sorted]) (List.Perm.refl _) (by simpa using h)
  simpa [insSort] using this

/-- The invariant step: after the rows `seen`, the counter is N minus their number (down to 0) and the array is the
first N of the full index. -/
theorem step_ok (t : TP kcmp) (N : Nat) (hN : 1 ≤ N) (seen : List (β × Nat)) (x : β × Nat)
    (hs : Sorted (E kcmp) (insSort kcmp seen)) (hp : (insSort kcmp seen).Perm seen) (hx : ∀ y ∈ seen, y.2 < x.2) :
    step kcmp N (N - min seen.length N, (insSort kcmp seen).take N) x =
      (N - min (seen.length + 1) N, (ordIns (E kcmp) x (insSort kcmp seen)).take N) := by
  have et := E_tp kcmp t
  let full := insSort kcmp seen
  have hlen : full.length = seen.length := hp.length_eq
  have fresh : ∀ y ∈ full, E kcmp y x ≠ .eq := fun y hy => (E_new y x (hx y (hp.mem_iff.mp hy))).2.2
  have sortedTake : ∀ k, Sorted (E kcmp) (full.take k) := fun k => hs.sublist (List.take_sublist k full)
  unfold step
  by_cases hsmall : seen.length < N
  · have hc : N - min seen.length N ≠ 0 := by omega
    simp only [hc, ne_eq, not_false_eq_true, ↓reduceIte, Prod.mk.injEq]
    refine ⟨by omega, ?_⟩
    have ht : full.take N = full := List.take_of_length_le (by omega)
    show binIns (E kcmp) x (full.take N) = (ordIns (E kcmp) x full).take N
    rw [ht, binIns_eq et x full hs]
    have : (ordIns (E kcmp) x full).length = full.length + 1 := (ordIns_perm x full fresh).length_eq.trans (by simp)
    rw [List.take_of_length_le (by omega)]
  · have hc : N - min seen.length N = 0 := by omega
    simp only [hc, ne_eq, not_true_eq_false, ↓reduceIte, show N - min (seen.length + 1) N = 0 by omega]
    have hS : (full.take N).length = N := by simp; omega
    have hlast : (full.take N).getLast? = some full[N - 1] := by
      rw [List.getLast?_eq_getElem?]; simp [hS]; rw [List.getElem?_take]; simp; omega
    show (match (full.take N).getLast? with
      | none => (0, binIns (E kcmp) x (full.take N))
      | some last => if kcmp last.1 x.1 ≠ .gt then (0, full.take N) else (0, binIns (E kcmp) x (full.take N).dropLast)) =
      (0, (ordIns (E kcmp) x full).take N)
    rw [hlast]
    simp only
    have hlm : full[N - 1] ∈ seen := hp.mem_iff.mp (List.getElem_mem _)
    obtain ⟨elt, egt, _⟩ := E_new full[N - 1] x (hx _ hlm)
    by_cases hk : kcmp full[N - 1].1 x.1 ≠ .gt
    · simp only [hk, ne_eq, not_false_eq_true, ↓reduceIte, Prod.mk.injEq, true_and]
      have hl := elt.mpr hk
      rw [take_ordIns_ge x N full (by omega)]
      intro i hi hl'
      by_cases e : i = N - 1
      · subst e; exact hl
      · have hl2 : (insSort kcmp seen).length = seen.length := hp.length_eq
        exact et.lt_le (sorted_lt hs (show i < N - 1 by omega) (by omega)) (by rw [hl]; simp)
    · simp only [hk, ↓reduceIte, Prod.mk.injEq, true_and]
      simp at hk
      rw [List.dropLast_take (by omega), binIns_eq et x _ (sortedTake _)]
      exact (take_ordIns_lt et x N full hs fresh hN (by omega) (egt.mpr hk)).symm

theorem run_ok (t : TP kcmp) (N : Nat) (hN : 1 ≤ N) : ∀ (l seen : List (β × Nat)),
    (seen ++ l).Pairwise (fun a b => a.2 < b.2) →
    l.foldl (step kcmp N) (N - min seen.length N, (insSort kcmp seen).take N) =
      (N - min (seen ++ l).length N, (insSort kcmp (seen ++ l)).take N)
  | [], seen, _ => by simp
  | x :: xs, seen, hp => by
    have hp' := List.pairwise_append.mp hp
    obtain ⟨hs, hperm⟩ := insSort_props t seen hp'.1
    simp only [List.foldl_cons]
    rw [step_ok t N hN seen x hs hperm (fun y hy => hp'.2.2 y hy x (by simp))]
    have hins : insSort kcmp (seen ++ [x]) = ordIns (E kcmp) x (insSort kcmp seen) := by
      simp [insSort, List.foldl_append]
    have := run_ok t N hN xs (seen ++ [x]) (by simpa using hp)
    rw [hins] at this
    simp only [List.length_append, List.length_singleton, List.append_assoc, List.cons_append, List.nil_append] at this
    rw [this]
    simp [List.length_append]

theorem zipIdx_pairwise {γ} (rows : List γ) : rows.zipIdx.Pairwise (fun a b => a.2 < b.2) := by
  rw [List.pairwise_iff_getElem]
  intro i j hi hj hij
  simp [List.getElem_zipIdx]; omega

/-- **The ORDER BY ... LIMIT N program, run on qvm's array, returns the first N rows of the stable sort** by the ORDER
BY order (`List.mergeSort`, stable by `List.mergeSort_zipIdx`), for any comparator that is a total preorder (such as
`keySpec` over BINARY collations, `keySpec_trans`). Rows are numbered by OP_Sequence in arrival order. -/
theorem topN_correct (t : TP kcmp) (N : Nat) (hN : 1 ≤ N) (rows : List β) :
    ((rows.zipIdx).foldl (step kcmp N) (N, [])).2.map Prod.fst =
      (rows.mergeSort (fun a b => kcmp a b != .gt)).take N := by
  let le : β → β → Bool := fun a b => kcmp a b != .gt
  have h0 := run_ok t N hN rows.zipIdx [] (by simpa using zipIdx_pairwise rows)
  simp only [List.length_nil, Nat.zero_min, Nat.sub_zero, List.nil_append] at h0
  rw [show insSort kcmp ([] : List (β × Nat)) = [] from rfl, List.take_nil] at h0
  rw [h0]
  simp only
  obtain ⟨hs, hperm⟩ := insSort_props t rows.zipIdx (zipIdx_pairwise rows)
  have trN : ∀ a b c, le a b → le b c → le a c := by
    intro a b c h1 h2; simp only [le, bne_iff_ne, ne_eq] at *; exact t.trans a b c h1 h2
  have toN : ∀ a b, le a b || le b a := by
    intro a b; simp only [le, Bool.or_eq_true, bne_iff_ne, ne_eq]; rw [t.swap a b]
    cases kcmp a b <;> simp [Ordering.swap]
  have rel : ∀ a b, E kcmp a b = .lt → List.zipIdxLE le a b = true := by
    intro a b h
    unfold E at h
    simp only [List.zipIdxLE, le, bne_iff_ne, ne_eq]
    cases hk : kcmp a.1 b.1 <;> simp only [hk] at h <;> simp [t.swap a.1 b.1, hk, Ordering.swap] at *
    · exact Nat.le_of_lt (by unfold cmp3 at h; split at h <;> (try split at h) <;> simp_all)
  have hm : (insSort kcmp rows.zipIdx) = rows.zipIdx.mergeSort (List.zipIdxLE le) := by
    apply List.Perm.eq_of_pairwise (le := fun a b => List.zipIdxLE le a b = true)
    · intro a b ha hb h1 h2
      obtain ⟨a1, a2⟩ := a; obtain ⟨b1, b2⟩ := b
      have ma := List.mem_zipIdx' (hperm.mem_iff.mp ha)
      have mb := List.mem_zipIdx' ((List.mergeSort_perm _ _).mem_iff.mp hb)
      have : a2 = b2 := by
        simp only [List.zipIdxLE] at h1 h2
        split at h1 <;> split at h2 <;> simp_all <;> (try split at h1) <;> (try simp_all) <;> omega
      subst this
      simp only [Prod.mk.injEq, and_true]
      rw [ma.2, mb.2]
    · exact hs.imp (fun h => rel _ _ h)
    · exact List.pairwise_mergeSort (List.zipIdxLE_trans trN) (List.zipIdxLE_total toN) _
    · exact hperm.trans (List.mergeSort_perm _ _).symm
  rw [hm, List.map_take, List.mergeSort_zipIdx]

end Program

end Turbo.TopN

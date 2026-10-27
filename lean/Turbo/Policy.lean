/-
The specialisation policy (qvm's type feedback and regions, qc/qvm.c; the tier choice qc_adapt on the spec-policy
branch, b383531): feedback only widens, a region node is re-specialised at most once, and qc_adapt parks a plan at
most 11 times, re-measuring at growing intervals.
-/
namespace Turbo.Policy

/-! ## Feedback masks (QV_FB_*): the classes a site has seen, joined with `|=` -/

structure Mask where
  null : Bool
  int : Bool
  real : Bool
  text : Bool
  blob : Bool
  deriving DecidableEq, Repr

namespace Mask

def bot : Mask := ⟨false, false, false, false, false⟩
def join (a b : Mask) : Mask := ⟨a.null || b.null, a.int || b.int, a.real || b.real, a.text || b.text, a.blob || b.blob⟩
def le (a b : Mask) : Prop := join a b = b
def card (a : Mask) : Nat := a.null.toNat + a.int.toNat + a.real.toNat + a.text.toNat + a.blob.toNat

instance : DecidableRel le := fun a b => inferInstanceAs (Decidable (join a b = b))

theorem join_comm (a b : Mask) : join a b = join b a := by
  cases a; cases b; simp [join, Bool.or_comm]
theorem join_assoc (a b c : Mask) : join (join a b) c = join a (join b c) := by
  cases a; cases b; cases c; simp [join, Bool.or_assoc]
theorem join_idem (a : Mask) : join a a = a := by cases a; simp [join]
theorem le_join (a b : Mask) : le a (join a b) := by
  cases a; cases b; simp only [le, join, ← Bool.or_assoc, Bool.or_self]
theorem card_le (a : Mask) : a.card ≤ 5 := by
  cases a with | mk n i r t b => cases n <;> cases i <;> cases r <;> cases t <;> cases b <;> decide

/-- A strict widening adds a class. -/
theorem card_lt_of_lt (a b : Mask) (h : le a b) (hne : a ≠ b) : a.card < b.card := by
  cases a with | mk n i r t bl => cases b with | mk n' i' r' t' bl' =>
  simp only [le, join, Mask.mk.injEq] at h
  simp only [ne_eq, Mask.mk.injEq] at hne
  simp only [card]
  cases n <;> cases i <;> cases r <;> cases t <;> cases bl <;> cases n' <;> cases i' <;> cases r' <;> cases t' <;>
    cases bl' <;> simp_all

/-- The feedback after a run: every value the site saw joined in. -/
def observe (m : Mask) (seen : List Mask) : Mask := seen.foldl join m

/-- **Feedback only widens.** -/
theorem observe_widens (m : Mask) (seen : List Mask) : le m (observe m seen) := by
  induction seen generalizing m with
  | nil => simp [observe, le, join_idem]
  | cons x xs ih =>
    simp only [observe, List.foldl] at *
    have h1 := le_join m x; have h2 := ih (join m x)
    simp only [le] at *
    rw [← h2, ← join_assoc, h1]

theorem chain_card (l : List Mask) (hl : l.Pairwise (fun a b => le a b ∧ a ≠ b)) :
    ∀ x y, l.head? = some x → l.getLast? = some y → l.length + x.card ≤ y.card + 1 := by
  induction l with
  | nil => simp
  | cons a t ih =>
    intro x y hx hy
    simp at hx; subst hx
    cases t with
    | nil => simp at hy; subst hy; simp; omega
    | cons b t' =>
      have hp := List.pairwise_cons.mp hl
      have hab := hp.1 b (by simp)
      have h1 := card_lt_of_lt _ b hab.1 hab.2
      have h2 := ih hp.2 b y (by simp) (by rw [List.getLast?_cons_cons] at hy; exact hy)
      simp only [List.length_cons] at *; omega

/-- **A site's feedback changes at most 5 times** (the lattice has height 5), however many values it sees: a chain of
strict widenings has at most 6 masks. -/
theorem widenings_bounded (chain : List Mask) (h : chain.Pairwise (fun a b => le a b ∧ a ≠ b)) :
    chain.length ≤ 6 := by
  cases chain with
  | nil => simp
  | cons a t =>
    cases hy : (a :: t).getLast? with
    | none => simp at hy
    | some y =>
      have := chain_card _ h a y (by simp) hy
      have := card_le y; omega

end Mask

open Mask

/-! ## Which feedback a region speculates on (qv_rg_build, qv_fb_num on spec-policy) -/

def M (n i r t b : Bool) : Mask := ⟨n, i, r, t, b⟩

/-- The documented lattice: int → int|real|null → any. -/
inductive Level where
  | int | num | any
  deriving DecidableEq, Repr

def Level.rank : Level → Nat | .int => 0 | .num => 1 | .any => 2

def level (m : Mask) : Level :=
  if !m.null && !m.real && !m.text && !m.blob then .int
  else if !m.text && !m.blob then .num
  else .any

/-- **The level is monotone in the feedback**: more classes seen never give a more specialised level. -/
theorem level_mono (a b : Mask) (h : le a b) : (level a).rank ≤ (level b).rank := by
  cases a with | mk n i r t bl => cases b with | mk n' i' r' t' bl' =>
  simp only [le, join, Mask.mk.injEq] at h
  cases n <;> cases i <;> cases r <;> cases t <;> cases bl <;> cases n' <;> cases i' <;> cases r' <;> cases t' <;>
    cases bl' <;> simp_all [level, Level.rank]

/-- qv_fb_num: a region Column speculates (RG_COLI) on numbers and NULL with at least one number. -/
def fbNum (m : Mask) : Bool :=
  m != Mask.bot && !m.text && !m.blob && m != M true false false false false

/-- **Finding (design, not a wrong result): the speculation choice is not monotone at the bottom.** A Column whose
feedback is only NULL gets the generic node, and one that has also seen an integer gets the speculated one: more
feedback, more specialisation. It is harmless as the code stands (regions are built once, at the third run, and
rg_coli handles every serial type 0-9 itself), but a rebuild of regions from later feedback would not be one-way. -/
theorem fbNum_not_antitone : ∃ a b : Mask, le a b ∧ fbNum a = false ∧ fbNum b = true :=
  ⟨M true false false false false, M true true false false false, by decide, by decide, by decide⟩

/-- Within the lattice, fbNum speculates exactly on levels int and num (minus the empty and the NULL-only mask). -/
theorem fbNum_level (m : Mask) : fbNum m = true ↔
    (level m ≠ .any ∧ m ≠ Mask.bot ∧ m ≠ M true false false false false) := by
  cases m with | mk n i r t b =>
  cases n <;> cases i <;> cases r <;> cases t <;> cases b <;> decide

/-! ## Region nodes: rg_coli → rg_col, rg_cmpi → rg_cmp, one way -/

inductive Node where
  | spec      -- RG_COLI / RG_CMPI
  | generic   -- RG_COL / RG_CMP
  deriving DecidableEq, Repr

/-- One execution of a node on an input the speculation does (`true`) or does not cover. A miss rewrites the node's
handler to the generic one (`n->h = L[RG_COL]`); nothing rewrites it back. -/
def stepNode : Node → Bool → Node
  | .spec, true => .spec
  | .spec, false => .generic
  | .generic, _ => .generic

def widenCount : Node → List Bool → Nat
  | _, [] => 0
  | n, x :: xs => (if stepNode n x ≠ n then 1 else 0) + widenCount (stepNode n x) xs

theorem generic_stays : ∀ xs, widenCount .generic xs = 0
  | [] => rfl
  | x :: xs => by simp [widenCount, stepNode, generic_stays xs]

/-- **A region node is re-specialised at most once**, whatever its inputs. -/
theorem widen_once (n : Node) (xs : List Bool) : widenCount n xs ≤ 1 := by
  induction xs generalizing n with
  | nil => simp [widenCount]
  | cons x xs ih =>
    cases n <;> cases x <;> simp [widenCount, stepNode, generic_stays] <;> exact ih .spec

/-! ## The tier choice: qc_adapt (spec-policy, b383531)

The timings are abstracted as the observations each execution produces; the state is QcAdapt's, with C's `~0u` (stay
parked) as `none`. Counters are modelled as unbounded naturals; the 32-bit wrap is discussed below. -/

inductive St where
  | learn | keep | park
  deriving DecidableEq, Repr

structure A where
  n : Nat
  next : Option Nat
  st : St
  R : Nat
  K : Nat
  nq : Nat
  ni : Nat
  deriving DecidableEq, Repr

def A.init : A := ⟨0, some 0, .learn, 0, 0, 0, 0⟩

/-- What an execution observes. `cheap`: the timed plan run was under QC_ADAPT_MIN_US; `clear`: two interpreter runs
both over 1.25 x the slowest plan run; `faster`: the interpreter's median 5 % faster and every interpreter run under the
plan's median. -/
structure Obs where
  planFails : Bool
  interpFails : Bool
  cheap : Bool
  clear : Bool
  faster : Bool

def WARM : Nat := 3

/-- What a step did: `parked` when it parked the plan, `timed` when it timed a run (plan or interpreter). -/
structure Out where
  parked : Bool
  timed : Bool

/-- A learning step's outcome. -/
inductive Dec where
  | plan               -- a timed plan run
  | interp (ni : Nat)  -- a timed interpreter run, the new count
  | cheapKeep          -- the first timed plan run was cheap: kept
  | keep               -- decided: the plan stays
  | park               -- decided: the interpreter takes the statement
  deriving DecidableEq, Repr

/-- The learning decision from (nq, ni): `none` when the timed run fell back (nothing is counted). -/
def learnDec (nq ni : Nat) (o : Obs) : Option Dec :=
  if nq > ni then
    if o.interpFails then none
    else
      let clear := ni + 1 = 2 ∧ o.clear = true
      let ni' := if clear then 4 else ni + 1
      if ni' = 4 then some (if o.faster = true ∧ ¬ clear then .park else .keep) else some (.interp ni')
  else if o.planFails then none
  else if nq = 0 ∧ o.cheap = true then some .cheapKeep
  else some .plan

def applyDec (s : A) : Option Dec → A × Out
  | none => (s, ⟨false, false⟩)
  | some .plan => ({ s with nq := s.nq + 1 }, ⟨false, true⟩)
  | some (.interp ni) => ({ s with ni := ni }, ⟨false, true⟩)
  | some .cheapKeep => ({ s with st := .keep, next := some (s.n + 256) }, ⟨false, true⟩)
  | some .keep =>
    ({ s with ni := 4, st := .keep, next := some (s.n + 256 * 2 ^ (min s.K 8)), K := min (s.K + 1) 255 }, ⟨false, true⟩)
  | some .park =>
    let R := min (s.R + 1) 255
    ({ s with ni := 4, st := .park, R := R, next := if R > 10 then none else some (s.n + 64 * 2 ^ R) }, ⟨true, true⟩)

def waiting (s : A) : Bool := match s.next with | none => true | some nx => decide (s.n < nx)

/-- qc_adapt, transcribed: count the execution; parked or kept until `next`; then learning (after the warm-up). -/
def step (s0 : A) (o : Obs) : A × Out :=
  let s := { s0 with n := s0.n + 1 }
  if s.st ≠ .learn ∧ waiting s = true then (s, ⟨false, false⟩)
  else
    let s := if s.st ≠ .learn then { s with st := .learn, nq := 0, ni := 0 } else s
    if s.n ≤ WARM then (s, ⟨false, false⟩) else applyDec s (learnDec s.nq s.ni o)

def run : A → List Obs → A × Nat    -- the final state and the number of parks
  | s, [] => (s, 0)
  | s, o :: os => let (s', out) := step s o; let (s'', k) := run s' os; (s'', k + (if out.parked then 1 else 0))

/-- The invariant: R counts the parks (until it saturates at 11), and R > 10 means parked for good. -/
def Inv (s : A) : Prop := s.R ≤ 11 ∧ (s.R > 10 → s.st = .park ∧ s.next = none)

theorem applyDec_R (s : A) (d : Option Dec) (h : s.R ≤ 10) :
    Inv (applyDec s d).1 ∧ ((applyDec s d).2.parked = true → (applyDec s d).1.R = s.R + 1) ∧
    ((applyDec s d).2.parked = false → (applyDec s d).1.R = s.R) := by
  rcases d with _ | d
  · simp [applyDec, Inv]; omega
  · cases d <;> simp [applyDec, Inv] <;> omega

theorem step_inv (s : A) (o : Obs) (h : Inv s) :
    Inv (step s o).1 ∧ ((step s o).2.parked = true → (step s o).1.R = s.R + 1) ∧
    ((step s o).2.parked = false → (step s o).1.R = s.R) := by
  obtain ⟨h1, h2⟩ := h
  by_cases big : s.R > 10
  · obtain ⟨hp, hn⟩ := h2 big
    simp [step, waiting, hp, hn, Inv, h1, big]
  · unfold step
    by_cases hst : s.st = .learn
    · simp only [hst, ne_eq, not_true_eq_false, false_and, ↓reduceIte]
      split
      · simp [Inv]; omega
      · exact applyDec_R _ _ (by simp; omega)
    · by_cases hw : waiting { s with n := s.n + 1 } = true
      · simp [hst, hw, Inv]; omega
      · simp only [ne_eq, hst, not_false_eq_true, hw, and_false, ↓reduceIte, Bool.false_eq_true]
        split
        · simp [Inv]; omega
        · exact applyDec_R _ _ (by simp; omega)

/-- **qc_adapt parks a plan at most 11 times**, then never measures it again (in the unbounded-counter model). -/
theorem parks_bounded (os : List Obs) : (run A.init os).2 ≤ 11 := by
  have gen : ∀ (os : List Obs) (s : A), Inv s → (run s os).2 + s.R ≤ 11 := by
    intro os
    induction os with
    | nil => intro s h; simp [run]; exact h.1
    | cons o os ih =>
      intro s h
      obtain ⟨hi, hp, hn⟩ := step_inv s o h
      have := ih (step s o).1 hi
      simp only [run]
      by_cases pk : (step s o).2.parked = true
      · simp [pk]; have := hp pk; omega
      · simp at pk; simp [pk]; have := hn pk; omega
  have := gen os A.init ⟨by decide, by decide⟩
  simp [A.init] at this; exact this

/-- **The comment says "after 10 parks it stays parked"; the code stays parked after the 11th.** The 10th park still
sets a finite re-measure point (64 · 2^10 = 65536 executions later); the 11th sets `~0u`. Each park's wait is
64 · 2^R after R is incremented, so the first lasts 128 executions, not 64. -/
theorem park_schedule (s : A) :
    (s.R = 9 → (applyDec s (some .park)).1.next = some (s.n + 65536)) ∧
    (s.R = 10 → (applyDec s (some .park)).1.next = none) ∧
    (s.R = 0 → (applyDec s (some .park)).1.next = some (s.n + 128)) := by
  refine ⟨?_, ?_, ?_⟩ <;> intro hr <;> simp [applyDec, hr]

/-- **A learning phase times at most 8 runs** (4 of the plan, 4 of the interpreter) before it keeps or parks the
plan, checked exhaustively over every count and observation: from the invariant (nq = ni or ni + 1, ni ≤ 3), a step
that counts either decides or adds one to nq + ni and keeps the invariant; nq + ni ≤ 7 throughout. -/
def learnOk (nq ni : Nat) (o : Obs) : Bool :=
  match learnDec nq ni o with
  | none => true
  | some .plan => (nq + 1 == ni || nq + 1 == ni + 1) && ni ≤ 3
  | some (.interp ni') => ni' == ni + 1 && (nq == ni' || nq == ni' + 1) && ni' ≤ 3
  | _ => true

theorem learn_progress : ∀ (nq ni : Fin 5) (a b c d e : Bool),
    ((nq.val == ni.val || nq.val == ni.val + 1) && ni.val ≤ 3) = true → learnOk nq.val ni.val ⟨a, b, c, d, e⟩ = true := by
  decide

/-- **Re-measurement intervals grow**: a kept plan is next measured 256 to 65536 executions later; a parked one 128
to 65536 later, or never (R > 10). -/
theorem intervals (s : A) :
    (∃ nx, (applyDec s (some .keep)).1.next = some nx ∧ s.n + 256 ≤ nx ∧ nx ≤ s.n + 65536) ∧
    (applyDec s (some .cheapKeep)).1.next = some (s.n + 256) ∧
    (s.R ≤ 10 → (applyDec s (some .park)).1.next = none ∨
      ∃ nx, (applyDec s (some .park)).1.next = some nx ∧ s.n + 128 ≤ nx ∧ nx ≤ s.n + 65536) := by
  refine ⟨?_, by simp [applyDec], ?_⟩
  · simp only [applyDec, Option.some.injEq, exists_eq_left']
    have : 1 ≤ 2 ^ min s.K 8 := Nat.one_le_two_pow
    have : 2 ^ min s.K 8 ≤ 2 ^ 8 := Nat.pow_le_pow_right (by omega) (Nat.min_le_right _ _)
    omega
  · intro hr
    simp only [applyDec]
    split
    · left; rfl
    · right; simp only [Option.some.injEq, exists_eq_left']
      have r1 : min (s.R + 1) 255 = s.R + 1 := by omega
      rw [r1]
      have : 2 ≤ 2 ^ (s.R + 1) := by
        calc 2 = 2 ^ 1 := rfl
          _ ≤ _ := Nat.pow_le_pow_right (by omega) (by omega)
      have : 2 ^ (s.R + 1) ≤ 2 ^ 10 := Nat.pow_le_pow_right (by omega) (by omega)
      omega

/-! The 32-bit counters. In C, `n` and `next` are `unsigned`: `~0u` is "parked for good" only for the next 2^32
executions (when `n` reaches 0xffffffff, `n < next` fails and the plan is measured again), and `n + (64u << R)` near
2^32 wraps to a small `next`, which just re-measures early. Both are benign: they only cost a measurement. -/
example : ¬ ((0xffffffff : UInt32) < (0xffffffff : UInt32)) := by decide
example : (0xffffff00 : UInt32) + 256 = 0 := by decide

end Turbo.Policy

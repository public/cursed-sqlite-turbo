/-
LIKE and ESCAPE (func.c patternCompare and likeFunc, SQLite 3.54.1), and the LIKE optimisation's index range
(where.c isLikeOrGlob and exprAnalyze).

`patternCompare` is modelled on characters (after sqlite3Utf8Read; a NUL ends both strings, since the function reads
C strings), with its three results: 0 match, 1 no match, 2 "no match, and no suffix of the string matches either"
(SQLITE_NOWILDCARDMATCH, which lets an outer '%' stop searching). Proved: it computes the declarative meaning of the
pattern (`like_spec`), and its 2 is sound (`like_nowild`). The range: a string with the prefix's bytes lies in
[prefix, incremented prefix) (`range_ok`); but a string can match the prefix by its characters without having its
bytes, with an overlong UTF-8 encoding (`range_overlong`): SQLite then answers differently with and without the index.
-/
import Turbo.Compare

namespace Turbo.Like

/-! ## Characters -/

/-- sqlite3Utf8Trans1: the value bits of a lead byte 0xc0..0xff. -/
def trans1 (b : Nat) : Nat :=
  if b < 0xe0 then b - 0xc0 else if b < 0xf0 then b - 0xe0 else if b < 0xf8 then b - 0xf0 else if b < 0xfc then b - 0xf8 else 0

theorem dropWhile_len {α} (f : α → Bool) : ∀ l : List α, (l.dropWhile f).length ≤ l.length
  | [] => by simp
  | x :: l => by
    simp only [List.dropWhile]; split
    · have := dropWhile_len f l; simp; omega
    · simp

/-- sqlite3Utf8Read over a whole byte string: a lead byte takes every continuation byte after it; an overlong value
below 0x80, and a surrogate, read as U+FFFD (so do some other malformed forms; others decode to what they say). -/
def decode : List UInt8 → List Nat
  | [] => []
  | b :: bs =>
    if b.toNat < 0xc0 then b.toNat :: decode bs
    else
      let conts := bs.takeWhile (fun x => x &&& 0xc0 == 0x80)
      let c := conts.foldl (fun c x => c * 64 + (x.toNat &&& 0x3f)) (trans1 b.toNat)
      let c := if c < 0x80 || (c &&& 0xFFFFF800) == 0xD800 then 0xFFFD else c
      c :: decode (bs.dropWhile (fun x => x &&& 0xc0 == 0x80))
  termination_by l => l.length
  decreasing_by all_goals simp_wf; all_goals (have := dropWhile_len (fun x : UInt8 => x &&& 0xc0 == 0x80) bs); all_goals omega

/-- The text patternCompare sees: up to the first NUL. -/
def cstr (s : List UInt8) : List UInt8 := s.takeWhile (· != 0)

/-- The LIKE configuration after likeFunc: the wildcards (0: disabled, when the ESCAPE character is one of them), the
escape (0: none), and the case folding (likeInfoNorm; `PRAGMA case_sensitive_like` gives likeInfoAlt). -/
structure Cfg where
  all : Nat
  one : Nat
  esc : Nat
  nocase : Bool

/-- The three special characters are distinct (likeFunc disables a wildcard the ESCAPE character equals). -/
def Cfg.WF (k : Cfg) : Prop := k.esc ≠ k.all ∧ k.esc ≠ k.one ∧ k.all ≠ k.one

/-- likeFunc's configuration for an ESCAPE character `esc` (0: no ESCAPE clause). -/
def cfgOf (nocase : Bool) (esc : Nat) : Cfg :=
  ⟨if esc = 37 then 0 else 37, if esc = 95 then 0 else 95, esc, nocase⟩

theorem cfgOf_wf (nc : Bool) (e : Nat) : (cfgOf nc e).WF := by
  unfold cfgOf Cfg.WF; simp only; split <;> split <;> omega

def fold (c : Nat) : Nat := if 65 ≤ c ∧ c ≤ 90 then c + 32 else c

/-- A literal pattern character against a string character (the main loop's test). -/
def eqc (k : Cfg) (c c2 : Nat) : Bool := c == c2 || (k.nocase && c < 0x80 && c2 < 0x80 && fold c == fold c2)

/-! ## What a pattern means -/

inductive Tok where
  | all | one | lit (c : Nat) | bad
  deriving DecidableEq, Repr

/-- The pattern's tokens: an escaped character is a literal; an ESCAPE at the end matches nothing. -/
def tokens (k : Cfg) : List Nat → List Tok
  | [] => []
  | c :: p =>
    if c = k.all then .all :: tokens k p
    else if c = k.esc then (match p with | [] => [.bad] | c' :: p' => .lit c' :: tokens k p')
    else if c = k.one then .one :: tokens k p
    else .lit c :: tokens k p

/-- The meaning: '%' any characters, '_' one, a literal one equal (ASCII case-folded under nocase). -/
def tmatch (k : Cfg) : List Tok → List Nat → Bool
  | [], s => s.isEmpty
  | .all :: ts, s => (List.range (s.length + 1)).any fun j => tmatch k ts (s.drop j)
  | .one :: ts, _ :: s => tmatch k ts s
  | .one :: _, [] => false
  | .lit c :: ts, c2 :: s => eqc k c c2 && tmatch k ts s
  | .lit _ :: _, [] => false
  | .bad :: _, _ => false
  termination_by ts s => (ts.length, s.length)
  decreasing_by all_goals simp_wf; all_goals (first | omega | (left; omega))

/-! ## patternCompare, as written -/

mutual
/-- The main loop over the pattern. -/
def pc (k : Cfg) : List Nat → List Nat → Nat
  | [], s => if s.isEmpty then 0 else 1
  | c :: p, s =>
    if c = k.all then star k p s
    else if c = k.esc then
      (match p with
       | [] => 1
       | c' :: p' => match s with | [] => 1 | c2 :: s' => if eqc k c' c2 then pc k p' s' else 1)
    else match s with
      | [] => 1
      | c2 :: s' => if eqc k c c2 || c == k.one then pc k p s' else 1
  termination_by p s => (p.length, 0, s.length)
/-- After a '%': skip '%'s and '_'s (each '_' takes a character), then search for the next literal. -/
def star (k : Cfg) : List Nat → List Nat → Nat
  | [], _ => 0
  | c :: p, s =>
    if c = k.all then star k p s
    else if c = k.one then (match s with | [] => 2 | _ :: s' => star k p s')
    else if c = k.esc then (match p with | [] => 2 | c' :: p' => search k c' p' s)
    else search k c p s
  termination_by p s => (p.length, 1, s.length)
/-- strcspn (ASCII; both cases under nocase) or a character loop: at each occurrence try the rest; a result other
than "no match" is the answer; none left: 2. -/
def search (k : Cfg) (c : Nat) (p : List Nat) : List Nat → Nat
  | [] => 2
  | c2 :: s' =>
    if eqc k c c2 then (let r := pc k p s'; if r ≠ 1 then r else search k c p s')
    else search k c p s'
  termination_by s => (p.length, 2, s.length)
end

/-! ## patternCompare is right -/

theorem tmatch_all (k : Cfg) (ts : List Tok) (s : List Nat) :
    tmatch k (.all :: ts) s = true ↔ ∃ j, tmatch k ts (s.drop j) = true := by
  rw [tmatch]; simp only [List.any_eq_true, List.mem_range]
  constructor
  · rintro ⟨j, _, h⟩; exact ⟨j, h⟩
  · rintro ⟨j, h⟩
    by_cases hj : j ≤ s.length
    · exact ⟨j, by omega, h⟩
    · refine ⟨s.length, by omega, ?_⟩
      have : s.drop j = s.drop s.length := by simp [List.drop_eq_nil_of_le (show s.length ≤ j by omega)]
      rwa [← this]

/-- A no-match-anywhere result for a token list: nothing matches at any suffix. -/
def Nowhere (k : Cfg) (ts : List Tok) (s : List Nat) : Prop := ∀ j, tmatch k ts (s.drop j) = false

theorem drop_succ_cons {α} (x : α) (s : List α) (j : Nat) : (x :: s).drop (j + 1) = s.drop j := rfl

/-- One literal-like step ('_' or a literal): a sub-result of "nowhere" stays "nowhere" for the longer string. -/
theorem nowhere_step (k : Cfg) (t : Tok) (ts : List Tok) (x : Nat) (s : List Nat) (ht : t = .one ∨ ∃ c, t = .lit c)
    (h : Nowhere k ts s) : Nowhere k (t :: ts) (x :: s) := by
  intro j
  cases j with
  | zero =>
    rcases ht with rfl | ⟨c, rfl⟩
    · simp [tmatch]; exact h 0
    · simp [tmatch]; intro _; exact h 0
  | succ j =>
    rw [drop_succ_cons]
    cases hs : s.drop j with
    | nil => rcases ht with rfl | ⟨c, rfl⟩ <;> simp [tmatch]
    | cons y r =>
      have : r = s.drop (j + 1) := by rw [← List.drop_drop, hs]; rfl
      rcases ht with rfl | ⟨c, rfl⟩
      · simp only [tmatch]; rw [this]; exact h (j + 1)
      · simp only [tmatch, Bool.and_eq_false_iff]; right; rw [this]; exact h (j + 1)

theorem tokens_cons (k : Cfg) (c : Nat) (p : List Nat) : tokens k (c :: p) =
    if c = k.all then .all :: tokens k p
    else if c = k.esc then (match p with | [] => [.bad] | c' :: p' => .lit c' :: tokens k p')
    else if c = k.one then .one :: tokens k p else .lit c :: tokens k p := by
  cases p <;> rw [tokens.eq_def]

theorem pc_cons (k : Cfg) (c : Nat) (p s : List Nat) : pc k (c :: p) s =
    if c = k.all then star k p s
    else if c = k.esc then
      (match p with
       | [] => 1
       | c' :: p' => match s with | [] => 1 | c2 :: s' => if eqc k c' c2 then pc k p' s' else 1)
    else match s with
      | [] => 1
      | c2 :: s' => if eqc k c c2 || c == k.one then pc k p s' else 1 := by
  rw [pc.eq_def]

theorem pc_nil (k : Cfg) (s : List Nat) : pc k [] s = if s.isEmpty then 0 else 1 := by rw [pc.eq_def]

theorem star_cons (k : Cfg) (c : Nat) (p s : List Nat) : star k (c :: p) s =
    if c = k.all then star k p s
    else if c = k.one then (match s with | [] => 2 | _ :: s' => star k p s')
    else if c = k.esc then (match p with | [] => 2 | c' :: p' => search k c' p' s)
    else search k c p s := by
  rw [star.eq_def]

theorem star_nil (k : Cfg) (s : List Nat) : star k [] s = 0 := by rw [star.eq_def]

theorem search_cons (k : Cfg) (c : Nat) (p : List Nat) (x : Nat) (s : List Nat) : search k c p (x :: s) =
    if eqc k c x then (if pc k p s ≠ 1 then pc k p s else search k c p s) else search k c p s := by
  rw [search.eq_def]

theorem search_nil (k : Cfg) (c : Nat) (p : List Nat) : search k c p [] = 2 := by rw [search.eq_def]

def PA (k : Cfg) (p : List Nat) : Prop :=
  ∀ s, (pc k p s = 0 ↔ tmatch k (tokens k p) s = true) ∧ pc k p s ≤ 2 ∧ (pc k p s = 2 → Nowhere k (tokens k p) s)
def PB (k : Cfg) (p : List Nat) : Prop :=
  ∀ s, (star k p s = 0 ↔ ∃ j, tmatch k (tokens k p) (s.drop j) = true) ∧ (star k p s = 0 ∨ star k p s = 2)
def PC (k : Cfg) (p : List Nat) : Prop :=
  ∀ c s, (search k c p s = 0 ↔ ∃ j, tmatch k (.lit c :: tokens k p) (s.drop j) = true) ∧
    (search k c p s = 0 ∨ search k c p s = 2)

theorem lit_cons (k : Cfg) (c x : Nat) (ts : List Tok) (s : List Nat) :
    tmatch k (.lit c :: ts) (x :: s) = (eqc k c x && tmatch k ts s) := by simp [tmatch]

theorem PC_of_PA (k : Cfg) (p : List Nat) (ha : PA k p) : PC k p := by
  intro c s
  induction s with
  | nil => simp [search_nil, tmatch]
  | cons x s' ih =>
    obtain ⟨a1, a2, a3⟩ := ha s'
    by_cases he : eqc k c x = true
    · simp only [search_cons, he, ↓reduceIte]
      by_cases r0 : pc k p s' = 0
      · rw [r0]; simp only [ne_eq, Nat.zero_ne_one, not_false_eq_true, ↓reduceIte, true_or, and_true]
        exact ⟨fun _ => ⟨0, by simp [lit_cons, he, a1.mp r0]⟩, fun _ => trivial⟩
      by_cases r1 : pc k p s' = 1
      · rw [r1]; simp only [ne_eq, not_true_eq_false, ↓reduceIte]
        refine ⟨?_, ih.2⟩
        rw [ih.1]
        constructor
        · rintro ⟨j, hj⟩; exact ⟨j + 1, by rwa [drop_succ_cons]⟩
        · rintro ⟨j, hj⟩
          cases j with
          | zero => simp [lit_cons, he] at hj; exact absurd (a1.mpr hj) r0
          | succ j => exact ⟨j, by rwa [drop_succ_cons] at hj⟩
      · have r2 : pc k p s' = 2 := by omega
        rw [r2]; simp only [ne_eq, show (2 : Nat) ≠ 1 by decide, not_false_eq_true, ↓reduceIte,
          show (2 : Nat) ≠ 0 by decide, false_iff, or_true, and_true]
        have := nowhere_step k (.lit c) (tokens k p) x s' (Or.inr ⟨c, rfl⟩) (a3 r2)
        rintro ⟨j, hj⟩; rw [this j] at hj; exact Bool.false_ne_true hj
    · simp only [search_cons, he, Bool.false_eq_true, ↓reduceIte]
      refine ⟨?_, ih.2⟩
      rw [ih.1]
      constructor
      · rintro ⟨j, hj⟩; exact ⟨j + 1, by rwa [drop_succ_cons]⟩
      · rintro ⟨j, hj⟩
        cases j with
        | zero => simp [lit_cons, he] at hj
        | succ j => exact ⟨j, by rwa [drop_succ_cons] at hj⟩

theorem exists_drop_cons (x : Nat) (s : List Nat) (P : List Nat → Prop) :
    (∃ j, P (s.drop j)) ↔ ∃ j, ∃ y r, (x :: s).drop j = y :: r ∧ P r := by
  constructor
  · rintro ⟨j, hj⟩
    by_cases hl : j ≤ s.length
    · refine ⟨j, ?_⟩
      cases j with
      | zero => exact ⟨x, s, by simp, hj⟩
      | succ j =>
        have : j < s.length := by omega
        refine ⟨s[j], s.drop (j + 1), ?_, hj⟩
        rw [drop_succ_cons]; exact List.drop_eq_getElem_cons this
    · refine ⟨s.length, ?_⟩
      have : s.drop j = [] := List.drop_eq_nil_of_le (by omega)
      rw [this] at hj
      cases hs : s.length with
      | zero => exact ⟨x, s, rfl, by rw [List.length_eq_zero_iff.mp hs]; exact hj⟩
      | succ m =>
        refine ⟨s[m]'(by omega), [], ?_, hj⟩
        rw [drop_succ_cons]
        have := List.drop_eq_getElem_cons (l := s) (i := m) (by omega)
        rw [this, List.drop_eq_nil_of_le (by omega)]
  · rintro ⟨j, y, r, hj, hp⟩
    refine ⟨j, ?_⟩
    have : r = (x :: s).drop (j + 1) := by rw [← List.drop_drop, hj]; rfl
    rw [this, drop_succ_cons] at hp; exact hp

theorem step (k : Cfg) (hk : k.WF) (c : Nat) (p : List Nat)
    (ih : ∀ q : List Nat, q.length < (c :: p).length → PA k q ∧ PB k q ∧ PC k q) : PA k (c :: p) ∧ PB k (c :: p) := by
  obtain ⟨w1, w2, w3⟩ := hk
  have w1' := Ne.symm w1; have w2' := Ne.symm w2; have w3' := Ne.symm w3
  have ihp := ih p (by simp)
  constructor
  · intro s
    by_cases ca : c = k.all
    · have tk : tokens k (c :: p) = .all :: tokens k p := by rw [tokens_cons]; simp [ca]
      rw [tk]; simp only [pc_cons, ca, ↓reduceIte]
      obtain ⟨b1, b2⟩ := ihp.2.1 s
      refine ⟨by rw [b1, tmatch_all], by omega, ?_⟩
      intro h2 j
      apply Bool.eq_false_iff.mpr; intro ht
      rw [tmatch_all] at ht; obtain ⟨i, hi⟩ := ht
      rw [List.drop_drop] at hi
      have : star k p s ≠ 2 := by have := b1.mpr ⟨_, hi⟩; omega
      exact this h2
    by_cases ce : c = k.esc
    · have ce' : ¬ c = k.all := ca
      cases p with
      | nil =>
        have tk : tokens k [c] = [.bad] := by rw [tokens_cons]; simp [ce, w1]
        rw [tk]; simp [pc_cons, w1, ce, tmatch]
      | cons c' p' =>
        have tk : tokens k (c :: c' :: p') = .lit c' :: tokens k p' := by rw [tokens_cons]; simp [ce, w1]
        rw [tk]
        have ihp' := (ih p' (by simp; omega)).1
        cases s with
        | nil => simp [pc_cons, w1, ce, tmatch]
        | cons c2 s' =>
          simp only [pc_cons, w1, ce, ↓reduceIte, lit_cons]
          obtain ⟨a1, a2, a3⟩ := ihp' s'
          by_cases he : eqc k c' c2 = true
          · simp only [he, ↓reduceIte, Bool.true_and]
            exact ⟨a1, a2, fun h2 => nowhere_step k (.lit c') _ c2 s' (Or.inr ⟨c', rfl⟩) (a3 h2)⟩
          · simp [he]
    · by_cases co : c = k.one
      · have tk : tokens k (c :: p) = .one :: tokens k p := by rw [tokens_cons]; simp [co, w2', w3']
        rw [tk]
        cases s with
        | nil => simp [pc_cons, ca, ce, tmatch]
        | cons c2 s' =>
          simp only [pc_cons, w2', w3', ↓reduceIte, co, beq_self_eq_true, Bool.or_true]
          obtain ⟨a1, a2, a3⟩ := ihp.1 s'
          simp only [tmatch]
          exact ⟨a1, a2, fun h2 => nowhere_step k .one _ c2 s' (Or.inl rfl) (a3 h2)⟩
      · have tk : tokens k (c :: p) = .lit c :: tokens k p := by rw [tokens_cons]; simp [ca, ce, co]
        rw [tk]
        cases s with
        | nil => simp [pc_cons, ca, ce, tmatch]
        | cons c2 s' =>
          have co' : (c == k.one) = false := by simp [co]
          simp only [pc_cons, ca, ce, ↓reduceIte, co', Bool.or_false, lit_cons]
          obtain ⟨a1, a2, a3⟩ := ihp.1 s'
          by_cases he : eqc k c c2 = true
          · simp only [he, ↓reduceIte, Bool.true_and]
            exact ⟨a1, a2, fun h2 => nowhere_step k (.lit c) _ c2 s' (Or.inr ⟨c, rfl⟩) (a3 h2)⟩
          · simp [he]
  · intro s
    by_cases ca : c = k.all
    · have tk : tokens k (c :: p) = .all :: tokens k p := by rw [tokens_cons]; simp [ca]
      rw [tk]; simp only [star_cons, ca, ↓reduceIte]
      obtain ⟨b1, b2⟩ := ihp.2.1 s
      refine ⟨?_, b2⟩
      rw [b1]
      constructor
      · rintro ⟨j, hj⟩; exact ⟨0, by rw [tmatch_all]; exact ⟨j, by simpa using hj⟩⟩
      · rintro ⟨j, hj⟩; rw [tmatch_all] at hj; obtain ⟨i, hi⟩ := hj; exact ⟨j + i, by rwa [List.drop_drop] at hi⟩
    by_cases co : c = k.one
    · have ce : ¬ c = k.esc := by intro h; exact w2 (h ▸ co)
      have tk : tokens k (c :: p) = .one :: tokens k p := by rw [tokens_cons]; simp [co, w2', w3']
      rw [tk]
      cases s with
      | nil => simp [star_cons, w3', co, tmatch]
      | cons x s' =>
        simp only [star_cons, w3', co, ↓reduceIte]
        obtain ⟨b1, b2⟩ := ihp.2.1 s'
        refine ⟨?_, b2⟩
        rw [b1, exists_drop_cons x s' (fun r => tmatch k (tokens k p) r = true)]
        constructor
        · rintro ⟨j, y, r, h1, h2⟩; exact ⟨j, by rw [h1]; simpa [tmatch] using h2⟩
        · rintro ⟨j, hj⟩
          cases hd : (x :: s').drop j with
          | nil => rw [hd] at hj; simp [tmatch] at hj
          | cons y r => rw [hd] at hj; exact ⟨j, y, r, hd, by simpa [tmatch] using hj⟩
    by_cases ce : c = k.esc
    · cases p with
      | nil =>
        have tk : tokens k [c] = [.bad] := by rw [tokens_cons]; simp [ce, w1]
        rw [tk]; simp [star_cons, w1, w2, ce, tmatch]
      | cons c' p' =>
        have tk : tokens k (c :: c' :: p') = .lit c' :: tokens k p' := by rw [tokens_cons]; simp [ce, w1]
        rw [tk]; simp only [star_cons, w1, w2, ce, ↓reduceIte]
        exact (ih p' (by simp; omega)).2.2 c' s
    · have tk : tokens k (c :: p) = .lit c :: tokens k p := by rw [tokens_cons]; simp [ca, ce, co]
      rw [tk]; simp only [star_cons, ca, co, ce, ↓reduceIte]
      exact ihp.2.2 c s

theorem all_correct (k : Cfg) (hk : k.WF) : ∀ n (p : List Nat), p.length ≤ n → PA k p ∧ PB k p ∧ PC k p := by
  intro n
  induction n with
  | zero =>
    intro p hp
    have : p = [] := List.eq_nil_of_length_eq_zero (by omega)
    subst this
    have ha : PA k [] := by intro s; cases s <;> simp [pc_nil, tokens, tmatch]
    refine ⟨ha, ?_, PC_of_PA k [] ha⟩
    intro s; simp only [star_nil, true_or, and_true, tokens]
    exact ⟨fun _ => ⟨s.length, by simp [tmatch]⟩, fun _ => trivial⟩
  | succ n ih =>
    intro p hp
    cases p with
    | nil =>
      have ha : PA k [] := by intro s; cases s <;> simp [pc_nil, tokens, tmatch]
      refine ⟨ha, ?_, PC_of_PA k [] ha⟩
      intro s; simp only [star_nil, true_or, and_true, tokens]
      exact ⟨fun _ => ⟨s.length, by simp [tmatch]⟩, fun _ => trivial⟩
    | cons c p =>
      have := step k hk c p (fun q hq => ih q (by simp at hp hq; omega))
      exact ⟨this.1, this.2, PC_of_PA k _ this.1⟩

/-- **patternCompare computes the pattern's meaning**: it returns 0 (SQLITE_MATCH) exactly when the string matches the
pattern's tokens. -/
theorem like_spec (k : Cfg) (hk : k.WF) (p s : List Nat) : pc k p s = 0 ↔ tmatch k (tokens k p) s = true :=
  ((all_correct k hk p.length p (Nat.le_refl _)).1 s).1

/-- **Its early exit is sound**: 2 (SQLITE_NOWILDCARDMATCH) only when no suffix of the string matches either, which is
what lets an enclosing '%' stop searching. -/
theorem like_nowild (k : Cfg) (hk : k.WF) (p s : List Nat) (h : pc k p s = 2) : Nowhere k (tokens k p) s :=
  ((all_correct k hk p.length p (Nat.le_refl _)).1 s).2.2 h

/-- likeFunc's result: like(pattern, string [, escape]). -/
def likeFn (nocase : Bool) (esc : Nat) (pat str : List UInt8) : Bool :=
  pc (cfgOf nocase esc) (decode (cstr pat)) (decode (cstr str)) == 0

/-! ## The LIKE optimisation's range -/

/-- exprAnalyze's upper bound: the prefix's last byte incremented, a trailing 0xBF carrying (as 0x80) into the byte
before. -/
def incr : List UInt8 → List UInt8
  | [] => []
  | bs =>
    let rev := bs.reverse
    let n := (rev.takeWhile (· == 0xbf)).length
    let rest := rev.drop n
    if rest.isEmpty then bs   -- (only 0xBF bytes: exprAnalyze increments the first one; not reached from UTF-8)
    else (rest.drop 1).reverse ++ [rest.head! + 1] ++ List.replicate n 0x80

theorem lex_append (p t : List UInt8) : lex p (p ++ t) ≠ .gt := by
  induction p with
  | nil => cases t <;> simp [lex]
  | cons a p ih => simp [lex, UInt8.lt_irrefl, ih]

theorem lex_lt_of_lt (q : List UInt8) (a b : UInt8) (u v : List UInt8) (h : a < b) : lex (q ++ a :: u) (q ++ b :: v) = .lt := by
  induction q with
  | nil => simp [lex, h]
  | cons x q ih => simp [lex, UInt8.lt_irrefl, ih]

/-- **The case-sensitive range holds for byte prefixes**: a string whose bytes start with the prefix P lies in
[P, incr P) under BINARY, when some byte of P before its trailing 0xBF run is below 0xFF (isLikeOrGlob refuses 0xFF). -/
theorem range_ok (q : List UInt8) (a : UInt8) (n : Nat) (t : List UInt8) (ha : a.toNat < 255) :
    let P := q ++ a :: List.replicate n 0xbf
    lex P (P ++ t) ≠ .gt ∧ lex (P ++ t) (q ++ (a + 1) :: List.replicate n 0x80) = .lt := by
  refine ⟨lex_append _ _, ?_⟩
  simp only [List.append_assoc, List.cons_append]
  apply lex_lt_of_lt
  rw [UInt8.lt_iff_toNat_lt, UInt8.toNat_add]; simp; omega

/-- **Finding: an overlong UTF-8 encoding matches a LIKE prefix by its characters but lies outside the range.**
`61 E0 82 80` decodes to 'a', U+0080, like `61 C2 80`, so `x LIKE 'a\u0080%'` is true for it; the range is
['a\u0080', 'a\u0081') = [61 C2 80, 61 C2 81), and 61 E0 82 80 is above it. With an index and case_sensitive_like,
SQLite answers differently than without the index (`NOT INDEXED`). -/
theorem range_overlong :
    likeFn false 0 [0x61, 0xc2, 0x80, 0x25] [0x61, 0xe0, 0x82, 0x80] = true ∧
    lex [0x61, 0xe0, 0x82, 0x80] [0x61, 0xc2, 0x81] = .gt := by
  refine ⟨?_, by decide⟩
  simp (config := { decide := true }) [likeFn, cstr, cfgOf, decode, trans1, pc_cons, star_nil]

end Turbo.Like

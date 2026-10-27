/-
The record format (fileformat2.html §2.1): a varint header size, varint serial types, then the bodies. Modelled:
- OP_Column's reading of a field (vdbe.c, SQLite 3.54.1): the lazy header walk, the corruption test and serialGet;
- qc_decode (qc/qc.c) as written, and the same function with the checks OP_Column makes (`qcDecode true`).
Found: qc_decode accepts records OP_Column reports as corrupt (`qc_decode_lenient`), so a qc plan returns rows where
SQLite returns SQLITE_CORRUPT. Proved: with the missing checks, whatever qc_decode accepts, OP_Column reads the same
values (`qcDecode_sound`).
-/
namespace Turbo.Record

abbrev Bytes := List UInt8

/-- A field value as OP_Column produces it (reals by their bits; NaN reads as NULL). -/
inductive RV where
  | null
  | int (i : Int)
  | real (bits : UInt64)
  | text (s : Bytes)
  | blob (b : Bytes)
  deriving DecidableEq, Repr

/-! ## Varints -/

/-- sqlite3GetVarint at position p: (value, length); `none` when it runs past the end of the bytes. Up to 8 bytes of
7 bits, a 9th byte of 8. -/
def readVar (b : Bytes) (p : Nat) : Option (Nat × Nat) := go 9 0 0
where
  /-- `r` bytes left to read (9 - k). -/
  go : Nat → Nat → Nat → Option (Nat × Nat)
    | 0, _, _ => none
    | r + 1, k, v =>
      match b[p + k]? with
      | none => none
      | some x =>
        if r = 0 then some (v * 256 + x.toNat, k + 1)
        else if x < 0x80 then some (v * 128 + x.toNat, k + 1)
        else go r (k + 1) (v * 128 + (x.toNat - 128))

/-- sqlite3GetVarint32 (and the one-byte getVarint32 macro): values past 32 bits read as 0xffffffff. -/
def readVar32 (b : Bytes) (p : Nat) : Option (Nat × Nat) :=
  (readVar b p).map fun (v, n) => (if v > 0xffffffff then 0xffffffff else v, n)

/-- sqlite3VdbeSerialTypeLen. -/
def slen (t : Nat) : Nat :=
  if t < 12 then [0, 1, 2, 3, 4, 6, 8, 8, 0, 0, 0, 0][t]! else (t - 12) / 2

/-! ## Values -/

def beNat (b : Bytes) : Nat := b.foldl (fun n x => n * 256 + x.toNat) 0

/-- A k-byte big-endian two's complement integer. -/
def beInt (b : Bytes) : Int :=
  let u := beNat b
  if u ≥ 2 ^ (8 * b.length - 1) then (u : Int) - 2 ^ (8 * b.length) else u

def isNaN (bits : UInt64) : Bool := (bits >>> 52) &&& 0x7ff == 0x7ff && bits &&& 0xfffffffffffff != 0

/-- sqlite3VdbeSerialGet of serial type t with the body `d` (its slen t bytes). Types 10 and 11 read as NULL. -/
def serialGet (t : Nat) (d : Bytes) : RV :=
  if t = 0 ∨ t = 10 ∨ t = 11 then .null
  else if t = 8 then .int 0
  else if t = 9 then .int 1
  else if t = 7 then (let x := (beNat d).toUInt64; if isNaN x then .null else .real x)
  else if t ≤ 6 then .int (beInt d)
  else if t % 2 = 1 then .text d else .blob d

def body (b : Bytes) (off len : Nat) : Bytes := (b.drop off).take len

/-! ## OP_Column -/

/-- A field the header walk read: its serial type, body offset, and the walk's state after it. -/
structure Fld where
  t : Nat
  off : Nat
  pos : Nat
  next : Nat
  deriving DecidableEq, Repr, Inhabited

/-- The header walk of OP_Column's do-while: read a serial type at pos, add its length to the body offset, and go on
while fields remain to read (`fuel`: p2 + 1) and pos < hdr. Each field with the state after it; the last is where the
walk stops. `none`: a type runs past the end of the record (then past the header too: corrupt either way). -/
def walk (b : Bytes) (hdr : Nat) : Nat → Nat → Nat → Option (List Fld)
  | 0, _, _ => some []
  | f + 1, pos, off =>
    match readVar32 b pos with
    | none => none
    | some (t, n) =>
      let e : Fld := ⟨t, off, pos + n, off + slen t⟩
      if 0 < f ∧ pos + n < hdr then (walk b hdr f (pos + n) (off + slen t)).map (e :: ·)
      else some [e]

/-- OP_Column, field p2 of a record held whole in the page (`none`: SQLITE_CORRUPT). The record's length is the
payload size. A header size of 0 (never written by SQLite) reads every field as NULL. -/
def column (b : Bytes) (p2 : Nat) : Option RV :=
  match readVar32 b 0 with
  | none => none
  | some (hdr, ho) =>
    if b.length < hdr then none
    else if hdr = 0 then some .null
    else
      match walk b hdr (p2 + 1) ho hdr with
      | none => none
      | some fs =>
        let last := fs.getLast?.getD ⟨0, 0, ho, hdr⟩
        if (hdr ≤ last.pos ∧ (hdr < last.pos ∨ last.next ≠ b.length)) ∨ b.length < last.next then none
        else match fs[p2]? with
          | none => some .null
          | some e => some (serialGet e.t (body b e.off (slen e.t)))

/-! ## qc_decode -/

/-- qc_stlen (u32) for a 64-bit type. -/
def qcLen (t : Nat) : Nat := if t < 12 then slen t else ((t - 12) / 2) % 2 ^ 32

/-- qc_value: `none` for types 10 and 11 (fall back). -/
def qcValue (t : Nat) (d : Bytes) : Option RV :=
  if t = 10 ∨ t = 11 then none else some (serialGet t d)

/-- qc_decode's loop over columns c .. maxc (`req`: the mask). `fixed` adds OP_Column's checks: a type must end inside
the header and fit 32 bits. -/
def qcLoop (fixed : Bool) (b : Bytes) (hdr maxc : Nat) (req : Nat → Bool) :
    Nat → Nat → Nat → Nat → Option (Nat × Nat × List (Nat × RV))
  | 0, _, h, d => some (h, d, [])
  | fuel + 1, c, h, d =>
    if hdr ≤ h then
      (qcLoop fixed b hdr maxc req fuel (c + 1) h d).map fun (h', d', vs) =>
        (h', d', if req c then (c, .null) :: vs else vs)
    else
      match readVar b h with
      | none => none
      | some (t, n) =>
        if fixed ∧ (hdr < h + n ∨ t > 0xffffffff) then none
        else
          let len := qcLen t
          let v : Option (Option RV) := if req c then (if b.length < d + len then none else (qcValue t (body b d len)).map some) else some none
          match v with
          | none => none
          | some v =>
            (qcLoop fixed b hdr maxc req fuel (c + 1) (h + n) (d + len)).map fun (h', d', vs) =>
              (h', d', match v with | some v => (c, v) :: vs | none => vs)

/-- qc_decode(rec, sz, mask) for columns 0 .. maxc (maxc the mask's highest bit, which is set). `fixed`: also refuse a
header size whose own varint fills it (or past 32 bits), and a header read to its end whose fields do not end at the record's end. -/
def qcDecode (fixed : Bool) (b : Bytes) (maxc : Nat) (req : Nat → Bool) : Option (List (Nat × RV)) :=
  match readVar b 0 with
  | none => none
  | some (hdr, n) =>
    if b.length < hdr ∨ hdr < 1 then none
    else if fixed ∧ (hdr ≤ n ∨ hdr > 0xffffffff) then none
    else
      match qcLoop fixed b hdr maxc req (maxc + 1) 0 n hdr with
      | none => none
      | some (h, d, vs) => if fixed ∧ hdr ≤ h ∧ d ≠ b.length then none else some vs

/-! ## The finding -/

/-- **qc_decode accepts records OP_Column calls corrupt.** Three minimal ones, columns 0 and 1 requested:
- `[3, 1, 0, 7, 5]`: the header's fields cover 4 of the 5 bytes (the C repro: `(7, 5)` with b's type patched to NULL);
  qc reads (7, NULL), SQLite reports SQLITE_CORRUPT for column 1 (column 0 alone reads 7: the walk stops before the
  header's end, so OP_Column does not check it);
- `[1, 7]`: a header of only its size, with a body: qc reads (NULL, NULL);
- `[2, 0x80, 0x09]`: a type varint (9: the integer 1) running past the header's end into the body; qc reads 1. -/
theorem qc_decode_lenient :
    qcDecode false [3, 1, 0, 7, 5] 1 (fun _ => true) = some [(0, .int 7), (1, .null)] ∧ column [3, 1, 0, 7, 5] 1 = none ∧
    qcDecode false [1, 7] 1 (fun _ => true) = some [(0, .null), (1, .null)] ∧ column [1, 7] 0 = none ∧
    qcDecode false [2, 0x80, 0x09] 0 (fun _ => true) = some [(0, .int 1)] ∧ column [2, 0x80, 0x09] 0 = none := by
  decide

/-- On a well-formed record both agree (a sanity check). -/
example : qcDecode true [3, 1, 17, 7, 104, 105] 1 (fun _ => true) = some [(0, .int 7), (1, .text [104, 105])] ∧
    column [3, 1, 17, 7, 104, 105] 0 = some (.int 7) ∧ column [3, 1, 17, 7, 104, 105] 1 = some (.text [104, 105]) ∧
    column [3, 1, 17, 7, 104, 105] 5 = some .null := by
  decide

/-! ## Soundness of the fixed decoder -/

/-- A walk with less fuel reads a prefix of the fields. -/
theorem walk_take (b : Bytes) (hdr : Nat) :
    ∀ (F G pos off : Nat) (fs : List Fld), walk b hdr F pos off = some fs → 1 ≤ G → G ≤ F →
      walk b hdr G pos off = some (fs.take G) := by
  intro F
  induction F with
  | zero => intro G _ _ _ _ h1 h2; omega
  | succ F ih =>
    intro G pos off fs h hG1 hG2
    obtain ⟨G', rfl⟩ : ∃ G', G = G' + 1 := ⟨G - 1, by omega⟩
    simp only [walk] at h ⊢
    cases hr : readVar32 b pos with
    | none => simp [hr] at h
    | some tn =>
      obtain ⟨t, n⟩ := tn
      simp only [hr] at h ⊢
      by_cases hc : 0 < F ∧ pos + n < hdr
      · simp only [hc, and_self, ↓reduceIte, Option.map_eq_some_iff] at h
        obtain ⟨rest, hrest, rfl⟩ := h
        by_cases hG : 0 < G'
        · have := ih G' (pos + n) (off + slen t) rest hrest (by omega) (by omega)
          simp [hG, hc.2, this]
        · have : G' = 0 := by omega
          subst this; simp
      · simp only [hc, ↓reduceIte, Option.some.injEq] at h
        subst h
        have : ¬ (0 < G' ∧ pos + n < hdr) := by omega
        simp [this]

/-- Every field but the last ends inside the header. -/
theorem walk_inner (b : Bytes) (hdr : Nat) :
    ∀ (F pos off : Nat) (fs : List Fld), walk b hdr F pos off = some fs →
      ∀ i (hi : i + 1 < fs.length), (fs[i]'(by omega)).pos < hdr := by
  intro F
  induction F with
  | zero => intro pos off fs h i hi; simp [walk] at h; subst h; simp at hi
  | succ F ih =>
    intro pos off fs h i hi
    simp only [walk] at h
    cases hr : readVar32 b pos with
    | none => simp [hr] at h
    | some tn =>
      obtain ⟨t, n⟩ := tn
      simp only [hr] at h
      by_cases hc : 0 < F ∧ pos + n < hdr
      · simp only [hc, and_self, ↓reduceIte, Option.map_eq_some_iff] at h
        obtain ⟨rest, hrest, rfl⟩ := h
        cases i with
        | zero => simpa using hc.2
        | succ i => simp only [List.getElem_cons_succ]; exact ih _ _ rest hrest i (by simp at hi; omega)
      · simp only [hc, ↓reduceIte, Option.some.injEq] at h
        subst h; simp at hi

theorem readVar32_of (b : Bytes) (p v n : Nat) (h : readVar b p = some (v, n)) (hv : v ≤ 0xffffffff) :
    readVar32 b p = some (v, n) := by
  simp [readVar32, h]; omega

theorem qcLen_of (t : Nat) (ht : t ≤ 0xffffffff) : qcLen t = slen t := by
  unfold qcLen; split
  · rfl
  · unfold slen; rename_i h12; simp only [h12, ite_false]
    exact Nat.mod_eq_of_lt (by omega)

/-- Past the header's end the loop yields NULLs and moves nothing. -/
theorem qcLoop_past (b : Bytes) (hdr maxc : Nat) (req : Nat → Bool) :
    ∀ (F c h d : Nat) (h' d' : Nat) (vs : List (Nat × RV)), hdr ≤ h →
      qcLoop true b hdr maxc req F c h d = some (h', d', vs) →
      h' = h ∧ d' = d ∧ ∀ x ∈ vs, x.2 = .null ∧ c ≤ x.1 ∧ x.1 < c + F := by
  intro F
  induction F with
  | zero => intro c h d h' d' vs _ hq; simp [qcLoop] at hq; obtain ⟨rfl, rfl, rfl⟩ := hq; simp
  | succ F ih =>
    intro c h d h' d' vs hh hq
    simp only [qcLoop, hh, ↓reduceIte, Option.map_eq_some_iff] at hq
    obtain ⟨⟨h1, d1, vs1⟩, hr, he⟩ := hq
    simp only [Prod.mk.injEq] at he
    obtain ⟨rfl, rfl, rfl⟩ := he
    obtain ⟨e1, e2, e3⟩ := ih (c + 1) h d h1 d1 vs1 hh hr
    refine ⟨e1, e2, ?_⟩
    intro x hx
    split at hx
    · simp at hx
      rcases hx with rfl | hx
      · simp; try omega
      · obtain ⟨a1, a2, a3⟩ := e3 x hx; exact ⟨a1, by omega, by omega⟩
    · obtain ⟨a1, a2, a3⟩ := e3 x hx; exact ⟨a1, by omega, by omega⟩

/-- **The fixed loop reads the fields OP_Column's walk reads**: the same walk, the same stop, the values of the
requested fields from it (with their bodies inside the record), NULL past the header's end. -/
theorem qcLoop_walk (b : Bytes) (hdr maxc : Nat) (req : Nat → Bool) :
    ∀ (F c h d : Nat) (h' d' : Nat) (vs : List (Nat × RV)), 1 ≤ F → h < hdr →
      qcLoop true b hdr maxc req F c h d = some (h', d', vs) →
      ∃ fs, walk b hdr F h d = some fs ∧ fs.getLast? = some ⟨(fs.getLast?.getD default).t,
          (fs.getLast?.getD default).off, h', d'⟩ ∧ h' ≤ hdr ∧ (fs.length < F → h' = hdr) ∧
        ∀ x ∈ vs, c ≤ x.1 ∧ x.1 < c + F ∧
          (∀ e, fs[x.1 - c]? = some e → x.2 = serialGet e.t (body b e.off (slen e.t)) ∧ e.next ≤ b.length) ∧
          (fs[x.1 - c]? = none → x.2 = .null) := by
  intro F
  induction F with
  | zero => intro _ _ _ _ _ _ hF; omega
  | succ F ih =>
    intro c h d h' d' vs _ hh hq
    have hnot : ¬ hdr ≤ h := by omega
    simp only [qcLoop, hnot, ↓reduceIte] at hq
    cases hr : readVar b h with
    | none => simp [hr] at hq
    | some tn =>
      obtain ⟨t, n⟩ := tn
      simp only [hr] at hq
      by_cases hfx : true = true ∧ (hdr < h + n ∨ t > 0xffffffff)
      · simp [hfx] at hq
      have hfx' : ¬ (hdr < h + n ∨ t > 0xffffffff) := by simpa using hfx
      simp only [hfx', and_false, ↓reduceIte] at hq
      have hn : h + n ≤ hdr := by omega
      have ht : t ≤ 0xffffffff := by omega
      have r32 := readVar32_of b h t n hr ht
      rw [qcLen_of t ht] at hq
      -- the value step
      split at hq
      · simp at hq
      rename_i v hv
      simp only [Option.map_eq_some_iff] at hq
      obtain ⟨⟨h1, d1, vs1⟩, hrec, heq⟩ := hq
      simp only [Prod.mk.injEq] at heq
      obtain ⟨rfl, rfl, rfl⟩ := heq
      have hv2 : (req c = true ∧ d + slen t ≤ b.length ∧ v = some (serialGet t (body b d (slen t)))) ∨
          (req c = false ∧ v = none) := by
        by_cases hrc : req c = true
        · simp only [hrc, ↓reduceIte] at hv
          by_cases hl : b.length < d + slen t
          · simp [hl] at hv
          · simp only [hl, ↓reduceIte, qcValue] at hv
            by_cases h10 : t = 10 ∨ t = 11
            · simp [h10] at hv
            · simp [h10] at hv; left; exact ⟨hrc, by omega, hv.symm⟩
        · simp at hrc; simp [hrc] at hv; right; exact ⟨hrc, hv.symm⟩
      have hmem : ∀ x, x ∈ (match v with | some v => (c, v) :: vs1 | none => vs1) →
          (req c = true ∧ d + slen t ≤ b.length ∧ x = (c, serialGet t (body b d (slen t)))) ∨ x ∈ vs1 := by
        intro x hx
        rcases hv2 with ⟨hr1, hr2, rfl⟩ | ⟨_, rfl⟩
        · simp only [List.mem_cons] at hx
          rcases hx with hx | hx
          · left; exact ⟨hr1, hr2, hx⟩
          · right; exact hx
        · right; exact hx
      by_cases hin : h + n < hdr ∧ 0 < F
      · -- the walk goes on
        obtain ⟨fs0, hw0, hl0, hle, hlt, hx0⟩ := ih (c + 1) (h + n) (d + slen t) h1 d1 vs1 (by omega) hin.1 hrec
        refine ⟨⟨t, d, h + n, d + slen t⟩ :: fs0, ?_, ?_, hle, ?_, ?_⟩
        · simp [walk, r32, hin.1, hin.2, hw0]
        · cases fs0 with
          | nil => simp at hl0
          | cons a l => simp only [List.getLast?_cons_cons]; simpa using hl0
        · intro hl; simp at hl; exact hlt (by omega)
        · intro x hx
          rcases hmem x hx with ⟨_, hr2, rfl⟩ | hx1
          · refine ⟨Nat.le_refl _, by omega, ?_, by simp⟩
            intro e he; simp at he; subst he; exact ⟨rfl, hr2⟩
          · obtain ⟨a1, a2, a3, a4⟩ := hx0 x hx1
            have hidx : x.1 - c = (x.1 - (c + 1)) + 1 := by omega
            refine ⟨by omega, by omega, ?_, ?_⟩
            · intro e he; rw [hidx, List.getElem?_cons_succ] at he; exact a3 e he
            · intro he; rw [hidx, List.getElem?_cons_succ] at he; exact a4 he
      · -- the walk stops at this field
        have hstop : ¬ (0 < F ∧ h + n < hdr) := by omega
        have hwalk : walk b hdr (F + 1) h d = some [⟨t, d, h + n, d + slen t⟩] := by simp [walk, r32, hstop]
        have hpast : hdr ≤ h + n ∨ F = 0 := by omega
        -- the rest of the loop moves nothing
        have rest : h1 = h + n ∧ d1 = d + slen t ∧ ∀ x ∈ vs1, x.2 = .null ∧ c + 1 ≤ x.1 ∧ x.1 < c + 1 + F := by
          rcases hpast with hp | hp
          · exact qcLoop_past b hdr maxc req F (c + 1) (h + n) (d + slen t) h1 d1 vs1 hp hrec
          · subst hp; simp [qcLoop] at hrec; obtain ⟨rfl, rfl, rfl⟩ := hrec; simp
        obtain ⟨rfl, rfl, hnull⟩ := rest
        refine ⟨_, hwalk, by simp, hn, ?_, ?_⟩
        · intro hl; simp at hl; omega
        · intro x hx
          rcases hmem x hx with ⟨_, hr2, rfl⟩ | hx1
          · refine ⟨Nat.le_refl _, by omega, ?_, by simp⟩
            intro e he; simp at he; subst he; exact ⟨rfl, hr2⟩
          · obtain ⟨a1, a2, a3⟩ := hnull x hx1
            refine ⟨by omega, by omega, ?_, fun _ => a1⟩
            intro e he
            have : x.1 - c ≠ 0 := by omega
            simp [this] at he

/-- **The fixed decoder is sound**: whatever `qcDecode true` accepts, OP_Column reads the same value for every
requested field, and does not report the record corrupt. -/
theorem qcDecode_sound (b : Bytes) (maxc : Nat) (req : Nat → Bool) (vs : List (Nat × RV))
    (h : qcDecode true b maxc req = some vs) : ∀ x ∈ vs, column b x.1 = some x.2 := by
  unfold qcDecode at h
  cases hr : readVar b 0 with
  | none => simp [hr] at h
  | some hn =>
    obtain ⟨hdr, n⟩ := hn
    simp only [hr] at h
    split at h
    · exact absurd h (by simp)
    rename_i c1
    split at h
    · exact absurd h (by simp)
    rename_i c2
    have c2' : n < hdr ∧ hdr ≤ 0xffffffff := by simp at c2; omega
    cases hq : qcLoop true b hdr maxc req (maxc + 1) 0 n hdr with
    | none => simp [hq] at h
    | some r =>
      obtain ⟨h', d', vs'⟩ := r
      simp only [hq] at h
      split at h
      · exact absurd h (by simp)
      rename_i c3
      simp only [Option.some.injEq] at h
      subst h
      have hend : hdr ≤ h' → d' = b.length := by
        intro hh; apply Classical.byContradiction; intro hne; exact c3 ⟨trivial, hh, hne⟩
      obtain ⟨fs, hw, hlast, hle, hlt, hx⟩ := qcLoop_walk b hdr maxc req (maxc + 1) 0 n hdr h' d' vs' (by omega) c2'.1 hq
      intro x hxm
      obtain ⟨_, xlt, xsome, xnone⟩ := hx x hxm
      simp only [Nat.sub_zero] at xsome xnone
      have r32 := readVar32_of b 0 hdr n hr c2'.2
      have hwk := walk_take b hdr (maxc + 1) (x.1 + 1) n hdr fs hw (by omega) (by omega)
      have hne : fs ≠ [] := by intro hh; simp [hh] at hlast
      unfold column
      simp only [r32, show ¬ b.length < hdr by omega, show hdr ≠ 0 by omega, ↓reduceIte, hwk]
      -- the walk to x.1 stops at field x.1 or at the header's end
      have hget : (fs.take (x.1 + 1))[x.1]? = fs[x.1]? := by simp
      have hcheck : ¬ ((hdr ≤ ((fs.take (x.1 + 1)).getLast?.getD ⟨0, 0, n, hdr⟩).pos ∧
          (hdr < ((fs.take (x.1 + 1)).getLast?.getD ⟨0, 0, n, hdr⟩).pos ∨
            ((fs.take (x.1 + 1)).getLast?.getD ⟨0, 0, n, hdr⟩).next ≠ b.length)) ∨
          b.length < ((fs.take (x.1 + 1)).getLast?.getD ⟨0, 0, n, hdr⟩).next) := by
        rw [List.getLast?_eq_getElem?]
        by_cases hk : x.1 < fs.length
        · have hlen : (fs.take (x.1 + 1)).length - 1 = x.1 := by simp; omega
          rw [hlen, hget]
          have hfk : fs[x.1]? = some (fs[x.1]'hk) := List.getElem?_eq_getElem hk
          rw [hfk]; simp only [Option.getD_some]
          obtain ⟨_, hnext⟩ := xsome _ hfk
          by_cases hk2 : x.1 + 1 < fs.length
          · have := walk_inner b hdr (maxc + 1) n hdr fs hw x.1 hk2
            omega
          · -- the last field: the walk's stop
            have hl : fs.getLast? = some (fs[x.1]'hk) := by
              rw [List.getLast?_eq_getElem?]; have : fs.length - 1 = x.1 := by omega
              rw [this]; exact hfk
            rw [hl] at hlast; simp only [Option.some.injEq] at hlast
            have e1 := congrArg Fld.pos hlast; have e2 := congrArg Fld.next hlast
            simp only at e1 e2
            rw [e1, e2]
            by_cases hh : hdr ≤ h'
            · have := hend hh; omega
            · omega
        · have hlen : (fs.take (x.1 + 1)).length - 1 = fs.length - 1 := by simp; omega
          have htk : fs.take (x.1 + 1) = fs := List.take_of_length_le (by omega)
          rw [hlen, htk, ← List.getLast?_eq_getElem?, hlast]
          simp only [Option.getD_some]
          have := hlt (by omega)
          have := hend (by omega)
          omega
      simp only [hcheck, ↓reduceIte, hget]
      cases hf : fs[x.1]? with
      | none => simp [xnone hf]
      | some e => simp [(xsome e hf).1]

end Turbo.Record

/-! ## The shaped decoders: qc_decode_fast and the generated qc_dec_* (e5d68ff) -/

namespace Turbo.Record

/-- A column's class in a record shape (qc.c K_NUL, K_INT, K_TXT). -/
inductive K where
  | N | I | T
  deriving DecidableEq, Repr

/-- One column of qc_decode_fast's loop (and of gen_decoders.py's `col()`, the same statements unrolled), at header
position h and body position d, the header ending at he: `if (h >= he) return 0;` then the class's type test. -/
def stepK (b : Bytes) (he : Nat) (k : K) (h d : Nat) : Option (Nat × Nat × RV) :=
  if he ≤ h then none
  else match b[h]? with
    | none => none
    | some t0 =>
      let t := t0.toNat
      match k with
      | .N => if t ≠ 0 then none else some (h + 1, d, .null)
      | .I => if t = 0 ∨ t = 7 ∨ t > 9 then none else some (h + 1, d + slen t, serialGet t (body b d (slen t)))
      | .T =>
        let r : Option (Nat × Nat) :=
          if t ≥ 0x80 then
            (if he ≤ h + 1 then none
             else match b[h + 1]? with
               | none => none
               | some t1 => if t1.toNat ≥ 0x80 then none else some ((t - 128) * 128 + t1.toNat, h + 2))
          else some (t, h + 1)
        match r with
        | none => none
        | some (t, h') => if t < 13 ∨ t % 2 = 0 then none else some (h', d + slen t, serialGet t (body b d (slen t)))

/-- The columns, in order. -/
def fastLoop (b : Bytes) (he : Nat) : List K → Nat → Nat → Option (Nat × Nat × List RV)
  | [], h, d => some (h, d, [])
  | k :: ks, h, d =>
    match stepK b he k h d with
    | none => none
    | some (h', d', v) => (fastLoop b he ks h' d').map fun (h'', d'', vs) => (h'', d'', v :: vs)

/-- `u32 hl = rec[0]; if (hl >= 0x80 || hl > sz) return 0;` then the loop from h = 1, d = hl, then
`return h < he ? d <= rec + sz : d == rec + sz;`. -/
def decodeFast (b : Bytes) (cls : List K) : Option (List RV) :=
  match b[0]? with
  | none => none
  | some hl0 =>
    let hl := hl0.toNat
    if hl ≥ 0x80 ∨ hl > b.length then none
    else match fastLoop b hl cls 1 hl with
      | none => none
      | some (h, d, vs) => if (if h < hl then d ≤ b.length else d = b.length) then some vs else none

/-- The values as qc_decode lists them: (column, value) from column c. -/
def ixs : Nat → List RV → List (Nat × RV)
  | _, [] => []
  | c, v :: vs => (c, v) :: ixs (c + 1) vs

theorem readVar_one (b : Bytes) (p : Nat) (x : UInt8) (hx : b[p]? = some x) (h : x.toNat < 0x80) :
    readVar b p = some (x.toNat, 1) := by
  simp [readVar, readVar.go, hx, show x < 0x80 from UInt8.lt_iff_toNat_lt.mpr h]

theorem readVar_two (b : Bytes) (p : Nat) (x y : UInt8) (hx : b[p]? = some x) (hy : b[p + 1]? = some y)
    (h1 : 0x80 ≤ x.toNat) (h2 : y.toNat < 0x80) : readVar b p = some ((x.toNat - 128) * 128 + y.toNat, 2) := by
  have nx : ¬ x < 0x80 := by rw [UInt8.lt_iff_toNat_lt]; simp; omega
  have ny : y < 0x80 := UInt8.lt_iff_toNat_lt.mpr h2
  simp [readVar, readVar.go, hx, hy, nx, ny]

/-- The step is a qc_decode step: it reads the same type, within the header, of at most 32 bits, not 10 or 11. -/
theorem stepK_spec (b : Bytes) (he : Nat) (k : K) (h d h' d' : Nat) (v : RV)
    (hs : stepK b he k h d = some (h', d', v)) :
    h < he ∧ h' ≤ he ∧ h < h' ∧ ∃ t, readVar b h = some (t, h' - h) ∧ t ≤ 0xffffffff ∧ t ≠ 10 ∧ t ≠ 11 ∧
      d' = d + slen t ∧ v = serialGet t (body b d (slen t)) := by
  unfold stepK at hs
  by_cases hh : he ≤ h
  · simp [hh] at hs
  simp only [hh, ↓reduceIte] at hs
  cases ht0 : b[h]? with
  | none => simp [ht0] at hs
  | some t0 =>
    simp only [ht0] at hs
    have t0l : t0.toNat < 256 := UInt8.toNat_lt t0
    cases k with
    | N =>
      by_cases hz : t0.toNat ≠ 0
      · simp [hz] at hs
      simp only [hz, ↓reduceIte, Option.some.injEq, Prod.mk.injEq] at hs
      obtain ⟨rfl, rfl, rfl⟩ := hs
      have : t0.toNat = 0 := by omega
      refine ⟨by omega, by omega, by omega, 0, ?_, by omega, by omega, by omega, by simp [slen], by simp [serialGet]⟩
      rw [readVar_one b h t0 ht0 (by omega), this]; simp
    | I =>
      by_cases hz : t0.toNat = 0 ∨ t0.toNat = 7 ∨ t0.toNat > 9
      · simp only [hz, ↓reduceIte] at hs; exact absurd hs (by simp)
      simp only [hz, ↓reduceIte, Option.some.injEq, Prod.mk.injEq] at hs
      obtain ⟨rfl, rfl, rfl⟩ := hs
      refine ⟨by omega, by omega, by omega, t0.toNat, ?_, by omega, by omega, by omega, rfl, rfl⟩
      rw [readVar_one b h t0 ht0 (by omega)]; simp
    | T =>
      by_cases hbig : t0.toNat ≥ 0x80
      · simp only [hbig, ↓reduceIte] at hs
        by_cases hh1 : he ≤ h + 1
        · simp [hh1] at hs
        simp only [hh1, ↓reduceIte] at hs
        cases ht1 : b[h + 1]? with
        | none => simp [ht1] at hs
        | some t1 =>
          simp only [ht1] at hs
          have t1l : t1.toNat < 256 := UInt8.toNat_lt t1
          by_cases hs1 : t1.toNat ≥ 0x80
          · simp [hs1] at hs
          simp only [hs1, ↓reduceIte] at hs
          by_cases hc : (t0.toNat - 128) * 128 + t1.toNat < 13 ∨ ((t0.toNat - 128) * 128 + t1.toNat) % 2 = 0
          · simp only [hc, ↓reduceIte] at hs; exact absurd hs (by simp)
          simp only [hc, ↓reduceIte, Option.some.injEq, Prod.mk.injEq] at hs
          obtain ⟨rfl, rfl, rfl⟩ := hs
          refine ⟨by omega, by omega, by omega, _, ?_, by omega, by omega, by omega, rfl, rfl⟩
          rw [readVar_two b h t0 t1 ht0 ht1 (by omega) (by omega)]; simp
      · simp only [hbig, ↓reduceIte] at hs
        by_cases hc : t0.toNat < 13 ∨ t0.toNat % 2 = 0
        · simp only [hc, ↓reduceIte] at hs; exact absurd hs (by simp)
        simp only [hc, ↓reduceIte, Option.some.injEq, Prod.mk.injEq] at hs
        obtain ⟨rfl, rfl, rfl⟩ := hs
        refine ⟨by omega, by omega, by omega, _, ?_, by omega, by omega, by omega, rfl, rfl⟩
        rw [readVar_one b h t0 ht0 (by omega)]; simp

theorem fastLoop_mono (b : Bytes) (he : Nat) : ∀ (ks : List K) (h d hE dE : Nat) (vs : List RV),
    fastLoop b he ks h d = some (hE, dE, vs) → d ≤ dE ∧ vs.length = ks.length ∧ (ks ≠ [] → hE ≤ he) := by
  intro ks
  induction ks with
  | nil => intro h d hE dE vs hf; simp [fastLoop] at hf; obtain ⟨rfl, rfl, rfl⟩ := hf; simp
  | cons k ks ih =>
    intro h d hE dE vs hf
    simp only [fastLoop] at hf
    cases hs : stepK b he k h d with
    | none => simp [hs] at hf
    | some r =>
      obtain ⟨h1, d1, v⟩ := r
      simp only [hs, Option.map_eq_some_iff] at hf
      obtain ⟨⟨h2, d2, vs2⟩, hr, he2⟩ := hf
      simp only [Prod.mk.injEq] at he2; obtain ⟨rfl, rfl, rfl⟩ := he2
      obtain ⟨_, a2, _, t, _, _, _, _, hd, _⟩ := stepK_spec b he k h d h1 d1 v hs
      obtain ⟨m1, m2, m3⟩ := ih h1 d1 h2 d2 vs2 hr
      refine ⟨by omega, by simp [m2], ?_⟩
      intro _
      cases ks with
      | nil => simp [fastLoop] at hr; omega
      | cons _ _ => exact m3 (by simp)

/-- **The fast loop is the fixed qc_decode loop** on the columns it reads (all of them requested). -/
theorem fastLoop_qcLoop (b : Bytes) (hl maxc : Nat) (req : Nat → Bool) : ∀ (ks : List K) (c h d hE dE : Nat)
    (vs : List RV), fastLoop b hl ks h d = some (hE, dE, vs) → dE ≤ b.length →
      (∀ i, c ≤ i → i < c + ks.length → req i = true) →
      qcLoop true b hl maxc req ks.length c h d = some (hE, dE, ixs c vs) := by
  intro ks
  induction ks with
  | nil => intro c h d hE dE vs hf _ _; simp [fastLoop] at hf; obtain ⟨rfl, rfl, rfl⟩ := hf; simp [qcLoop, ixs]
  | cons k ks ih =>
    intro c h d hE dE vs hf hle hreq
    simp only [fastLoop] at hf
    cases hs : stepK b hl k h d with
    | none => simp [hs] at hf
    | some r =>
      obtain ⟨h1, d1, v⟩ := r
      simp only [hs, Option.map_eq_some_iff] at hf
      obtain ⟨⟨h2, d2, vs2⟩, hr, he2⟩ := hf
      simp only [Prod.mk.injEq] at he2; obtain ⟨rfl, rfl, rfl⟩ := he2
      obtain ⟨a1, a2, a3, t, ht, tb, t10, t11, hd, hv⟩ := stepK_spec b hl k h d h1 d1 v hs
      have mono := (fastLoop_mono b hl ks h1 d1 h2 d2 vs2 hr).1
      have rc := hreq c (Nat.le_refl _) (by simp)
      have hrc := ih (c + 1) h1 d1 h2 d2 vs2 hr hle (fun i h1' h2' => hreq i (by omega) (by simp; omega))
      simp only [List.length_cons, qcLoop, show ¬ hl ≤ h by omega, ↓reduceIte, ht]
      simp only [↓reduceIte, qcLen_of t tb, rc, show ¬ b.length < d + slen t by omega, qcValue,
        show ¬ (t = 10 ∨ t = 11) by omega, Option.map_some]
      rw [show h + (h1 - h) = h1 by omega, ← hd, hrc]
      simp [ixs, hv]
      exact ⟨a2, tb⟩

theorem mem_ixs : ∀ (c : Nat) (vs : List RV) (i : Nat) (hi : i < vs.length), (c + i, vs[i]) ∈ ixs c vs
  | _, [], _, hi => by simp at hi
  | c, v :: vs, 0, _ => by simp [ixs]
  | c, v :: vs, i + 1, hi => by
    simp only [ixs, List.mem_cons]; right
    have := mem_ixs (c + 1) vs i (by simp at hi; omega)
    rwa [show c + 1 + i = c + (i + 1) by omega] at this

/-- **qc_decode_fast (and so each generated qc_dec_*, which unrolls it) is sound**: whatever it accepts for a shape,
OP_Column reads the same value for each of the shape's columns, and does not report the record corrupt. -/
theorem decodeFast_sound (b : Bytes) (cls : List K) (vs : List RV) (hne : cls ≠ [])
    (h : decodeFast b cls = some vs) : ∀ (c : Nat) (hc : c < vs.length), column b c = some vs[c] := by
  unfold decodeFast at h
  cases h0 : b[0]? with
  | none => simp [h0] at h
  | some hl0 =>
    simp only [h0] at h
    by_cases c1 : hl0.toNat ≥ 0x80 ∨ hl0.toNat > b.length
    · simp [c1] at h
    simp only [c1, ↓reduceIte] at h
    cases hf : fastLoop b hl0.toNat cls 1 hl0.toNat with
    | none => simp [hf] at h
    | some r =>
      obtain ⟨hE, dE, vs'⟩ := r
      simp only [hf] at h
      by_cases hend : (if hE < hl0.toNat then dE ≤ b.length else dE = b.length)
      · simp only [hend, ↓reduceIte, Option.some.injEq] at h; subst h
        have hle : dE ≤ b.length := by split at hend <;> omega
        obtain ⟨_, hlen, hhe⟩ := fastLoop_mono b hl0.toNat cls 1 hl0.toNat hE dE vs' hf
        -- the first column needs 1 < hl
        have h1 : 1 < hl0.toNat := by
          cases cls with
          | nil => exact absurd rfl hne
          | cons k ks =>
            simp only [fastLoop] at hf
            cases hs : stepK b hl0.toNat k 1 hl0.toNat with
            | none => simp [hs] at hf
            | some r => obtain ⟨h', d', v⟩ := r; exact (stepK_spec b _ k 1 _ h' d' v hs).1
        have rv := readVar_one b 0 hl0 h0 (by omega)
        let req : Nat → Bool := fun i => decide (i < cls.length)
        have hq : qcDecode true b (cls.length - 1) req = some (ixs 0 vs') := by
          unfold qcDecode
          rw [rv]
          simp only [show ¬ (b.length < hl0.toNat ∨ hl0.toNat < 1) by omega, ↓reduceIte]
          have hfl := fastLoop_qcLoop b hl0.toNat (cls.length - 1) req cls 0 1 hl0.toNat hE dE vs' hf hle
            (fun i _ hi => by simp [req]; omega)
          have : cls.length - 1 + 1 = cls.length := by
            cases cls with | nil => exact absurd rfl hne | cons _ _ => simp
          rw [this, hfl]
          have : ¬ (true = true ∧ hl0.toNat ≤ hE ∧ dE ≠ b.length) := by
            intro ⟨_, h2, h3⟩; split at hend <;> omega
          simp
          refine ⟨⟨h1, by omega⟩, fun hh => ?_⟩
          split at hend <;> omega
        intro c hc
        have hm := mem_ixs 0 vs' c hc
        rw [Nat.zero_add] at hm
        exact qcDecode_sound b (cls.length - 1) req (ixs 0 vs') hq (c, vs'[c]) hm
      · simp only [hend, ↓reduceIte] at h; exact absurd h (by simp)

/-! ## The generated decoders' twins

gen_decoders.py emits, next to each C decoder, its twin (`Turbo/Generated.lean`): the same straight-line sequence of
the same statements, as `genStart`, one `genCol` per column and `genEnd`. -/

/-- `u32 hl = rec[0]; if (hl >= 0x80 || hl > sz) return 0; const u8 *h = rec + 1, *he = rec + hl, *d = rec + hl;` -/
def genStart (b : Bytes) (k : Nat → Nat → Nat → Option (List RV)) : Option (List RV) :=
  match b[0]? with
  | none => none
  | some hl0 => if hl0.toNat ≥ 0x80 ∨ hl0.toNat > b.length then none else k hl0.toNat 1 hl0.toNat

/-- `if (h >= he) return 0;` and the column's statements (gen_decoders.py `col()`). -/
def genCol (b : Bytes) (he : Nat) (k : K) (h d : Nat) (cont : Nat → Nat → RV → Option (List RV)) : Option (List RV) :=
  match stepK b he k h d with
  | none => none
  | some (h', d', v) => cont h' d' v

/-- `return h < he ? d <= rec + sz : d == rec + sz;` -/
def genEnd (b : Bytes) (he h d : Nat) (vs : List RV) : Option (List RV) :=
  if (if h < he then d ≤ b.length else d = b.length) then some vs else none

/-- A chain of `genCol`s ending in `genEnd` is the fast loop with its end check. -/
def chain (b : Bytes) (he : Nat) : List K → Nat → Nat → (List RV → List RV) → Option (List RV)
  | [], h, d, acc => genEnd b he h d (acc [])
  | k :: ks, h, d, acc => genCol b he k h d fun h' d' v => chain b he ks h' d' (fun r => acc (v :: r))

theorem chain_eq (b : Bytes) (he : Nat) : ∀ (ks : List K) (h d : Nat) (acc : List RV → List RV),
    chain b he ks h d acc = (match fastLoop b he ks h d with
      | none => none
      | some (h', d', vs) => if (if h' < he then d' ≤ b.length else d' = b.length) then some (acc vs) else none) := by
  intro ks
  induction ks with
  | nil => intro h d acc; simp [chain, fastLoop, genEnd]
  | cons k ks ih =>
    intro h d acc
    simp only [chain, genCol, fastLoop]
    cases stepK b he k h d with
    | none => simp
    | some r =>
      obtain ⟨h', d', v⟩ := r
      simp only [ih]
      cases fastLoop b he ks h' d' <;> simp

theorem decodeFast_chain (b : Bytes) (cls : List K) :
    decodeFast b cls = genStart b (fun he h d => chain b he cls h d id) := by
  unfold decodeFast genStart
  cases b[0]? with
  | none => rfl
  | some hl0 => simp only; split <;> simp [chain_eq]

end Turbo.Record

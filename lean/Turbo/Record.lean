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

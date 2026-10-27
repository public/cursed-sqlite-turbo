/-
Type affinity (datatype3.html §3-4, vdbe.c applyAffinity / applyNumericAffinity, sqlite3AtoF, alsoAnInt,
sqlite3VdbeIntegerAffinity, OP_RealAffinity): what a typed column stores, what it reads back, and the conversions a
comparison applies first. Executable, for the oracle; the conversions are exact for the inputs it generates (numeric
texts with at most 19 significant digits, where sqlite3AtoF rounds correctly; reals with short decimal expansions where
"%!.15g" needs no rounding). Two theorems: a value a numeric column stores is never numeric text, and a TEXT column
stores no numbers, so comparing two values of the same column needs no conversion.
-/
import Turbo.FastPaths

namespace Turbo

/-- Column affinities. -/
inductive SAff where
  | blob | text | numeric | integer | real
  deriving DecidableEq, Repr

def SAff.isNumeric : SAff → Bool
  | .numeric | .integer | .real => true
  | _ => false

/-! ## Doubles -/

def pow2 (e : Int) : Rat := if 0 ≤ e then ((2 ^ e.toNat : Nat) : Rat) else 1 / ((2 ^ (-e).toNat : Nat) : Rat)

/-- Round half to even. -/
def roundHalfEven (x : Rat) : Int :=
  let f := x.floor
  let r := x - f
  if r < 1/2 then f else if 1/2 < r then f + 1 else if f % 2 = 0 then f else f + 1

/-- The binary exponent e with 2^52 ≤ a / 2^e < 2^53 (a > 0), not below -1074 (subnormals). -/
def expOf (a : Rat) : Int := Id.run do
  let k : Int := (Nat.log2 a.num.natAbs : Int) - (Nat.log2 a.den : Int)
  let mut e := k - 52
  for _ in [0:4] do
    if a / pow2 e ≥ 9007199254740992 then e := e + 1
    else if a / pow2 e < 4503599627370496 then e := e - 1
  return max e (-1074)

/-- The nearest double (ties to even), as C's `(double)` of an integer and correctly rounded decimal conversion. -/
def roundD (q : Rat) : Dbl :=
  if q = 0 then .fin 0
  else
    let a := if q < 0 then -q else q
    let e := expOf a
    let m := roundHalfEven (a / pow2 e)
    let v : Rat := (m : Rat) * pow2 e
    if v ≥ pow2 1024 then (if q < 0 then .negInf else .posInf)
    else .fin (if q < 0 then -v else v)

/-- The bits of a double the model holds (+0.0 for zero). -/
def dblBits : Dbl → UInt64
  | .posInf => 0x7ff0000000000000
  | .negInf => 0xfff0000000000000
  | .fin q =>
    if q = 0 then 0
    else
      let s : UInt64 := if q < 0 then 0x8000000000000000 else 0
      let a := if q < 0 then -q else q
      let e := expOf a
      let m := (a / pow2 e).floor.toNat
      if m < 4503599627370496 then s ||| m.toUInt64                         -- subnormal (e = -1074)
      else s ||| ((e + 1075).toNat.toUInt64 <<< 52) ||| (m - 4503599627370496).toUInt64

/-! ## Text to number: sqlite3AtoF's grammar, exact -/

def isSpace (c : UInt8) : Bool := c == 32 || (9 ≤ c && c ≤ 13)
def isDigit (c : UInt8) : Bool := 48 ≤ c && c ≤ 57

def trim (s : List UInt8) : List UInt8 := ((s.dropWhile isSpace).reverse.dropWhile isSpace).reverse

def digits (s : List UInt8) : List UInt8 × List UInt8 := (s.takeWhile isDigit, s.dropWhile isDigit)
def digVal (ds : List UInt8) : Nat := ds.foldl (fun n d => n * 10 + (d.toNat - 48)) 0

/-- `[+-]digits[.digits][E[+-]digits]` or `[+-].digits[E[+-]digits]`, whitespace around: (pure integer?, exact value);
`none` when it is not a number (sqlite3AtoF ≤ 0: applyNumericAffinity leaves it as text). -/
def parseDec (s0 : List UInt8) : Option (Bool × Rat) :=
  let s := trim s0
  let (neg, s) := match s with
    | 45 :: r => (true, r)
    | 43 :: r => (false, r)
    | r => (false, r)
  let (ip, s) := digits s
  let (fp, dot, s) := match s with
    | 46 :: r => let (f, r) := digits r; (f, true, r)
    | r => ([], false, r)
  if ip.isEmpty && fp.isEmpty then none
  else
    let (ex, hasE, ok, s) : Int × Bool × Bool × List UInt8 := match s with
      | c :: r =>
        if c == 69 || c == 101 then
          let (eneg, r) := match r with
            | 45 :: r => (true, r)
            | 43 :: r => (false, r)
            | r => (false, r)
          let (ed, r) := digits r
          (if eneg then -(digVal ed : Int) else digVal ed, true, !ed.isEmpty, r)
        else (0, false, true, c :: r)
      | [] => (0, false, true, [])
    if !ok || !s.isEmpty then none
    else
      let mant : Nat := digVal (ip ++ fp)
      let e10 : Int := ex - fp.length
      let v : Rat := if 0 ≤ e10 then ((mant * 10 ^ e10.toNat : Nat) : Rat) else (mant : Rat) / ((10 ^ (-e10).toNat : Nat) : Rat)
      some (!dot && !hasE, if neg then -v else v)

def inI64 (q : Rat) : Bool := q.den == 1 && -9223372036854775808 ≤ q && q < 9223372036854775808

/-- applyNumericAffinity of a text: an integer literal that fits int64 is that integer (alsoAnInt); any other number is
the nearest double, which `tryInt` (storage) then makes an integer when it is integral and strictly inside int64
(sqlite3VdbeIntegerAffinity). `none`: not a number. -/
def textToNum (tryInt : Bool) (s : List UInt8) : Option Val :=
  match parseDec s with
  | none => none
  | some (pureInt, q) =>
    if pureInt && inI64 q then some (.int q.num)
    else
      let d := roundD q
      match d with
      | .fin r => if tryInt && r.den == 1 && -9223372036854775808 < r && r < 9223372036854775808 then some (.int r.num)
                  else some (.real d)
      | _ => some (.real d)

/-! ## Number to text ("%!.15g"), for values with a short exact decimal expansion -/

def natDigits (n : Nat) : List UInt8 := (toString n).toUTF8.toList

/-- The decimal digits of a dyadic rational's fraction part, if at most `k` of them. -/
def fracDigits (r : Rat) (k : Nat) : Option (List UInt8) := Id.run do
  let mut x := r
  let mut out : List UInt8 := []
  for _ in [0:k] do
    if x = 0 then return some out
    let y := x * 10
    let d := y.floor
    out := out ++ [(48 + d.toNat).toUInt8]
    x := y - d
  return if x = 0 then some out else none

/-- sqlite3VdbeMemStringify: an integer in decimal; a real with "%!.15g" when its exact decimal form has at most 15
significant digits and a magnitude in [1e-4, 1e15) (fixed notation, trailing zeros dropped, ".0" when integral);
`none` outside that set (the oracle does not generate those). -/
def numToText : Val → Option (List UInt8)
  | .int i => some ((toString i).toUTF8.toList)
  | .real (.fin q) =>
    let neg := q < 0
    let a := if neg then -q else q
    if a = 0 then some ("0.0".toUTF8.toList)
    else if a < 1/10000 || 1000000000000000 ≤ a then none
    else
      let ip := a.floor.toNat
      let ipd := if ip = 0 then [] else natDigits ip
      match fracDigits (a - ip) 20 with
      | none => none
      | some fd =>
        let lead := if ip = 0 then (fd.takeWhile (· == 48)).length else 0
        if ipd.length + fd.length - lead > 15 then none
        else
          let body := (if ip = 0 then [48] else ipd) ++ [46] ++ (if fd.isEmpty then [48] else fd)
          some ((if neg then [45] else []) ++ body)
  | _ => none

/-! ## Storage, read-back, comparison -/

/-- applyAffinity at INSERT. `none`: a conversion the model does not cover. -/
def storeAff (a : SAff) (v : Val) : Option Val :=
  match a, v with
  | .text, .int _ | .text, .real _ => (numToText v).map .text
  | .text, v => some v
  | .blob, v => some v
  | _, .text s => some ((textToNum true s).getD (.text s))
  | _, .real (.fin r) =>
    if r.den == 1 && -9223372036854775808 < r && r < 9223372036854775808 then some (.int r.num) else some v
  | _, v => some v

/-- What a column reads back: a REAL column turns a stored integer into the nearest double (OP_RealAffinity). -/
def readAff (a : SAff) (v : Val) : Val :=
  match a, v with
  | .real, .int i => .real (roundD i)
  | _, v => v

/-- `c <op> ?` for a column of affinity `a` and a bound value (no affinity): the comparison takes the column's affinity
(NUMERIC for INTEGER/REAL/NUMERIC), applied as OP_Lt does (`vdbeCmp`): numeric affinity converts text operands that
look like numbers, TEXT affinity converts numbers to text when either side is text. `none`: NULL (the comparison is
NULL) or not covered. -/
def cmpWithAff (a : SAff) (x y : Val) : Option Ordering :=
  if x == .null || y == .null then none
  else
    let isStr : Val → Bool := fun v => match v with | .text _ => true | _ => false
    if a.isNumeric && (isStr x || isStr y) then
      let num : Val → Val := fun v => match v with | .text s => (textToNum false s).getD v | v => v
      some (order .binary (num x) (num y))
    else if a = .text && (isStr x || isStr y) then
      let txt : Val → Option Val := fun v => match v with
        | .int _ | .real _ => (numToText v).map .text
        | v => some v
      match txt x, txt y with
      | some x', some y' => some (order .binary x' y')
      | _, _ => none
    else some (order .binary x y)

theorem textToNum_num (b : Bool) (s : List UInt8) (v : Val) (h : textToNum b s = some v) : v.isNum = true := by
  unfold textToNum at h
  split at h
  · simp at h
  · split at h
    · simp at h; subst h; rfl
    · simp only at h
      generalize roundD _ = d at h
      cases d <;> simp at h <;> (try split at h) <;> (try simp at h) <;> subst h <;> rfl

/-- **A numeric column never stores text that looks like a number**: so the numeric affinity of a comparison between
two of its values converts nothing. -/
theorem store_numeric_text (a : SAff) (ha : a.isNumeric) (v : Val) (s : List UInt8)
    (h : storeAff a v = some (.text s)) : textToNum true s = none := by
  cases a <;> simp [SAff.isNumeric] at ha <;>
  cases v <;> simp [storeAff] at h <;>
  first
    | (rename_i r; cases r <;> simp at h <;> split at h <;> simp at h)
    | (rename_i t; cases ht : textToNum true t <;> simp [ht] at h
       · subst h; exact ht
       · subst h; have := textToNum_num true t _ ht; simp [Val.isNum] at this)

/-- **A TEXT column stores no numbers.** -/
theorem store_text_no_num (v w : Val) (h : storeAff .text v = some w) : w.isNum = false := by
  cases v <;> simp [storeAff] at h <;> (try subst h) <;> (try rfl)
  all_goals (obtain ⟨t, _, rfl⟩ := h; rfl)

end Turbo

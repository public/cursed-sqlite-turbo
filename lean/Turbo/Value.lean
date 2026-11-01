/-
The values SQLite compares, and the order it puts them in (sqlite3MemCompare, SQLite 3.54.1).

Doubles are modelled by their exact value. A double that is not NaN is -∞, +∞ or a finite dyadic rational; C's `<`
and `==` on two such doubles are the exact comparison of those values (IEEE 754 §5.11), and -0.0 == +0.0, so both
zeros are `fin 0`. NaN is not a value here: SQLite never keeps one in a register or a record (sqlite3VdbeMemSetDouble
and sqlite3VdbeSerialGet turn it into NULL), so the model reads a NaN as NULL when it builds a value (`Val.ofDouble`).
-/
namespace Turbo

/-- `a < b ? lt : a > b ? gt : eq`, the way the C code writes a three-way compare. -/
def cmp3 {α} [LT α] [DecidableRel (α := α) (· < ·)] (a b : α) : Ordering :=
  if a < b then .lt else if b < a then .gt else .eq

/-- A non-NaN IEEE binary64 value, by its exact value. -/
inductive Dbl where
  | negInf
  | fin (q : Rat)
  | posInf
  deriving DecidableEq, Repr, Inhabited

namespace Dbl

def rank : Dbl → Nat
  | negInf => 0
  | fin _ => 1
  | posInf => 2

/-- C's `<` / `>` between two non-NaN doubles. -/
def cmp : Dbl → Dbl → Ordering
  | fin a, fin b => cmp3 a b
  | a, b => cmp3 a.rank b.rank

end Dbl

/-- What the proofs assume about binary64, as hypotheses rather than a bit-level model:
- `isD q`: the rational q is the value of some finite double;
- `big_int`: a double of magnitude at least 2^53 is an integer (53 significant bits);
- `i2d`: C's `(double)i` for a 64-bit integer, in whatever rounding mode;
- `exact_small`, `exact_repr`: an integer the format represents converts exactly (true in every rounding mode): every
  integer of magnitude at most 2^53, and every integer that is a double.
Real IEEE binary64 satisfies all of them; `Fmt.toy` shows they are satisfiable in Lean (they are not vacuous). -/
structure Fmt where
  isD : Rat → Prop
  big_int : ∀ q, isD q → (q ≤ -9007199254740992 ∨ 9007199254740992 ≤ q) → (q.floor : Rat) = q
  i2d : Int → Dbl
  exact_small : ∀ i : Int, -9007199254740992 ≤ i → i ≤ 9007199254740992 → i2d i = .fin i
  exact_repr : ∀ i : Int, isD (i : Rat) → i2d i = .fin i

/-- A double the format has (±∞ always). -/
def Dbl.Valid (F : Fmt) : Dbl → Prop
  | .fin q => F.isD q
  | _ => True

/-- The C `int64` range. -/
def InI64 (i : Int) : Prop := -9223372036854775808 ≤ i ∧ i < 9223372036854775808

/-- An SQLite value (a register's or a record field's). -/
inductive Val where
  | null
  | int (i : Int)
  | real (r : Dbl)
  | text (s : List UInt8)
  | blob (b : List UInt8)
  deriving DecidableEq, Repr, Inhabited

namespace Val

/-- Storage class rank: NULL < numbers < TEXT < BLOB. -/
def cls : Val → Nat
  | null => 0
  | int _ => 1
  | real _ => 1
  | text _ => 2
  | blob _ => 3

def WF (F : Fmt) : Val → Prop
  | int i => InI64 i
  | real r => r.Valid F
  | _ => True

end Val

/-! Byte strings. -/

/-- The order of BINARY collation and of blobs: bytes as unsigned, a proper prefix first. -/
def lex : List UInt8 → List UInt8 → Ordering
  | [], [] => .eq
  | [], _ :: _ => .lt
  | _ :: _, [] => .gt
  | a :: as, b :: bs => if a < b then .lt else if b < a then .gt else lex as bs

/-- `memcmp(a, b, n)` (its sign). -/
def memcmp : Nat → List UInt8 → List UInt8 → Ordering
  | 0, _, _ => .eq
  | n + 1, a :: as, b :: bs => if a < b then .lt else if b < a then .gt else memcmp n as bs
  | _ + 1, _, _ => .eq   -- (past the end: callers pass n ≤ both lengths)

/-- binCollFunc / sqlite3BlobCompare / the fast paths' text compare: `memcmp` over the shorter length, then the
length difference. -/
def memcmpLen (a b : List UInt8) : Ordering :=
  match memcmp (min a.length b.length) a b with
  | .eq => cmp3 a.length b.length
  | c => c

/-- sqlite3UpperToLower on ASCII: 'A'..'Z' to 'a'..'z', every other byte unchanged. -/
def lower (c : UInt8) : UInt8 := if 65 ≤ c ∧ c ≤ 90 then c + 32 else c

/-- sqlite3_strnicmp(a, b, n), as written: it stops at the first NUL in `a`, so the bytes after an embedded NUL are
never compared. -/
def strnicmp : Nat → List UInt8 → List UInt8 → Int
  | 0, _, _ => 0
  | n + 1, a :: as, b :: bs =>
      if a ≠ 0 ∧ lower a = lower b then strnicmp n as bs else (lower a).toNat - (lower b).toNat
  | _ + 1, _, _ => 0

def sgn (x : Int) : Ordering := if x < 0 then .lt else if 0 < x then .gt else .eq

/-- nocaseCollatingFunc. -/
def nocase (a b : List UInt8) : Ordering :=
  let r := strnicmp (min a.length b.length) a b
  if r = 0 then cmp3 a.length b.length else sgn r

inductive Coll where
  | binary
  | nocase
  deriving DecidableEq, Repr, Inhabited

def Coll.cmp : Coll → List UInt8 → List UInt8 → Ordering
  | .binary, a, b => memcmpLen a b
  | .nocase, a, b => Turbo.nocase a b

/-! The documented order (datatype3.html §4.1): NULL first, then numbers by value, then text by collation, then blobs
by memcmp. An integer and a real are compared by exact value. -/

def cmpIntDbl (i : Int) : Dbl → Ordering
  | .negInf => .gt
  | .posInf => .lt
  | .fin q => cmp3 (i : Rat) q

def numCmp : Val → Val → Ordering
  | .int a, .int b => cmp3 a b
  | .real a, .real b => a.cmp b
  | .int a, .real b => cmpIntDbl a b
  | .real a, .int b => (cmpIntDbl b a).swap
  | _, _ => .eq

/-- The specification: SQLite's value order under a collation. -/
def order (c : Coll) (a b : Val) : Ordering :=
  if a.cls < b.cls then .lt
  else if b.cls < a.cls then .gt
  else match a, b with
    | .text s, .text t => c.cmp s t
    | .blob s, .blob t => lex s t
    | .null, .null => .eq
    | a, b => numCmp a b

/-! The implementation, as sqlite3.c writes it. -/

/-- sqlite3IntFloatCompare for a non-NaN double, given C's `(double)i`. -/
def intFloatCompareC (F : Fmt) (i : Int) : Dbl → Int
  | .negInf => 1                                   -- r < -9223372036854775808.0
  | .posInf => -1                                  -- r >= 9223372036854775808.0
  | .fin r =>
    if r < -9223372036854775808 then 1
    else if 9223372036854775808 ≤ r then -1
    else
      let y : Int := if 0 ≤ r then r.floor else r.ceil   -- (i64)r truncates
      if i < y then -1
      else if y < i then 1
      else match (F.i2d i).cmp (.fin r) with
        | .lt => -1
        | .gt => 1
        | .eq => 0

/-- sqlite3MemCompare on values (flags: one type per value, as qvm's registers and decoded records have). Text under
BINARY is `binCollFunc`; under no collation it falls through to the blob compare, which is the same function. -/
def memCompareC (F : Fmt) (c : Coll) (a b : Val) : Ordering :=
  match a, b with
  | .null, .null => .eq
  | .null, _ => .lt
  | _, .null => .gt
  | .int x, .int y => cmp3 x y
  | .real x, .real y => x.cmp y
  | .int x, .real y => sgn (intFloatCompareC F x y)
  | .int _, _ => .lt
  | .real x, .int y => sgn (- intFloatCompareC F y x)
  | .real _, _ => .lt
  | _, .int _ => .gt
  | _, .real _ => .gt
  | .text s, .text t => c.cmp s t
  | .text _, .blob _ => .lt
  | .blob _, .text _ => .gt
  | .blob s, .blob t => memcmpLen s t

end Turbo

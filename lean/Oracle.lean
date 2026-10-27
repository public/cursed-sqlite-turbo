/-
The oracle: random values (weighted to the edge cases the fast paths care about) and what the model says SQLite does
with them, as a text file for tests/lean_oracle.c.

  oracle SEED COUNT TABLES > cases.txt

Values: `n` NULL, `i<decimal>`, `r<16 hex digits>` a double's bits (NaN reads as NULL, as in SQLite), `t<hex>` TEXT,
`b<hex>` BLOB. Lines:
  C <B|N> a b exp       order(a, b) under BINARY / NOCASE: -1 0 1
  I v key exp           an index cell's first field v against the integer key (qc_idx_cmp)
  H a b eq              the hash set's key equality (qv_hk_eq): 1 equal (by `hk_eq_iff`, the order's equality)
  K v hex               the planned sort-key prefix of v (ascending)
  T n                   a table of n rows, then n lines `V x y z k` (x any value, y TEXT, z NULL/INTEGER/TEXT, k
                        INTEGER), then for each column c of x, z, k:
  O <A|D|AL|DF> c ids.. ids in ORDER BY c (ASC, DESC, ASC NULLS LAST, DESC NULLS FIRST), id
  P <op> c count hash   the (a.id, b.id) pairs with a.c op b.c, in id order: count and FNV-1a of the ids
  R c k1 k2 ids..       ids with k1 <= c < k2 (integer keys: the index range probe), in id order
  D c count             count(DISTINCT c)
  M c min max           min(c), max(c) (any value of the extreme class: compared by order, not identity)
  TT n                  a typed table: n lines `W ci cr cn ct cb`, the values inserted into columns of INTEGER, REAL,
                        NUMERIC, TEXT and BLOB affinity; then per column c the lines above (O A, P lt/eq, R, D) with
                        the column's affinity applied, and
  Y c vals..            the values c reads back, in id order (reals by the bits of their exact value)
  F c op p ids..        ids with c op p for a bound value p, through the column's affinity
  ON ids..              ids in ORDER BY y COLLATE NOCASE, id
  PN count hash         pairs with a.y < b.y COLLATE NOCASE
  E                     end of table
  X rec s0..s5 | q      a record (hex): what OP_Column reads for fields 0..5 (`c`: SQLITE_CORRUPT), and what qc_decode
                        returns for them (`f`: refused); then lines
  S shape vals | f      what qc_decode_fast and the generated qc_dec_<shape> return for that record (`f`: refused)
  LT nocase esc n       a block of n LIKE rows (nocase: likeInfoNorm, else case_sensitive_like; esc: the ESCAPE
                        character, 0 none), then n lines `LR p<pattern> t<string> 0|1` (the model's like()), then
  LP p<pattern> ids..   that pattern against every row's string: the ids that match
-/
import Turbo

open Turbo

/-! ## A deterministic generator (xorshift64*) -/

structure Gen where
  s : UInt64

def Gen.next (g : Gen) : UInt64 × Gen :=
  let x := g.s
  let x := x ^^^ (x >>> 12)
  let x := x ^^^ (x <<< 25)
  let x := x ^^^ (x >>> 27)
  (x * 0x2545F4914F6CDD1D, ⟨x⟩)

def Gen.below (g : Gen) (n : Nat) : Nat × Gen :=
  let (x, g) := g.next
  (x.toNat % n, g)

def pick {α} [Inhabited α] (g : Gen) (xs : Array α) : α × Gen :=
  let (k, g) := g.below xs.size
  (xs[k]!, g)

/-! ## Doubles: bits to the model's exact value -/

def dblOfBits (b : UInt64) : Option Dbl :=   -- none: NaN
  let sign := b >>> 63
  let e := ((b >>> 52) &&& 0x7ff).toNat
  let m := (b &&& 0xfffffffffffff).toNat
  if e = 0x7ff then (if m = 0 then some (if sign = 1 then .negInf else .posInf) else none)
  else
    let (mant, ex) : Nat × Int := if e = 0 then (m, -1074) else (m + 2 ^ 52, (e : Int) - 1075)
    let q : Rat := if ex ≥ 0 then ((mant * 2 ^ ex.toNat : Nat) : Rat) else (mant : Rat) / ((2 ^ (-ex).toNat : Nat) : Rat)
    some (.fin (if sign = 1 then -q else q))

/-- A value as SQLite holds it: NaN is NULL. -/
inductive Raw where
  | null | int (i : Int) | real (bits : UInt64) | text (s : List UInt8) | blob (b : List UInt8)
  deriving Inhabited

def Raw.val : Raw → Val
  | .null => .null
  | .int i => .int i
  | .real b => match dblOfBits b with | some d => .real d | none => .null
  | .text s => .text s
  | .blob b => .blob b

def hex2 (b : UInt8) : String :=
  let d := "0123456789abcdef".toList
  String.ofList [d[(b >>> 4).toNat]!, d[(b &&& 15).toNat]!]

def hexBytes (s : List UInt8) : String := String.join (s.map hex2)

def hex16 (x : UInt64) : String :=
  hexBytes ((List.range 8).reverse.map fun k => ((x >>> (8 * k).toUInt64) &&& 0xff).toUInt8)

def Raw.fmt : Raw → String
  | .null => "n"
  | .int i => s!"i{i}"
  | .real b => s!"r{hex16 b}"
  | .text s => s!"t{hexBytes s}"
  | .blob b => s!"b{hexBytes b}"

def fmtVal : Val → String
  | .null => "n"
  | .int i => s!"i{i}"
  | .real (.fin q) => s!"q{q.num}/{q.den}"
  | .real .negInf => "q-inf"
  | .real .posInf => "q+inf"
  | .text s => s!"t{hexBytes s}"
  | .blob b => s!"b{hexBytes b}"

/-! ## Values, weighted to the edges -/

def two53 : Int := 9007199254740992
def two63 : Int := 9223372036854775808

def edgeInts : Array Int := #[0, 1, -1, 2, 3, 4, 5, 7, 8, -4, -5, 100, two53, two53 - 1, two53 + 1, two53 + 2, -two53,
  -two53 - 1, -two53 + 1, 4611686018427387904, two63 - 1, two63 - 2, two63 - 1024, two63 - 1025, -two63, -two63 + 1,
  -two63 + 1024, 123456789012345678]

def f2b (f : Float) : UInt64 := f.toBits

def edgeReals : Array UInt64 := #[
  f2b 0.0, 0x8000000000000000 /- -0.0 -/, f2b 0.5, f2b (-0.5), f2b 1.0, f2b 1.5, f2b (-1.5), f2b 2.0, f2b 2.5, f2b 3.0,
  f2b 4.0, f2b 4.5, f2b 7.999, f2b 100.25, f2b (-4.5),
  0x4340000000000000 /- 2^53 -/, 0x4340000000000001 /- 2^53+2 -/, 0x433fffffffffffff /- 2^53-1 -/,
  0xc340000000000000 /- -2^53 -/, 0x43e0000000000000 /- 2^63 -/, 0x43dfffffffffffff /- 2^63-1024 -/,
  0xc3e0000000000000 /- -2^63 -/, 0xc3e0000000000001 /- below -2^63 -/, 0x43d0000000000000 /- 2^62 -/,
  0x7ff0000000000000 /- +inf -/, 0xfff0000000000000 /- -inf -/, 0x7ff8000000000000 /- NaN -/,
  0x0000000000000001 /- 5e-324 -/, 0x7fefffffffffffff /- max -/, f2b 1e300, f2b (-1e300), f2b 0.1,
  f2b 4503599627370495.5 /- 2^52 - 0.5 -/, f2b (-4503599627370495.5)]

def s (x : String) : List UInt8 := x.toUTF8.toList

def edgeTexts : Array (List UInt8) := #[[], s "a", s "A", s "b", s "B", s "ab", s "aB", s "Ab", s "abc", s "abd",
  [97, 0, 120], [97, 0, 121], [97, 0], [0], [0, 0], [97, 0, 66], s "Z", s "[", s "_", s "`", s "z", s "{",
  s "2025-10-01", s "2025-10-02", s "2025-10-0", s "2025-10", s "2025-1", s "abcdefg", s "abcdefgh", s "abcdefg\x00",
  [0xff], [0x80], [0xc3, 0xa9], s "1", s "10", s "9", s " 1", s "1.0", s "-1", s "x", s "X"]

def edgeBlobs : Array (List UInt8) := #[[], [0], [0, 0], [1], [0xff], [97], [65], [97, 98], [0, 1, 2, 3, 4, 5, 6, 7],
  [0, 1, 2, 3, 4, 5, 6, 8]]

def genBytes (g : Gen) (alpha : Array UInt8) : List UInt8 × Gen := Id.run do
  let (n, g) := g.below 10
  let mut g := g
  let mut out := []
  for _ in [0:n] do
    let (c, g') := pick g alpha
    g := g'; out := out ++ [c]
  return (out, g)

def alphaText : Array UInt8 := #[0, 65, 66, 90, 91, 95, 96, 97, 98, 122, 123, 48, 49, 0x80, 0xff]

def genRaw (g : Gen) : Raw × Gen :=
  let (k, g) := g.below 20
  match k with
  | 0 => (.null, g)
  | 1 | 2 | 3 => let (i, g) := pick g edgeInts; (.int i, g)
  | 4 => let (x, g) := g.next; (.int ((x.toNat : Int) - two63), g)     -- any int64
  | 5 => let (x, g) := g.below 21; (.int ((x : Int) - 10), g)
  | 6 | 7 | 8 => let (b, g) := pick g edgeReals; (.real b, g)
  | 9 => let (x, g) := g.below 2001; (.real (f2b ((Float.ofNat x - 1000.0) / 4.0)), g)
  | 10 => let (i, g) := pick g edgeInts; (.real (f2b (Float.ofInt i)), g)   -- ints as doubles (rounded)
  | 11 => let (x, g) := g.next; (.real x, g)                                -- any bits
  | 12 | 13 | 14 => let (t, g) := pick g edgeTexts; (.text t, g)
  | 15 | 16 => let (t, g) := genBytes g alphaText; (.text t, g)
  | 17 => let (b, g) := pick g edgeBlobs; (.blob b, g)
  | _ => let (b, g) := genBytes g alphaText; (.blob b, g)

def genText (g : Gen) : List UInt8 × Gen :=
  let (k, g) := g.below 2
  if k = 0 then pick g edgeTexts else genBytes g alphaText

/-! ## The model's answers -/

def fmtOrd : Ordering → String | .lt => "-1" | .eq => "0" | .gt => "1"

def FNV (h : UInt64) (x : Nat) : UInt64 := (h ^^^ x.toUInt64) * 1099511628211

/-- A stable insertion sort (the order SQLite's ORDER BY ..., id gives is total, so stability does not matter). -/
def isort {α} (lt : α → α → Bool) (xs : List α) : List α :=
  xs.foldl (fun acc x =>
    let (a, b) := acc.span (fun y => !lt x y)
    a ++ x :: b) []

def holds (op : String) (o : Ordering) : Bool :=
  match op with
  | "lt" => o == .lt | "le" => o != .gt | "eq" => o == .eq | "ne" => o != .eq | "gt" => o == .gt | _ => o != .lt

def keyHex (v : Val) : String := hex16 (key v).toUInt64

structure Row where
  id : Nat
  x : Raw
  y : List UInt8
  z : Raw
  k : Raw

/-- The table's value columns: x any value; z NULL, INTEGER or TEXT (what qcg's general plans take); k integers only
(the type feedback regions speculate on). -/
def cols : List (String × (Row → Raw)) := [("x", (·.x)), ("z", (·.z)), ("k", (·.k))]

def genZ (g : Gen) : Raw × Gen :=
  let (c, g) := g.below 4
  match c with
  | 0 => (.null, g)
  | 1 => let (t, g) := genText g; (.text t, g)
  | _ => let (r, g) := genRaw g; match r with | .int i => (.int i, g) | _ => let (i, g) := pick g edgeInts; (.int i, g)

def genK (g : Gen) : Raw × Gen :=
  let (c, g) := g.below 3
  if c = 0 then let (x, g) := g.below 41; (.int ((x : Int) - 20), g) else let (i, g) := pick g edgeInts; (.int i, g)

/-! ## Typed tables (affinity) -/

def numTexts : Array String := #["0", "1", "10", "-1", "+5", " 7", "7 ", "  -3  ", "007", "1.0", "1.5", "-0.25", ".5",
  "5.", "1e3", "1E2", "2.5e1", "9223372036854775807", "-9223372036854775808", "9223372036854775808",
  "18446744073709551616", "1e20", "0x10", "1a", "abc", "", " ", "-", "1.5.2", "1e", "-0", "0.0", "0.1", "1e-2", "3.14159",
  "9007199254740993", "4.5", "-4.5", "100.25", "2", "20", "3"]

def safeReals : Array Float := #[0.0, -0.0, 0.5, 1.5, -1.5, 2.0, 2.5, 3.0, 4.5, -4.5, 100.25, 7.0, -0.25, 1000.0]

def tcols : List (String × SAff) := [("ci", .integer), ("cr", .real), ("cn", .numeric), ("ct", .text), ("cb", .blob)]

def genTyped (g : Gen) (a : SAff) : Raw × Gen :=
  let (c, g) := g.below 8
  match c with
  | 0 => (.null, g)
  | 1 | 2 => let (t, g) := pick g numTexts; (.text (s t), g)
  | 3 => if a = .text then let (f, g) := pick g safeReals; (.real (f2b f), g) else let (b, g) := pick g edgeReals; (.real b, g)
  | 4 => let (f, g) := pick g safeReals; (.real (f2b f), g)
  | 5 => let (b, g) := pick g edgeBlobs; (.blob b, g)
  | 6 => let (t, g) := pick g edgeTexts; (.text t, g)
  | _ => let (i, g) := pick g edgeInts; (.int i, g)

/-- A value as the model outputs it exactly: reals by the bits of their exact value (zero as +0.0). -/
def fmtExact : Val → String
  | .null => "n"
  | .int i => s!"i{i}"
  | .real d => s!"r{hex16 (dblBits d)}"
  | .text t => s!"t{hexBytes t}"
  | .blob b => s!"b{hexBytes b}"

def holdsOpt (op : String) : Option Ordering → Bool
  | none => false
  | some o => holds op o

def typedTable (out : IO.FS.Stream) (g0 : Gen) : IO Gen := do
  let mut g := g0
  let (n, g1) := g.below 30
  g := g1
  let n := n + 2
  let mut raws : Array (Nat × List Raw) := #[]
  for id in [1:n+1] do
    let mut rs : List Raw := []
    for (_, a) in tcols do
      let (r, g1) := genTyped g a
      g := g1
      -- a value the model cannot store exactly (a TEXT column's real with a long decimal form) becomes NULL
      let r := if (storeAff a r.val).isNone then Raw.null else r
      rs := rs ++ [r]
    raws := raws.push (id, rs)
  out.putStrLn s!"TT {n}"
  for (_, rs) in raws do out.putStrLn s!"W {" ".intercalate (rs.map Raw.fmt)}"
  let ids (l : List Nat) : String := " ".intercalate (l.map toString)
  for (j, (cn, a)) in tcols.zipIdx.map (fun (c, j) => (j, c)) do
    let vals : List (Nat × Val) := raws.toList.map fun (id, rs) => (id, readAff a ((storeAff a (rs[j]!).val).getD .null))
    out.putStrLn s!"Y {cn} {" ".intercalate (vals.map (fmtExact ·.2))}"
    let lt (x y : Nat × Val) : Bool := match order .binary x.2 y.2 with | .lt => true | .gt => false | .eq => x.1 < y.1
    out.putStrLn s!"O A {cn} {ids ((isort lt vals).map (·.1))}"
    for op in ["lt", "eq"] do
      let mut cnt := 0
      let mut h : UInt64 := 14695981039346656037
      for x in vals do
        for y in vals do
          if x.2 != .null && y.2 != .null && holds op (order .binary x.2 y.2) then
            cnt := cnt + 1; h := FNV (FNV h x.1) y.1
      out.putStrLn s!"P {op} {cn} {cnt} {h}"
    let nn := (vals.map (·.2)).filter (· != .null)
    let classes := nn.foldl (fun (acc : List Val) v => if acc.any (fun w => order .binary v w == .eq) then acc else v :: acc) []
    out.putStrLn s!"D {cn} {classes.length}"
    -- comparisons with a bound value of any type, through the column's affinity
    for _ in [0:4] do
      let (p, g1) := genTyped g (if a = .text then .text else .blob)
      let (o, g2) := g1.below 6
      g := g2
      let op := ["lt", "le", "eq", "ne", "gt", "ge"][o]!
      let res := vals.map fun (id, v) => (id, v, cmpWithAff a v p.val)
      -- skip a bound value the model does not cover (a number it cannot write as text)
      if res.all (fun (_, v, r) => v == .null || p.val == .null || r.isSome) then
        out.putStrLn s!"F {cn} {op} {p.fmt} {ids ((res.filter (fun (_, _, r) => holdsOpt op r)).map (·.1))}"
    for _ in [0:2] do
      let (k1, g1) := pick g edgeInts
      let (k2, g2) := pick g1 edgeInts
      g := g2
      let (k1, k2) := if k1 ≤ k2 then (k1, k2) else (k2, k1)
      let sel := vals.filter fun (_, v) => holdsOpt "ge" (cmpWithAff a v (.int k1)) && holdsOpt "lt" (cmpWithAff a v (.int k2))
      out.putStrLn s!"R {cn} {k1} {k2} {ids (sel.map (·.1))}"
  out.putStrLn "E"
  return g

/-! ## Records: valid ones, then mutated -/

open Turbo.Record in
def putVar (v : Nat) : List UInt8 :=   -- big-endian 7-bit groups (values below 2^56)
  let rec go : Nat → Nat → List UInt8
    | 0, _ => []
    | k + 1, x => if x < 128 then [x.toUInt8] else go k (x / 128) ++ [(x % 128).toUInt8]
  match go 9 v with
  | [] => [0]
  | l => (l.dropLast.map (· ||| 0x80)) ++ [l.getLast!]

def encInt (i : Int) : Nat × List UInt8 :=   -- SQLite's serial type and body for an integer (file format 4)
  if i = 0 then (8, []) else if i = 1 then (9, [])
  else
    let w := if -128 ≤ i ∧ i < 128 then 1 else if -32768 ≤ i ∧ i < 32768 then 2 else if -8388608 ≤ i ∧ i < 8388608 then 3
      else if -2147483648 ≤ i ∧ i < 2147483648 then 4 else if -140737488355328 ≤ i ∧ i < 140737488355328 then 6 else 8
    let t := match w with | 1 => 1 | 2 => 2 | 3 => 3 | 4 => 4 | 6 => 5 | _ => 6
    let u : Nat := (if i < 0 then i + 2 ^ (8 * w) else i).toNat
    (t, (List.range w).reverse.map fun k => ((u >>> (8 * k)) % 256).toUInt8)

def encRaw : Raw → Nat × List UInt8
  | .null => (0, [])
  | .int i => encInt i
  | .real b => (7, (List.range 8).reverse.map fun k => ((b >>> (8 * k).toUInt64) &&& 0xff).toUInt8)
  | .text t => (13 + 2 * t.length, t)
  | .blob t => (12 + 2 * t.length, t)

def encRecord (vs : List Raw) : List UInt8 :=
  let parts := vs.map encRaw
  let types := parts.flatMap (fun (p : Nat × List UInt8) => putVar p.1)
  let h0 := types.length + 1
  let hdr := if h0 < 128 then h0 else types.length + (putVar (types.length + 2)).length
  putVar hdr ++ types ++ parts.flatMap (fun (p : Nat × List UInt8) => p.2)

def mutate (g : Gen) (r : List UInt8) : List UInt8 × Gen :=
  let (k, g) := g.below 12
  let (p, g) := g.below (r.length + 1)
  let (x, g) := g.next
  let byte : UInt8 := (x &&& 0xff).toUInt8
  match k with
  | 0 => (r, g)                                                     -- valid
  | 1 => (r ++ [byte], g)                                           -- a trailing byte
  | 2 => (r.take (r.length - 1), g)                                 -- one byte short
  | 3 => ((r.head?.map (fun h => [h + 1])).getD [] ++ r.drop 1, g)   -- header size + 1
  | 4 => ((r.head?.map (fun h => [h - 1])).getD [] ++ r.drop 1, g)   -- header size - 1
  | 5 => ([1] ++ r.drop 1, g)                                       -- header size 1
  | 6 => (r.set p byte, g)                                          -- any byte
  | 7 => (r.set (1 + p % 4) (byte % 14), g)                         -- a type replaced
  | 8 => (r.take (1 + p % 4) ++ [0x80] ++ r.drop (1 + p % 4), g)      -- a continuation byte in the header
  | 9 => ([0x80, r.headD 0] ++ r.drop 1, g)                         -- the header size as a 2-byte varint
  | 10 => (r.take 1 ++ [0x90, 0x80, 0x80, 0x80, 0x0d] ++ r.drop 1, g) -- a type beyond 32 bits
  | _ => ([0] ++ r.drop 1, g)                                       -- header size 0

open Turbo.Record in
def fmtRV : RV → String
  | .null => "n"
  | .int i => s!"i{i}"
  | .real b => s!"r{hex16 b}"
  | .text t => s!"t{hexBytes t}"
  | .blob t => s!"b{hexBytes t}"

open Turbo.Record in
def records (out : IO.FS.Stream) (g0 : Gen) (count : Nat) : IO Gen := do
  let mut g := g0
  for _ in [0:count] do
    let (nf, g1) := g.below 6
    let (typed, g2) := g1.below 2
    g := g2
    let nf := if typed = 0 then nf % 4 else nf
    let mut vs : List Raw := []
    for _ in [0:nf + 1] do
      let (v, g1) := genRaw g
      g := g1
      -- short texts and blobs (a record stays in one page); half the records only NULL, INTEGER, TEXT (shaped)
      let v := match v with | .text t => Raw.text (t.take 12) | .blob t => Raw.blob (t.take 12) | v => v
      let v := if typed = 0 then (match v with | .real _ => Raw.int 5 | .blob t => Raw.text t | v => v) else v
      vs := vs ++ [v]
    let (r, g1) := mutate g (encRecord vs)
    g := g1
    if r.isEmpty then continue
    let m := 5   -- columns 0..5 (the tables have six)
    let spec := (List.range (m + 1)).map fun c => match column r c with | none => "c" | some v => fmtRV v
    let qc := match qcDecode true r m (fun _ => true) with   -- (qc_decode since e5d68ff: OP_Column's checks)
      | none => "f" | some vs => " ".intercalate (vs.map (fun (x : Nat × RV) => fmtRV x.2))
    out.putStrLn s!"X {hexBytes r} {" ".intercalate spec} | {qc}"
    -- the shaped decoders: the record's own shape (when it has one), and a random one
    let own : Option (List K) := vs.mapM fun v => match v with
      | .null => some K.N | .int _ => some K.I | .text _ => some K.T | _ => none
    let (rn, g1) := g.below 4
    let (rs, g2) := g1.next
    g := g2
    let rnd : List K := (List.range (rn + 1)).map fun i => match (rs >>> (2 * i).toUInt64) % 3 with
      | 0 => K.N | 1 => K.I | _ => K.T
    let shapes := (match own with | some o => if o.length ≤ 4 then [o] else [] | none => []) ++ [rnd]
    for sh in shapes do
      let res := match decodeFast r sh with | none => "f" | some vs => " ".intercalate (vs.map fmtRV)
      let name := String.join (sh.map fun k => match k with | .N => "N" | .I => "I" | .T => "T")
      out.putStrLn s!"S {name} {res}"
  return g

/-! ## LIKE -/

/-- Pattern and string pieces: letters in both cases, the wildcards, escapes, multibyte and malformed UTF-8 (an
overlong U+0080, a lone continuation byte), an embedded NUL. -/
def likePieces : Array (List UInt8) := #[s "a", s "A", s "b", s "B", s "%", s "_", s "\\", s "x", s "@",
  [0xc3, 0xa9] /- é -/, [0xc3, 0x89] /- É -/, [0xc2, 0x80], [0xe0, 0x82, 0x80] /- overlong U+0080 -/, [0x80], [0],
  s "ab", s "%a", s "a_"]

def swapCase (x : List UInt8) : List UInt8 :=
  x.map fun c => if 65 ≤ c ∧ c ≤ 90 then c + 32 else if 97 ≤ c ∧ c ≤ 122 then c - 32 else c

/-- A string of pieces, and a pattern made from the same pieces: kept, case-swapped, '_', '%', escaped, or dropped. -/
def genLikePair (g : Gen) (esc : Nat) : (List UInt8 × List UInt8) × Gen := Id.run do
  let (n, g) := g.below 7
  let mut g := g
  let mut str : List UInt8 := []
  let mut pat : List UInt8 := []
  for _ in [0:n] do
    let (pc, g1) := pick g likePieces
    let (m, g2) := g1.below 10
    g := g2
    str := str ++ pc
    let e : List UInt8 := if esc = 0 then [] else [esc.toUInt8]
    pat := pat ++ match m with
      | 0 | 1 | 2 => pc
      | 3 => swapCase pc
      | 4 => s "_"
      | 5 => s "%"
      | 6 => e ++ pc
      | 7 => []
      | 8 => pc ++ s "%"
      | _ => let (q, _) := pick g likePieces; q
  return ((pat, str), g)

open Turbo.Like in
def likeBlocks (out : IO.FS.Stream) (g0 : Gen) (blocks : Nat) : IO Gen := do
  let mut g := g0
  let escs : Array Nat := #[0, 92, 37, 95, 97]   -- none, '\', '%', '_', 'a'
  for _ in [0:blocks] do
    let (nc, g1) := g.below 2
    let (e, g2) := pick g1 escs
    let (n, g3) := g2.below 25
    g := g3
    let nocase := nc == 0
    let mut rows : Array (List UInt8 × List UInt8) := #[]
    for _ in [0:n + 1] do
      let ((p, t), g1) := genLikePair g e
      g := g1
      rows := rows.push (p, t)
    out.putStrLn s!"LT {if nocase then 1 else 0} {e} {rows.size}"
    for (p, t) in rows do
      out.putStrLn s!"LR p{hexBytes p} t{hexBytes t} {if likeFn nocase e p t then 1 else 0}"
    -- one pattern against every string of the block (an index range when it has a literal prefix)
    let (pi, g1) := g.below rows.size
    g := g1
    let p := (rows[pi]!).1
    let ids := (List.range rows.size).filter (fun i => likeFn nocase e p (rows[i]!).2) |>.map (· + 1)
    out.putStrLn s!"LP p{hexBytes p} {" ".intercalate (ids.map toString)}"
  return g

def main (args : List String) : IO Unit := do
  let seed := (args[0]? >>= String.toNat?).getD 1
  let count := (args[1]? >>= String.toNat?).getD 2000
  let tables := (args[2]? >>= String.toNat?).getD 50
  let nrec := (args[3]? >>= String.toNat?).getD 3000
  let nlike := (args[4]? >>= String.toNat?).getD 400
  let out ← IO.getStdout
  let mut g : Gen := ⟨(seed.toUInt64 * 0x9E3779B97F4A7C15) ||| 1⟩
  for _ in [0:count] do
    let (a, g1) := genRaw g
    let (b, g2) := genRaw g1
    let (c, g3) := g2.below 4
    g := g3
    -- NOCASE only between texts (otherwise it is BINARY's order)
    let coll := if c = 0 then Coll.nocase else Coll.binary
    out.putStrLn s!"C {if coll == .nocase then "N" else "B"} {a.fmt} {b.fmt} {fmtOrd (order coll a.val b.val)}"
    out.putStrLn s!"H {a.fmt} {b.fmt} {if order .binary a.val b.val == .eq then 1 else 0}"
    out.putStrLn s!"K {a.fmt} {keyHex a.val}"
    let (ki, g4) := pick g edgeInts
    let (kr, g5) := g4.next
    g := g5
    let key : Int := if kr % 3 == 0 then (kr.toNat : Int) - two63 else ki
    out.putStrLn s!"I {a.fmt} {key} {fmtOrd (order .binary a.val (.int key))}"
  for _ in [0:tables] do
    let (n, g1) := g.below 40
    g := g1
    let n := n + 2
    let mut rows : Array Row := #[]
    for id in [1:n+1] do
      let (x, g1) := genRaw g
      let (y, g2) := genText g1
      let (z, g3) := genZ g2
      let (k, g4) := genK g3
      g := g4
      rows := rows.push ⟨id, x, y, z, k⟩
    out.putStrLn s!"T {n}"
    for r in rows do out.putStrLn s!"V {r.x.fmt} t{hexBytes r.y} {r.z.fmt} {r.k.fmt}"
    let rl := rows.toList
    let ids (l : List Row) : String := " ".intercalate (l.map (fun r => toString r.id))
    let flags : List (String × SortFlags) := [("A", ⟨false, false⟩), ("D", ⟨true, false⟩), ("AL", ⟨false, true⟩), ("DF", ⟨true, true⟩)]
    for (cn, col) in cols do
      for (dn, f) in flags do
        let lt (a b : Row) : Bool :=
          match keySpec [(.binary, f)] [(col a).val] [(col b).val] with | .lt => true | .gt => false | .eq => a.id < b.id
        out.putStrLn s!"O {dn} {cn} {ids (isort lt rl)}"
      for op in ["lt", "le", "eq", "ne", "gt", "ge"] do
        let mut cnt := 0
        let mut h : UInt64 := 14695981039346656037
        for a in rl do
          for b in rl do
            let va := (col a).val; let vb := (col b).val
            if va != .null && vb != .null && holds op (order .binary va vb) then
              cnt := cnt + 1; h := FNV (FNV h a.id) b.id
        out.putStrLn s!"P {op} {cn} {cnt} {h}"
      for _ in [0:3] do
        let (k1, g1) := pick g edgeInts
        let (k2, g2) := pick g1 edgeInts
        g := g2
        let (k1, k2) := if k1 ≤ k2 then (k1, k2) else (k2, k1)
        let sel := rl.filter fun r => order .binary (col r).val (.int k1) != .lt && order .binary (col r).val (.int k2) == .lt
        out.putStrLn s!"R {cn} {k1} {k2} {ids sel}"
      -- DISTINCT: classes of equal non-NULL values (count(DISTINCT) skips NULLs)
      let nr := (rl.map col).filter (fun r => r.val != .null)
      let classes := nr.foldl (fun (acc : List Val) v =>
        if acc.any (fun w => order .binary v.val w == .eq) then acc else v.val :: acc) []
      out.putStrLn s!"D {cn} {classes.length}"
      let mn := nr.foldl (fun (acc : Option Raw) v => match acc with
        | none => some v | some w => if order .binary v.val w.val == .lt then some v else some w) none
      let mx := nr.foldl (fun (acc : Option Raw) v => match acc with
        | none => some v | some w => if order .binary v.val w.val == .gt then some v else some w) none
      out.putStrLn s!"M {cn} {(mn.getD .null).fmt} {(mx.getD .null).fmt}"
    let ltN (a b : Row) : Bool :=
      match order .nocase (.text a.y) (.text b.y) with | .lt => true | .gt => false | .eq => a.id < b.id
    out.putStrLn s!"ON {ids (isort ltN rl)}"
    let mut cnt := 0
    let mut h : UInt64 := 14695981039346656037
    for a in rl do
      for b in rl do
        if order .nocase (.text a.y) (.text b.y) == .lt then
          cnt := cnt + 1; h := FNV (FNV h a.id) b.id
    out.putStrLn s!"PN {cnt} {h}"
    out.putStrLn "E"
    g ← typedTable out g
  g ← records out g nrec
  let _ ← likeBlocks out g nlike

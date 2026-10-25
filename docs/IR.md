# qvm's middle tier: plan

qc has three executors:
- **The specialised plan** (`qc.c`) and **the general loop plans** (`qcg.c`) pattern-match the bytecode into
  rewritten programs.
- **qvm** (`qvm.c`) runs any read-only VDBE program on SQLite `Mem` registers.

The middle tier sits between the loop plans and qvm. It doesn't need to recognise a whole shape, and it doesn't pay
an interpreter's per-opcode costs.

## What it is for

The profiles in RESULTS §7 show where qvm spends its time once the B-tree work is subtracted:
- **Register traffic:** every opcode reads and writes `Mem` flags. Every Column decodes into a 56-byte `Mem` that the
  next opcode reads back.
- **Repeated decoding:** a row's record header is parsed incrementally per Column. The serial type is checked per
  value, even when the schema and every row so far say the column is always an integer.
- **Generic data structures:** ephemeral B-trees for tables that are only appended to and scanned, and generic
  aggregate contexts for `count`/`sum`.
- **Dispatch:** one indirect jump per opcode, threaded.

## Done so far (part 1)

These are the pieces the IR's lowering will emit. qvm already uses them directly where the bytecode allows:
- **In-memory vectors for ephemeral rowid tables** (`QVC_VEC`): window frames, and materialized and recursive CTEs.
  - Records live in the arena and are read zero-copy.
  - Appends take O(1), rowid seeks use binary search, and deletes are tombstones that follow SQLite's cursor rules.
  - Chosen at lift time when every opcode on the cursor family is one the vector reproduces.
  - On anything else at run time (an insert into the middle, a move from an unknown position) the run deoptimises.
- **Native aggregates:**
  - `count()` is a plain integer.
  - `sum`/`total`/`avg` accumulate integers natively. The first non-integer or overflow writes SQLite's own `SumCtx`
    into the register and calls `sumStep` from then on, so results match by construction.
- **Deoptimisation:** runs are read-only and their rows are buffered. A run that meets an unsupported case returns
  QC_FALLBACK before any row is handed out, and the plan drops the speculation for later runs (`vecOff`). The caller
  steps the statement with SQLite. This is the mechanism type guards will use.
- **Record decoders by shape:** `gen_decoders.py`, already used by the loop plans.

Measured (exp200, A/B medians against the interpreter):

| shape | vs interpreter |
|---|---:|
| window lag/lead | −44 % |
| window avg, range frame | −42 % |
| window rank | −28 % |
| window sum | −27 % |
| materialized CTE | −34 % |
| recursive CTE | −52 % |
| avg/sum/total | −16 % |

## Done so far (part 2)

- **Type feedback** (step 1): per-opcode class masks from a plan's first two runs, recorded by a separate compile of
  the interpreter loop. `QFB=1` prints them.
- **Loop regions with a closure executor** (step 4): single-cursor loop bodies become arrays of nodes that run
  direct-threaded: handlers chosen by opcode and feedback, operands resolved. The next row is decoded by the loop's
  Next. Integer Columns and integer comparisons run in line, and a failed guess widens the node to the generic one.
  - The handlers share qv_run's opcode bodies, so a region can hand over to qv_run at any opcode.
  - Unlike the guards planned below, a failed guess doesn't deoptimise the run. Each node's generic path is the
    exact one, so the guess only picks the fast path.

  Measured in RESULTS §7c: up to 13 points over qvm alone on scans, filters and expressions, and level with the
  previous commit elsewhere.

## The IR

- **Scope:** one loop nest at a time, delimited by a cursor's Rewind/Seek … Next/Prev and by coroutine bodies. The
  code outside loops stays in qvm, so a region boundary is a qvm call and back.
- **Values:** typed SSA values: `int`, `real`, `text(ptr,len)`, `blob(ptr,len)`, each optionally `| null`.
  - Registers that only hold such values become IR values.
  - Registers used as subroutine return addresses or coroutine states stay control flow.
- **Type feedback:** qvm records cheap feedback while it runs: per Column opcode, a mask of the serial-type classes
  seen; per comparison, the operand class pair.
  - After N runs, a region is lifted with those types as speculation.
  - A Column whose mask is `{int}` becomes "check type byte ∈ 1..6/8/9, read int".
  - A comparison between two speculated ints becomes a machine compare.
- **Fused decoding:** all the Columns a region reads from one cursor become one decode at the row's position, using
  the shape decoder for the speculated serial types (the loop plans' `qc_dec_*`). The header is parsed once and only
  the fields used are produced. A shape mismatch is a guard failure.
- **Aggregates and ephemeral data:**
  - AggStep/AggFinal on `count`/`sum`/`total`/`avg`/`min`/`max` become IR accumulators;
  - ephemeral tables become the part 1 vectors, or hash sets where only Found/IdxInsert touch them (DISTINCT,
    count(DISTINCT));
  - sorters become the stable merge sort on pre-decoded keys.
- **Guards and deoptimisation:**
  - Every speculation is a guard. A failed guard abandons the run and falls back as above.
  - The region is re-lifted without that speculation, so types widen to `| text` or to `any`, which is qvm's own `Mem`
    path.
  - Nothing is ever partially output, so no frame reconstruction is needed.
- **Execution:**
  - first, closure threading: each IR node is a small struct with a function pointer, the values in a flat unboxed
    array, and no `Mem`;
  - then, for hot regions, copy-and-patch stencils (the vjit infrastructure in cursed-http's explore/sqlite-jit) once
    a profile shows dispatch is still significant.

  The oracle experiment (RESULTS 5g) bounds that last step at a few percent for decode/write. The IR's gains are
  expected from unboxing, fusion and data structures, not from machine code.

## Order of work

1. ~~Type feedback in qvm~~ (done, part 2).
2. Hash sets for membership-only ephemeral indexes (DISTINCT, count(DISTINCT)).
3. A sorted vector for iterated ephemeral indexes: IN lists, top-N, IN (subselect).
4. ~~The region lifter and closure executor for single-cursor scan loops~~ (done, part 2). Next on this line: typed
   values in the nodes (no `Mem` between them), so a region's Column → compare → AggStep chain stays unboxed.
5. Nested loops (joins through SeekRowid / index seeks) and coroutines inside regions.
6. Stencils for hot regions, if the profile asks for them.

Each step is checked the same way as everything else in qc: the corpus in both modes compares every value with the
interpreter, a sanitizer build runs both modes, and the speed claims come from alternating A/B runs on the Xeon.

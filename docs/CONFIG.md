# Configuration

Compile-time knobs go in `CFLAGS`. The run-time switches are environment variables, read once when the first
connection's state is created. Defaults are what `main` ships.

## Build-time knobs

- `-DQV_MAXPINS=N` (default 65536, at least 256): how many distinct database pages one qvm execution may keep
  pinned while text or blob values point into them. Each page is pinned once per execution. Past the limit, the
  execution falls back to the interpreter. A pinned page holds a page-cache reference until the execution ends, so
  the worst case is N × page size.
- `-DQV_PIN_CHEAP=N` (default 128): past this many pinned pages in one execution, qvm copies text and blobs into
  their registers, as vdbe.c does, instead of pinning more pages. A long scan then doesn't pay a pin per page for
  values that ResultRow or an insert copies anyway. `0` copies always.
- `-DQV_TOPN_MAX=N` (default 256): the most entries qvm's top-N sorter (`ORDER BY … LIMIT N`) keeps in a sorted array.
  Past that it moves them into an ephemeral B-tree, as SQLite would have used.
- `-DQV_SPILL_COPY_MAX=N` (default 256 MB): a sort that outgrows memory runs in SQLite's own sorter, and qvm copies
  the rows it reads back. Past N bytes in one run, the statement falls back to the interpreter.
- `-DQC_MAXPLANS=N` (default 1024, per tier): how many statements can hold a lifted plan at once on one connection.
  Beyond that, a statement isn't lifted and runs in the interpreter. A transaction's end closes only the cursors of
  the plans it used, so a large cap costs nothing per transaction.
- `-DQC_CACHE_PLANS=N` (default 256, 0 to compile it out; `QC_NOCACHE=1` at run time): the plan cache across
  prepares.
  - **Detach:** when a statement is finalized, its plan (general or qvm) is kept, keyed by connection and SQL text.
  - **Reuse:** the next prepare of the same text gets the plan back if its program has the same signature: every
    opcode and operand, with P4 compared by value. A qvm plan keeps its type feedback and loop regions.
  - **Bounds:** least recently used out, purged when the connection closes. Each connection has its own.
  - **Tip:** statements whose plan depends on a bound value are re-prepared by SQLite whenever a binding changes,
    and then lifted again. `SQLITE_DBCONFIG_ENABLE_QPSG` on the connection avoids that, at the cost of plans that
    ignore the bound values.
- `-DQV_NO_THREADED`: qvm dispatches with a switch instead of computed gotos.
- `-DQV_RGSEEK=1` (default 0): a loop whose body moves other cursors to one row (a join's SeekRowid, NotExists,
  DeferredSeek, NullRow) becomes a region too, run by qv_region_s (qc/qvm_region.h). Under clang it wins on such joins
  (zotero duplicates.creators −2.2 % instructions, load_item_data −0.8 %, load_tags −0.7 %). Under gcc -O2, which the
  benchmark boxes build with, the same statements lose (load_item_data +1.0 %, calibre view.meta +0.3 %): a streamed
  region is entered again for every row, and gcc's entry to qv_region_s costs more than the nodes save. See
  docs/TOUGH_PROBLEMS.md, "Join loops with point lookups in regions".
- `-DQC_ADAPT_MIN_US=N` (default 0: every plan is measured; `QC_ADAPT_MIN_US=N` at run time keeps a plan under N µs unmeasured), `-DQC_ADAPT_WARM=N` (default 3): the adaptive tier choice (RESULTS §17).
  - **What it does:** a general or qvm plan run with a row callback is timed after its first N executions. Plans
    that take N µs or more are compared with SQLite's interpreter, which qc then runs itself on a few executions and
    whose rows it hands to the same callback.
  - **Parking:** a statement is parked unless the plan's fastest of four runs is at least 2 % under the interpreter's
    fastest (`-DQC_ADAPT_MARGIN=0.98`, or `QC_ADAPT_MARGIN=0.98` at run time; 1.0 parks a plan that is any slower,
    1.03, the default before `1a50b2d`, keeps one up to 3 % slower): `sqlite3_qc_exec` returns QC_FALLBACK ("parked")
    and the caller steps it, and serving runs it in the interpreter without asking qc. Its R-th park lasts 256 ×
    2^(R−1) executions (`QC_PARK_BASE`); the third park of a plan that was never kept is for good (`QC_PARK_FINAL`). A
    kept plan is measured again after 256 × 2^K executions.
  - **Turning it off:** `QC_NOADAPT=1` at run time.
  - **A parked statement's fresh handles:** when a plan goes back into the plan cache inside a park, the rest of its park
    is counted at once and noted by its text's hash and length (`QV_PARKS` slots per connection, default 256). Each new
    handle on that text is then left to SQLite before the plan-cache lookup. `QC_NOPARKFAST=1` at run time turns this
    off (for A/B runs).
  - **Gates:** a point lookup too small for any plan to win, and an output-only scan, are handed to SQLite at their first
    start without being lifted.


## Run-time switches

These are mostly for measurement and A/B runs.

- `QC_STREAM=0` / `1` (default on, `-DQV_STREAM_DEFAULT`): a served qvm plan past its feedback runs hands out each row as it reaches it, in its own
  registers, as SQLite's interpreter does, instead of keeping the whole result before the first step.
  - **Only one stream is paused at a time on a connection.** Before any other statement starts on it, the paused stream's
    remaining rows are kept as an unstreamed run keeps them. A refused statement (a write) counts too.
  - **A failure after rows were handed out** (a deopt, out of memory): the interpreter runs the statement from its
    start in the same read transaction and skips those rows. Plans with a function that isn't deterministic don't
    stream.
  - **Which plans stream:** those whose last run handed out at least 32 rows (`QC_STREAM_MIN=N`, `-DQV_STREAM_MIN`)
    with texts or blobs, or 4 values or more a row. A short result, or rows of a few numbers, is cheaper kept whole. `QC_STREAM_MIN=0` streams every result
    (the tests).
  - `QC_STREAM_FAILAT=K` (tests): every stream fails after K rows and is replayed.
- `QC_STATS=1`: counts printed to stderr at exit (or by `sqlite3_qc_stats()`):
  - executions by tier;
  - fallbacks and failed lifts by reason;
  - the type-feedback masks of Column and comparison opcodes;
  - region nodes widened, plan cache hits;
  - the adaptive tier choice's samples, kept and parked plans.


## The JCC-erratum flag

On x86-64 the Makefile adds `-mbranches-within-32B-boundaries` when the compiler takes it. On Cascade Lake, the
JCC-erratum microcode otherwise lets any edit move a hot loop onto a 32-byte boundary and cost it up to 15 %
(RESULTS §13).


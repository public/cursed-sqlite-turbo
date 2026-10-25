# Prior art: compiling SQLite's queries to machine code

(Written in cursed-http before qc existed; "our" and "this repo" in §5 mean cursed-http and its hand-written engine.)

Question: is there a known way to "JIT SQLite", i.e. turn a VDBE program (or the query plan behind it) into
specialised machine code, and what did it buy where it was tried? Searched 2026-10-25: web, arXiv, SQLite/PostgreSQL
lists, GitHub.

## Short answer

- **Nobody ships a JIT for SQLite's VDBE.** There are three experiments (a thesis, Tarantool, a Go rewrite), and none
  of them measured OLTP point queries. The reported wins are 1.7–2× on scan-heavy, expression-heavy queries. They go to
  zero when B-tree and row work dominate, or when many rows are returned.
- **Query compilation wins in analytics** (HyPer/Umbra, PostgreSQL), where an operator touches millions of tuples and
  interpretation overhead is paid per tuple. Its best-documented gains come from **tuple deforming and expression
  evaluation** specialised to a known schema. That's the only part that maps onto our workload.
- **Copy-and-patch** solves *compile latency*. It doesn't make code faster: it's 14 % faster than LLVM -O0 on TPC-H.
  Our programs are fixed at build time, so compile latency doesn't matter to us and a C compiler at `-O2` is the
  better "JIT".
- **Why upstream hasn't done it:** SQLite gives no reason in public. The constraints are obvious, though: portability to
  platforms that forbid writable+executable memory (iOS, consoles, many embedded targets), the 100 % MC/DC test standard,
  library size, and OLTP-sized programs where the interpreter isn't where the time goes.

## 1. SQLite VDBE JIT attempts

| project | what was compiled | how | reported result | relevance |
|---|---|---|---|---|
| **Kashuba & Mühleisen, "Automatic Generation of a Hybrid Query Execution Engine"** (CWI, arXiv 1808.05448, SQLite 3.23.0) | VDBE opcode bodies. A tool extracts each `case OP_x:` from `vdbe.c` with pycparser and turns it into a C template, with jumps as labels and the opcode as a constant. A hot loop (counted backward jumps) is emitted as C, compiled with `gcc -O2` to a `.so`, `dlopen`ed and called | template JIT through a C compiler | **up to 1.72×** on a 100M-row full scan with ~60 arithmetic/compare operations and an empty result. The gain shrinks as more rows are returned and is **"negligible" once >60 % of rows are selected** (the per-row result callback dominates). Hand-specialised integer opcodes: 4.17× | Scan of random numbers, no index. The win comes from removing dispatch and type checks in a tight expression loop. We have no such loop: our reads don't run the VDBE at all |
| **Tarantool SQL JIT** (Habr 666370, 2022; Tarantool's SQL is forked from SQLite's VDBE) | per-opcode basic blocks in LLVM IR, with opcode bodies called as C callbacks (no LLVM inlining through the C API before LLVM 13) | LLVM ORC; LuaJIT and MIR considered | TPC-H: Q19 ~2×, Q17/Q20 better, the rest unchanged. Arithmetic JIT unfinished | "Not a universal win; suits heavy analytical queries". Same lesson |
| **musql** (github.com/samyfodil/musql, Go) | scans and aggregates over its own **columnar** file format; point lookups and joins as "JIT-compiled VDBE programs" | own codegen | 130–3,400× on scans and aggregates (columnar plus SIMD, not the JIT alone); **rowid lookup 5.6×, indexed equi-join 1.4×** vs C SQLite; **batch INSERT 0.82–0.97× of SQLite's time**. Not SQLite file-compatible | The big numbers come from a different storage format. On SQLite-shaped point work (lookup, join, insert) the gains are small, and on inserts there's essentially none, in line with our own `direct_writes` result (§5) |
| Turso / libSQL `vdbecc` (2026) | the reverse direction: LLVM IR → VDBE bytecode (the Doom demo) | — | — | shows the VDBE as a compilation *target*, not a JIT |
| HN thread on "Why SQLite Uses Bytecode" (item 40206752, 2024) | discussion only: opcode bodies already look like basic blocks, so a template JIT "could follow" | — | no measurement | — |

`sqlite.org/whybytecode.html` (Hipp) argues for bytecode over a tree of objects. It mentions no JIT, and it notes that
an opcode is a database primitive (`OP_Column`, `OP_SeekGE`) rather than a CPU-level instruction. Each opcode already
does a lot of work, so dispatch is a small share of OLTP statements.

**musql behind a build flag?** (asked 2026-10-25) Its speed comes from its own columnar file. Against the rules:
- **rule 2**: "the database is SQLite: the file at `$SQLITE_PATH`". A `.musq` file is another database, and its
  importer would be a second store.
- **rule 3**: no added tables or indexes, so a columnar shadow table inside the SQLite file is out too.
- **rule 5**: an in-memory columnar copy is "in-memory copies of tables".

That's **red** at every level, flag or no flag. It could be built only as a "what if" ceiling in explore/ and never
in `submission/`. The part that transfers is what musql does for point work, "JIT-compiled VDBE programs" for rowid
lookups and indexed joins (5.6× and 1.4× against C SQLite running SQL). That's the comparison our direct cursor
reads already won by hand. Its batch INSERT at 0.82–0.97× of SQLite's time matches our `direct_writes` finding.

## 2. Compiling query plans (academic and production)

| work | idea | reported result | what it says about us |
|---|---|---|---|
| **Neumann, "Efficiently Compiling Efficient Query Plans for Modern Hardware"** (VLDB 2011, HyPer) | data-centric produce/consume codegen to LLVM IR: a pipeline becomes one tight loop with tuples kept in registers | several × over Volcano interpretation and vector-at-a-time engines on TPC-H, compile times of a few ms per query | the win is per tuple across pipelines with millions of tuples. Our feed handles 20 + 20 rows |
| **Kohn, Leis, Neumann, "Adaptive Execution of Compiled Queries"** (ICDE 2018) | start in a bytecode interpreter of the LLVM IR, compile hot morsels in the background | removes the compile-latency penalty on short queries | compile latency is the main practical problem of query JITs. We have none (programs fixed at build) |
| **Kersten, Leis, Neumann, "Tidy Tuples and Flying Start"** (VLDB 2021, Umbra) | own IR; the "Flying Start" backend emits x86 directly, an order of magnitude faster to compile than LLVM -O0 | short queries become cheap to compile | same: a latency fix |
| **Kersten et al., "Everything You Always Wanted to Know About Compiled and Vectorized Queries"** (VLDB 2018) | Typer (compiled) vs Tectorwise (vectorised) in one framework | within ~2× of each other. Compiled wins on compute-heavy work, vectorised on memory-stall-heavy (hash joins). Both beat interpretation | **our feed is memory-stall bound** (2k L2 misses per request on the Xeon, IPC 1.74 on the feed). Compilation doesn't hide misses; batching and prefetching do (that's what `ms_table_seek` does) |
| **Tableau Hyper** | HyPer's lineage in production (LLVM, adaptive) | — | — |
| **DuckDB** | deliberately no JIT: vectorised interpretation (2,048-value vectors). Cited reasons: compiler toolchains are heavy dependencies for an embeddable library, and vectorisation gets most of the gain | DuckDB is competitive with compiled engines | same embedding argument SQLite has |
| **PostgreSQL JIT** (Andres Freund; LLVM; PG 11, 2018; on by default since PG 12) | expressions and **tuple deforming** compiled per query; deforming uses the known tuple descriptor (fixed offsets, known types, no NULL checks for NOT NULL) | deforming's share of TPC-H Q1 **15 % → ~3 %**; "up to ~40 %" on some TPC-H queries; deforming up to 2× on wide tables (Knizhnik). JIT only above `jit_above_cost` (100,000) | **OLTP regresses**: compile cost is tens to hundreds of ms, so short queries must stay interpreted, and many operators recommend `jit=off` for OLTP. Deforming is the part that transfers to us: we already deform by hand (§5) |

## 3. Copy-and-patch

- **Xu & Kjolstad, "Copy-and-Patch Compilation"** (OOPSLA 2021, arXiv 2011.13127): stencils are pre-compiled machine
  code with holes (relocations) for constants, jump targets and calls. Clang produces them at build time; at run
  time they're memcpy'd and the holes patched. On TPC-H, code generation is **~100× faster than LLVM -O0** (1000× vs
  -O2) and the output runs **~14 % faster than LLVM -O0**, ~10× faster than interpretation. WebAssembly: 4.9–6.5× faster
  to compile than Liftoff, with 39–63 % faster code.
- **CPython 3.13 JIT** uses it for micro-ops. The reported early gains are a few percent at best, because the stencils
  are glued-together interpreter cases and keep calling into the runtime.
- **What fits us:** copy-and-patch only makes sense when the programs are unknown until run time. Ours are seven
  statements fixed by the challenge spec. Ahead-of-time specialisation (write or generate the C, compile with the
  rest of the server under PGO) gives the same code shape with full optimisation and no W^X issues. A run-time JIT
  only adds over AOT if it specialises on **run-time constants** (root page numbers, the file format, key widths, the
  current tree depth). For us those are a handful of loads from hot lines.

## 4. Why SQLite upstream hasn't done it (inferred; there is no public statement)

1. **Portability and policy.** SQLite runs on platforms that forbid writable+executable memory (iOS apps, game
   consoles, hardened kernels, many MCUs). A JIT would be an optional fast path at best.
2. **Testing.** SQLite ships with 100 % MC/DC branch coverage (TH3). A code generator multiplies the states to cover.
3. **Size and dependencies.** An LLVM dependency is out of the question for a ~1 MB library (the same argument as
   DuckDB's). A template JIT needs per-architecture code.
4. **Where OLTP time goes.** Opcodes are coarse (`OP_Column` deforms a field, `OP_SeekGE` descends a B-tree), so
   dispatch is a small share for point queries. The B-tree, pager and page cache dominate, and compiling bytecode
   doesn't touch them. The thesis's gains show up only on scans with long expression chains.
5. **Prepared statements** already amortise parsing and planning, the usual target of "compile once".

## 5. Our own prior art (this repo): we already did the AOT version

- **Reads:** `explore/db` replaced the SQL feed/get with hand-written B-tree cursor code (`direct_reads=1`, default
  since round 1). It's a hand-compiled query plan, in HyPer terms one pipeline per endpoint with the joins fused. The
  feed adds a level-synchronous batched B-tree descent with prefetching (`ms_table_seek`, from `explore/sqlite-simd`),
  `Previous` stepping instead of re-seeks, and one range walk of `likes_post_id_idx` for all 20 like counts. The VDBE
  isn't on the read path at all, and record deforming is hand-specialised (`rec_decode`: header varints, then only the
  first *n* fields, with no `Mem` objects and no `sqlite3VdbeRecordUnpack`).
- **Writes:** `direct_writes=1` is exactly "the INSERT VDBE program compiled to straight-line C": `sqlite3BtreeInsert`
  into each index in VDBE order, `OP_MakeRecord` and the CHECK reimplemented, `OP_NoConflict` as an index probe. It
  produced a **byte-identical database file** after 230k random ops with failure injection, and was **rejected because
  it isn't faster**: 1.4 vs 1.6 µs of B-tree work per like on macOS, beside ~4 µs of WAL/page cost, and mixed totals
  within ±5 % with the sign flipping (explore/db/RESULTS.md, "Direct writes").

So the "JIT" question for us is narrower than the literature's. There's no interpreter left on the hot path except
in writes, where it's worth ~0.2 µs per write. What's left is whether *specialising further* (on schema constants,
on the exact record layout, on known-clean JSON fields) cuts the feed's instruction count. That's the PostgreSQL
deforming lesson, applied to code that is already compiled. See ESTIMATE.md.

## Sources

- Kashuba, Mühleisen: arXiv 1808.05448 — https://arxiv.org/abs/1808.05448
- Tarantool SQL JIT (Habr) — https://habr.com/ru/post/666370
- musql — https://github.com/samyfodil/musql
- Why SQLite uses bytecode — https://sqlite.org/whybytecode.html ; HN — https://news.ycombinator.com/item?id=40206752
- Turso vdbecc article — https://yage.ai/share/turso-sqlite-vdbe-llvm-20260805.html
- Xu, Kjolstad, Copy-and-Patch — https://arxiv.org/abs/2011.13127 ; https://2021.splashcon.org/details/splash-2021-oopsla/40/Copy-and-Patch-Compilation-A-Fast-Compilation-Algorithm-for-High-Level-Languages-and
- PostgreSQL JIT threads — https://www.postgresql.org/message-id/20161206232231.ajn6r5bww63v4ntu%40alap3.anarazel.de ,
  https://postgresql.org/message-id/20170401074141.jgzageyn3fzshdf3%40alap3.anarazel.de ,
  https://www.postgresql.org/message-id/5a18282d-89d0-ba21-4d54-bc2259ad7f26@postgrespro.ru ; FOSDEM 2018
  "JITing PostgreSQL using LLVM" — https://archive.fosdem.org/2018/schedule/event/jiting_postgresql_using_llvm/
- DuckDB (dbdb.io) — https://dbdb.io/db/duckdb
- Neumann VLDB 2011; Kohn/Leis/Neumann ICDE 2018; Kersten/Leis/Neumann VLDB 2021; Kersten et al. VLDB 2018 (cited
  from the papers, not re-fetched).

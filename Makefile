# cursed-sqlite-turbo (qc and qvm)
#   make            the patched amalgamation and the generated decoders in build/gen (fetches SQLite)
#   make test       qc against the interpreter on the same connection: rows and JSON bodies, value by value
#   make bench      interpreter vs qc (rows / JSON), µs per statement
#   make db         the test database (build/test.db; scripts/gen-db.py)
#   make corpus     common query flavours: compiled or not (why), results vs the interpreter, speed (N=, Q=filter)
#   make qcache     the plan cache across prepares: random prepares, schema and connection changes, vs the interpreter
#   make serve      qc serving through sqlite3_step: the plain API's results, served and not, value by value
#   make regress    the wrong results found so far (SQLancer, suites, replays), each against the interpreter, both modes
#   make topn       qvm's top-N sorter (ORDER BY ... LIMIT N): random queries vs the interpreter, also with a 4-entry array
#   make par        a scan on helper threads (QV_PAR) against the interpreter; par-tsan: under ThreadSanitizer (clang)
#   make threads    qc served on many threads at once (SQLITE_THREADSAFE=1): own connections and one shared, vs the
#                   interpreter; threads-tsan, threads-asan: the same under ThreadSanitizer, AddressSanitizer (clang)
#   make stock      QC_STOCK=1: qc on SQLite's own amalgamation, unmodified (checked against its SHA-256), no hooks: test,
#                   regress (also SQLITE_THREADSAFE=2, and without qc's copies of SQLite's functions), qcache, topn, corpus; each
#                   against the interpreter. make stock-bench: tests/stockcost, patched and stock builds side by side
#   make gauntlet   the benchmarks and the differential correctness runs over real applications' statements, from
#                   sqlgauntlet (scripts/gauntlet.sh): this tree against stock SQLite; MODE=speed, GAUNTLET="options"
# THREADSAFE=1 builds everything with SQLITE_THREADSAFE=1 (default 0: the benchmarks' build)
CC ?= cc
PYTHON ?= python3
B := build
G := $(B)/gen
SQ := third_party/sqlite
UNAME_M := $(shell uname -m)
THREADSAFE ?= 0
SQLOPTS0 := -DSQLITE_DEFAULT_MEMSTATUS=0 -DSQLITE_DEFAULT_WAL_SYNCHRONOUS=1 -DSQLITE_DQS=0 \
           -DSQLITE_LIKE_DOESNT_MATCH_BLOBS -DSQLITE_USE_ALLOCA -DSQLITE_OMIT_LOAD_EXTENSION -DSQLITE_OMIT_DEPRECATED \
           -DSQLITE_OMIT_SHARED_CACHE -DSQLITE_OMIT_DECLTYPE
SQLOPTS := -DSQLITE_THREADSAFE=$(THREADSAFE) $(SQLOPTS0)
ifeq ($(UNAME_M),x86_64)
# hot loops' branches kept off 32-byte boundaries (Cascade Lake's JCC erratum microcode): otherwise any edit can move
# a loop onto one and cost it 15 % (RESULTS §13). clang's driver flag, or GNU as's through gcc
JCC := $(shell $(CC) -mbranches-within-32B-boundaries -x c -c /dev/null -o /dev/null 2>/dev/null && echo -mbranches-within-32B-boundaries || ($(CC) -Wa,-mbranches-within-32B-boundaries -x c -c /dev/null -o /dev/null 2>/dev/null && echo -Wa,-mbranches-within-32B-boundaries))
ARCH ?= -march=native $(JCC)
else
ARCH ?= -mcpu=native
endif
CFLAGS := -O2 $(ARCH) $(SQLOPTS) -I$(G) -Iqc -w
LIBS := -lm -lpthread

all: $(G)/sqlite3.c $(G)/qc_dec.h

$(SQ)/sqlite3.c:
	scripts/fetch-sqlite.sh
$(G)/sqlite3.c: $(SQ)/sqlite3.c qc/patch.py
	@mkdir -p $(G); $(PYTHON) qc/patch.py $(SQ)/sqlite3.c $@; cp $(SQ)/sqlite3.h $(G)/
$(G)/qc_dec.h: qc/gen_decoders.py
	@mkdir -p $(G); $(PYTHON) qc/gen_decoders.py $@

$(B)/test.db: scripts/gen-db.py
	@mkdir -p $(B); $(PYTHON) scripts/gen-db.py $@
db: $(B)/test.db

DEPS := $(G)/sqlite3.c $(G)/qc_dec.h qc/qc.c qc/qcg.c qc/qvm.c qc/qvm_run.h qc/qvm_par.h qc/qvm_region.h
$(B)/qtest: tests/qtest.c $(DEPS)
	$(CC) $(CFLAGS) $< -o $@ $(LIBS)
$(B)/qbench: tests/qbench.c $(DEPS)
	$(CC) $(CFLAGS) $< -o $@ $(LIBS)

test: $(B)/qtest $(B)/test.db
	cp $(B)/test.db $(B)/t.db && rm -f $(B)/t.db-wal $(B)/t.db-shm && $(B)/qtest $(B)/t.db $${BATCHES:-300} $${SEED:-1}
bench: $(B)/qbench $(B)/test.db
	$(B)/qbench $(B)/test.db
clean:
	rm -rf $(B)
.PHONY: all db test bench clean
$(B)/corpus: tests/corpus.c $(DEPS)
	$(CC) $(CFLAGS) $< -o $@ $(LIBS)
corpus: $(B)/corpus $(B)/test.db
	$(B)/corpus $(B)/test.db $${N:-20000} $${Q:-}
.PHONY: corpus
$(B)/qcache: tests/qcache.c $(DEPS)
	$(CC) $(CFLAGS) $< -o $@ $(LIBS)
qcache: $(B)/qcache   # the plan cache across prepares against the interpreter, under schema and connection changes
	$(B)/qcache $(B)/qcache.db $${N:-20000} $${SEED:-1} && QC_VM_ONLY=1 $(B)/qcache $(B)/qcache.db $${N:-20000} $${SEED:-1}
.PHONY: qcache
$(B)/topn: tests/topn.c $(DEPS)
	$(CC) $(CFLAGS) $< -o $@ $(LIBS)
$(B)/topn4: tests/topn.c $(DEPS)
	$(CC) $(CFLAGS) -DQV_TOPN_MAX=4 $< -o $@ $(LIBS)
topn: $(B)/topn $(B)/topn4   # the top-N sorter against the interpreter (topn4: moved into a B-tree on almost every run)
	$(B)/topn $${N:-2000} $${SEED:-1} && $(B)/topn4 $${N:-2000} $${SEED:-1} && QC_VM_ONLY=1 $(B)/topn $${N:-2000} $${SEED:-1}
.PHONY: topn
$(B)/regress: tests/regress.c $(DEPS)
	$(CC) $(CFLAGS) $< -o $@ $(LIBS)
$(B)/regress4: tests/regress.c $(DEPS)   # with SQLITE_ENABLE_STAT4 (better-sqlite3's): a new binding can re-prepare to another program
	$(CC) $(CFLAGS) -DSQLITE_ENABLE_STAT4 $< -o $@ $(LIBS)
$(B)/regress0: tests/regress.c $(DEPS)   # with QV_SORT_MEM=0: qvm's sorter hands its records to SQLite's at the cache size
	$(CC) $(CFLAGS) -DQV_SORT_MEM=0 $< -o $@ $(LIBS)
regress: $(B)/regress $(B)/regress4 $(B)/regress0   # every wrong result found so far, against the interpreter
	$(B)/regress && QC_VM_ONLY=1 $(B)/regress && $(B)/regress4 && QC_VM_ONLY=1 $(B)/regress4 && QC_VM_ONLY=1 $(B)/regress0
.PHONY: regress
$(B)/serve: tests/serve.c $(DEPS)
	$(CC) $(CFLAGS) $< -o $@ $(LIBS)
$(B)/serve-seek: tests/serve.c $(DEPS)
	$(CC) $(CFLAGS) -DQV_RGSEEK=1 $< -o $@ $(LIBS)
serve: $(B)/serve $(B)/serve-seek   # qc serving inside sqlite3_step against SQLite alone, through the plain API
	QC_VM_ONLY=1 $(B)/serve $${N:-3000} $${SEED:-1}
	QC_STREAM=1 QC_STREAM_MIN=0 $(B)/serve $${N:-3000} $${SEED:-1} && QC_STREAM=1 QC_STREAM_MIN=0 QC_VM_ONLY=1 $(B)/serve $${N:-3000} $${SEED:-1}   # streamed (any size)
	QC_STREAM=1 QC_STREAM_MIN=0 QC_STREAM_FAILAT=2 QC_VM_ONLY=1 $(B)/serve $${N:-3000} $${SEED:-1}   # every stream fails after 2 rows: replayed
	$(B)/serve $${N:-3000} $${SEED:-1}   # streamed past the default 32 rows (the default)
	QC_STREAM=0 $(B)/serve $${N:-3000} $${SEED:-1} && QC_STREAM=0 QC_VM_ONLY=1 $(B)/serve $${N:-3000} $${SEED:-1}   # nothing streamed
	QC_VM_ONLY=1 $(B)/serve-seek $${N:-3000} $${SEED:-1} && QC_STREAM=1 QC_STREAM_MIN=0 QC_VM_ONLY=1 $(B)/serve-seek $${N:-3000} $${SEED:-1}   # -DQV_RGSEEK=1: regions with point lookups
.PHONY: serve
$(B)/threads.db: scripts/gen-db.py   # (a small one: the sanitizers' runs)
	@mkdir -p $(B); $(PYTHON) scripts/gen-db.py $@ 2000 10000 40000
TCFLAGS := -O2 $(ARCH) -DSQLITE_THREADSAFE=1 $(SQLOPTS0) -I$(G) -Iqc -Itests -w
$(B)/threads: tests/threads.c tests/corpus.c $(DEPS)
	$(CC) $(TCFLAGS) $< -o $@ $(LIBS)
$(B)/threads-tsan: tests/threads.c tests/corpus.c $(DEPS)
	clang -O1 -g -fsanitize=thread $(filter-out -O2,$(TCFLAGS)) $< -o $@ $(LIBS)
$(B)/threads-asan: tests/threads.c tests/corpus.c $(DEPS)
	clang -O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer $(filter-out -O2,$(TCFLAGS)) $< -o $@ $(LIBS)
threads: $(B)/threads $(B)/test.db   # every thread's results against the interpreter (the full test database, a copy)
	cp $(B)/test.db $(B)/th.db && rm -f $(B)/th.db-wal $(B)/th.db-shm && $(B)/threads $(B)/th.db $${T:-8} $${N:-400} $${SEED:-1}
	cp $(B)/test.db $(B)/th.db && rm -f $(B)/th.db-wal $(B)/th.db-shm && QC_VM_ONLY=1 $(B)/threads $(B)/th.db $${T:-8} $${N:-200} $${SEED:-1}
threads-tsan: $(B)/threads-tsan $(B)/threads.db
	cp $(B)/threads.db $(B)/tht.db && rm -f $(B)/tht.db-wal $(B)/tht.db-shm && TSAN_OPTIONS="halt_on_error=1 suppressions=tests/tsan.supp" $(B)/threads-tsan $(B)/tht.db $${T:-6} $${N:-150} $${SEED:-1}
threads-asan: $(B)/threads-asan $(B)/threads.db
	cp $(B)/threads.db $(B)/tha.db && rm -f $(B)/tha.db-wal $(B)/tha.db-shm && $(B)/threads-asan $(B)/tha.db $${T:-6} $${N:-200} $${SEED:-1}
.PHONY: threads threads-tsan threads-asan
# QC_STOCK=1: third_party/sqlite/sqlite3.c as fetched (byte for byte) and qc's copies of the SQLite functions it calls,
# generated from it into build/gen-stock/qc_copies.c (qc/patch.py --copies: step 10 alone); qc.c includes them
GS := $(B)/gen-stock
SQLITE_C_SHA := 0c657666d819f261cc4007526ad57e1669de9949df7a8ea847aa284a2bf0ee52
SCFLAGS := -O2 $(ARCH) $(SQLOPTS) -DQC_STOCK=1 -I$(GS) -I$(SQ) -Iqc -w
$(GS)/qc_copies.c: $(SQ)/sqlite3.c qc/patch.py
	@mkdir -p $(GS); $(PYTHON) qc/patch.py --copies $(SQ)/sqlite3.c $@
$(GS)/qc_dec.h: qc/gen_decoders.py
	@mkdir -p $(GS); $(PYTHON) qc/gen_decoders.py $@
SDEPS := $(SQ)/sqlite3.c $(GS)/qc_copies.c $(GS)/qc_dec.h qc/qc.c qc/qcg.c qc/qvm.c qc/qvm_run.h qc/qvm_par.h qc/qvm_region.h
$(B)/%-stock: tests/%.c $(SDEPS)
	$(CC) $(SCFLAGS) $< -o $@ $(LIBS)
$(B)/regress4-stock: tests/regress.c $(SDEPS)
	$(CC) $(SCFLAGS) -DSQLITE_ENABLE_STAT4 $< -o $@ $(LIBS)
$(B)/regress2-stock: tests/regress.c $(SDEPS)   # the submission's threading mode
	$(CC) $(filter-out -DSQLITE_THREADSAFE=%,$(SCFLAGS)) -DSQLITE_THREADSAFE=2 $< -o $@ $(LIBS)
$(B)/regressnc-stock: tests/regress.c $(SDEPS)   # without qc's copies (qc calls SQLite's own functions)
	$(CC) $(SCFLAGS) -DQC_STOCK_COPIES=0 $< -o $@ $(LIBS)
$(B)/stockcost: tests/stockcost.c $(DEPS)
	$(CC) $(CFLAGS) $< -o $@ $(LIBS)
$(B)/stockcost-stock: tests/stockcost.c $(SDEPS)
	$(CC) $(SCFLAGS) $< -o $@ $(LIBS)
$(B)/stockcost-stocknc: tests/stockcost.c $(SDEPS)
	$(CC) $(SCFLAGS) -DQC_STOCK_COPIES=0 $< -o $@ $(LIBS)
stock-check: $(SQ)/sqlite3.c   # the amalgamation is SQLite 3.54.1's, unmodified
	@h=$$( (sha256sum $(SQ)/sqlite3.c 2>/dev/null || shasum -a 256 $(SQ)/sqlite3.c) | cut -d' ' -f1); \
	  [ "$$h" = "$(SQLITE_C_SHA)" ] || { echo "stock: $(SQ)/sqlite3.c is not SQLite 3.54.1's ($$h)" >&2; exit 1; }; echo "stock: $(SQ)/sqlite3.c unmodified"
STOCK_BINS := $(B)/qtest-stock $(B)/regress-stock $(B)/regress4-stock $(B)/regress2-stock $(B)/regressnc-stock $(B)/qcache-stock $(B)/topn-stock $(B)/corpus-stock
stock: stock-check $(STOCK_BINS) $(B)/test.db
	cp $(B)/test.db $(B)/ts.db && rm -f $(B)/ts.db-wal $(B)/ts.db-shm && $(B)/qtest-stock $(B)/ts.db $${BATCHES:-300} $${SEED:-1}
	$(B)/regress-stock && QC_VM_ONLY=1 $(B)/regress-stock && $(B)/regress4-stock && QC_VM_ONLY=1 $(B)/regress4-stock
	$(B)/regress2-stock && QC_VM_ONLY=1 $(B)/regressnc-stock
	$(B)/qcache-stock $(B)/qcache-stock.db $${N:-20000} $${SEED:-1} && QC_VM_ONLY=1 $(B)/qcache-stock $(B)/qcache-stock.db $${N:-20000} $${SEED:-1}
	$(B)/topn-stock $${N:-2000} $${SEED:-1} && QC_VM_ONLY=1 $(B)/topn-stock $${N:-2000} $${SEED:-1}
	$(B)/corpus-stock $(B)/test.db 2000 > $(B)/corpus-stock.txt; r=$$?; tail -1 $(B)/corpus-stock.txt; exit $$r
stock-bench: $(B)/stockcost $(B)/stockcost-stock $(B)/stockcost-stocknc $(B)/test.db   # the feed and a post by id, JSON, autocommit
	@for r in 1 2 3; do for q in "feed json 20000" "get json 100000" "feed interp 4000"; do for b in stockcost stockcost-stock stockcost-stocknc; do \
	  printf '%-18s ' $$b; $(B)/$$b $(B)/test.db $$q; done; done; done
.PHONY: stock stock-check stock-bench
# the Lean model as an oracle (lean/, docs/LEAN.md): its cases against SQLite and turbo's fast paths, both modes
LAKE ?= lake
lean/Turbo/Generated.lean: lean/gen_twins.py $(G)/qc_dec.h   # the generated decoders' twins, proved in the build (not committed)
	$(PYTHON) lean/gen_twins.py $(G)/qc_dec.h $@
lean: lean/Turbo/Generated.lean   # the model and every proof (lake build)
	cd lean && $(LAKE) build
$(B)/lean-cases.txt: lean/Oracle.lean $(wildcard lean/Turbo/*.lean) lean/Turbo/Generated.lean
	cd lean && $(LAKE) build
	lean/.lake/build/bin/oracle $${SEED:-1} $${N:-20000} $${TABLES:-200} $${RECORDS:-3000} $${LIKES:-400} > $@
$(B)/lean_oracle: tests/lean_oracle.c $(DEPS)
	$(CC) $(CFLAGS) -DSQLITE_ENABLE_DBPAGE_VTAB $< -o $@ $(LIBS)   # (sqlite_dbpage: records written into pages)
lean-oracle: $(B)/lean_oracle $(B)/lean-cases.txt
	LEAN_ORACLE_STRICT=1 $(B)/lean_oracle $(B)/lean-cases.txt && LEAN_ORACLE_STRICT=1 QC_VM_ONLY=1 $(B)/lean_oracle $(B)/lean-cases.txt
.PHONY: lean lean-oracle
$(B)/par: tests/par.c $(DEPS)
	$(CC) $(TCFLAGS) $< -o $@ $(LIBS)
$(B)/par-tsan: tests/par.c $(DEPS)
	clang -O1 -g -fsanitize=thread $(filter-out -O2,$(TCFLAGS)) $< -o $@ $(LIBS)
par: $(B)/par   # scans on helper threads (QV_PAR) against the interpreter: off, no helper, 1 and 3, in memory and in a file with a small cache
	QC_STATS=1 $(B)/par $${N:-200} $${SEED:-1} && QC_STATS=1 QV_PAR=0 $(B)/par $${N:-200} $${SEED:-1} && QC_STATS=1 QV_PAR=1 $(B)/par $${N:-200} $${SEED:-1} && QC_STATS=1 QV_PAR=3 $(B)/par $${N:-200} $${SEED:-1}
	QC_STATS=1 QV_PAR=3 PAR_DB=$(B)/par.db PAR_CACHE=100 $(B)/par $${N:-200} $${SEED:-1}
par-tsan: $(B)/par-tsan
	TSAN_OPTIONS="halt_on_error=1 suppressions=tests/tsan.supp" QC_STATS=1 QV_PAR=3 PAR_DB=$(B)/part.db $(B)/par-tsan $${N:-60} $${SEED:-1}
.PHONY: par par-tsan
# sqlgauntlet (scripts/gauntlet.sh pins its commit): this checkout as its backend turbo, against stock SQLite
gauntlet:
	sh scripts/gauntlet.sh $${MODE:-check} $(GAUNTLET)
.PHONY: gauntlet

# Git hooks in .githooks/ (Conventional Commits: scripts/check-commit-msg.sh).
hooks:
	git config core.hooksPath .githooks
.PHONY: hooks

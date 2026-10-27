# cursed-sqlite-turbo (qc and qvm)
#   make            the patched amalgamation and the generated decoders in build/gen (fetches SQLite)
#   make test       qc against the interpreter on the same connection: rows and JSON bodies, value by value
#   make bench      interpreter vs qc (rows / JSON), µs per statement
#   make db         the test database (build/test.db; scripts/gen-db.py)
#   make corpus     common query flavours: compiled or not (why), results vs the interpreter, speed (N=, Q=filter)
#   make qcache     the plan cache across prepares: random prepares, schema and connection changes, vs the interpreter
#   make regress    the wrong results found so far (SQLancer, suites, replays), each against the interpreter, both modes
#   make topn       qvm's top-N sorter (ORDER BY ... LIMIT N): random queries vs the interpreter, also with a 4-entry array
CC ?= cc
PYTHON ?= python3
B := build
G := $(B)/gen
SQ := third_party/sqlite
UNAME_M := $(shell uname -m)
SQLOPTS := -DSQLITE_THREADSAFE=0 -DSQLITE_DEFAULT_MEMSTATUS=0 -DSQLITE_DEFAULT_WAL_SYNCHRONOUS=1 -DSQLITE_DQS=0 \
           -DSQLITE_LIKE_DOESNT_MATCH_BLOBS -DSQLITE_USE_ALLOCA -DSQLITE_OMIT_LOAD_EXTENSION -DSQLITE_OMIT_DEPRECATED \
           -DSQLITE_OMIT_SHARED_CACHE -DSQLITE_OMIT_DECLTYPE
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

DEPS := $(G)/sqlite3.c $(G)/qc_dec.h qc/qc.c qc/qcg.c qc/qvm.c qc/qvm_run.h
$(B)/qtest: tests/qtest.c $(DEPS)
	$(CC) $(CFLAGS) $< -o $@ $(LIBS)
$(B)/qbench: bench/qbench.c $(DEPS)
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
regress: $(B)/regress   # every wrong result found so far, against the interpreter
	$(B)/regress && QC_VM_ONLY=1 $(B)/regress
.PHONY: regress
# the Lean model as an oracle (lean/, docs/LEAN.md): its cases against SQLite and turbo's fast paths, both modes
LAKE ?= lake
$(B)/lean-cases.txt: lean/Oracle.lean $(wildcard lean/Turbo/*.lean)
	@mkdir -p $(B); cd lean && $(LAKE) build oracle
	lean/.lake/build/bin/oracle $${SEED:-1} $${N:-20000} $${TABLES:-200} $${RECORDS:-3000} > $@
$(B)/lean_oracle: tests/lean_oracle.c $(DEPS)
	$(CC) $(CFLAGS) -DSQLITE_ENABLE_DBPAGE_VTAB $< -o $@ $(LIBS)   # (sqlite_dbpage: records written into pages)
lean-oracle: $(B)/lean_oracle $(B)/lean-cases.txt
	$(B)/lean_oracle $(B)/lean-cases.txt && QC_VM_ONLY=1 $(B)/lean_oracle $(B)/lean-cases.txt
.PHONY: lean-oracle

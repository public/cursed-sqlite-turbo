# cursed-sqlite-jit (qc)
#   make            the patched amalgamation and the generated decoders in build/gen (fetches SQLite)
#   make test       qc against the interpreter on the same connection: rows and JSON bodies, value by value
#   make bench      interpreter vs qc (rows / JSON), µs per statement
#   make db         the test database (build/test.db; scripts/gen-db.py)
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
ARCH ?= -march=native
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

DEPS := $(G)/sqlite3.c $(G)/qc_dec.h qc/qc.c
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

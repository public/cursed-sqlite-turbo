/* qc_wasm.c: qc for SQLite's JS API (ext/wasm). Appended to the patched amalgamation and qc.c by wasm/build.sh, so it
** compiles in the same unit as sqlite3-wasm.c. The exports are EMSCRIPTEN_KEEPALIVE: they show up in
** sqlite3.wasm.exports without touching ext/wasm's export list. wasm/qc.mjs wraps them for oo1 statements.
**
**   int sqlite3_qc_wasm_compile(stmt)       sqlite3_qc: 1 = compiled
**   void sqlite3_qc_wasm_release(void)      sqlite3_qc_release, and this file's buffer
**   int sqlite3_qc_wasm_exec(stmt)          run the plan; SQLITE_OK: the rows are in the buffer below,
**                                           QC_FALLBACK (-1): step the statement instead (nothing was written)
**   const u8 *sqlite3_qc_wasm_buf(void)     the rows of the last run, in the format below
**   int sqlite3_qc_wasm_len(void)           its length in bytes
**   const char *sqlite3_qc_wasm_why(void)   the last fallback's reason
**
** The rows (little-endian, unaligned): u32 ncol, u32 nrow, then nrow * ncol values, each a type byte (SQLite's
** SQLITE_INTEGER ... SQLITE_NULL) and its payload: i64 / f64 (8 bytes), u32 n + n bytes (text, blob), nothing (NULL).
** qc hands its values out as pointers into the database pages that are valid during its callback: they are copied
** here, and the buffer belongs to qc_wasm until the next run. */
#include <emscripten.h>

static u8 *qcw_buf; static u32 qcw_cap, qcw_len; static int qcw_oom;
static u8 *qcw_room(u32 n) {
  if (qcw_len + n > qcw_cap) {
    u32 c = qcw_cap ? qcw_cap : 4096; while (c < qcw_len + n) c *= 2;
    u8 *b = sqlite3_realloc(qcw_buf, (int)c); if (!b) { qcw_oom = 1; return 0; }
    qcw_buf = b; qcw_cap = c;
  }
  u8 *p = qcw_buf + qcw_len; qcw_len += n; return p;
}
static int qcw_rows(void *ctx, int nrow, int ncol, const QcVal *v) {   /* may be called more than once per run */
  (void)ctx;
  if (qcw_len < 8 && !qcw_room(8 - qcw_len)) return SQLITE_NOMEM;
  u32 hdr[2]; memcpy(hdr, qcw_buf, 8); hdr[0] = (u32)ncol; hdr[1] += (u32)nrow; memcpy(qcw_buf, hdr, 8);
  for (int k = 0; k < nrow * ncol; k++) {
    u8 *p;
    switch (v[k].type) {
      case SQLITE_INTEGER: case SQLITE_FLOAT:
        if (!(p = qcw_room(9))) return SQLITE_NOMEM;
        p[0] = (u8)v[k].type; memcpy(p + 1, &v[k].i, 8); break;
      case SQLITE_TEXT: case SQLITE_BLOB: {
        u32 n = (u32)v[k].n;
        if (!(p = qcw_room(5 + n))) return SQLITE_NOMEM;
        p[0] = (u8)v[k].type; memcpy(p + 1, &n, 4); if (n) memcpy(p + 5, v[k].z, n); break;
      }
      default:
        if (!(p = qcw_room(1))) return SQLITE_NOMEM;
        p[0] = SQLITE_NULL; break;
    }
  }
  return SQLITE_OK;
}
EMSCRIPTEN_KEEPALIVE int sqlite3_qc_wasm_exec(sqlite3_stmt *pStmt) {
  qcw_len = 0; qcw_oom = 0;
  if (!qcw_room(8)) return SQLITE_NOMEM;
  memset(qcw_buf, 0, 8);
  int rc = sqlite3_qc_exec(pStmt, qcw_rows, 0);
  if (rc == SQLITE_OK && qcw_oom) rc = SQLITE_NOMEM;
  return rc;
}
EMSCRIPTEN_KEEPALIVE const u8 *sqlite3_qc_wasm_buf(void) { return qcw_buf; }
EMSCRIPTEN_KEEPALIVE int sqlite3_qc_wasm_len(void) { return (int)qcw_len; }
EMSCRIPTEN_KEEPALIVE const char *sqlite3_qc_wasm_why(void) { return qc_why; }
/* sqlite3_qc and sqlite3_qc_release are SQLITE_API in qc.c; kept alive here so the JS side finds them */
EMSCRIPTEN_KEEPALIVE int sqlite3_qc_wasm_compile(sqlite3_stmt *pStmt) { return sqlite3_qc(pStmt); }
EMSCRIPTEN_KEEPALIVE void sqlite3_qc_wasm_release(void) { sqlite3_free(qcw_buf); qcw_buf = 0; qcw_cap = qcw_len = 0; sqlite3_qc_release(); }

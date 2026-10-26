// qc.mjs: qc for SQLite's JS API (the jsapi/jit bundle of wasm/build.sh). installQc(sqlite3) adds two methods to
// oo1 statements:
//   stmt.qc()       compile the statement (sqlite3_qc): true = compiled; false = not a shape qc handles, nothing changes
//   stmt.qcAll()    run it with its current bindings and return every row as an array of values, as
//                   stmt.get([]) after each step() would. A compiled statement runs its plan (wasm/qc_wasm.c); one
//                   that is not, or whose plan falls back (autocommit, a value the plan can't reproduce), is stepped.
//                   The statement is reset afterwards, bindings kept.
// As in C, plans only run inside a transaction (BEGIN ... COMMIT); in autocommit mode qcAll() steps the statement.
// Values: INTEGER as a Number, or a BigInt outside Number's safe range; REAL as a Number; TEXT as a string; BLOB as a
// Uint8Array; NULL as null.
const QC_FALLBACK = -1;

export function installQc(sqlite3) {
  const { wasm, oo1 } = sqlite3, x = wasm.exports;
  if (!x.sqlite3_qc_wasm_exec) throw new Error('qc.mjs: this sqlite3.wasm has no qc (build it with wasm/build.sh jsapi)');
  const td = new TextDecoder();
  const P = oo1.Stmt.prototype;
  P.qc = function () { return x.sqlite3_qc_wasm_compile(this.pointer) === 1; };
  P.qcAll = function () {
    const rc = x.sqlite3_qc_wasm_exec(this.pointer);
    if (rc === QC_FALLBACK) {
      const rows = [];
      try { while (this.step()) rows.push(this.get([])); } finally { this.reset(); }
      return rows;
    }
    if (rc !== 0) sqlite3.SQLite3Error.toss(rc, 'sqlite3_qc_exec');
    return decode(wasm.heap8u(), Number(x.sqlite3_qc_wasm_buf()), x.sqlite3_qc_wasm_len());
  };
  sqlite3.qcWhy = () => wasm.cstrToJs(x.sqlite3_qc_wasm_why());
  sqlite3.qcRelease = () => x.sqlite3_qc_wasm_release();

  function decode(heap, p, len) {   // the format in wasm/qc_wasm.c
    if (len < 8) return [];
    const dv = new DataView(heap.buffer, heap.byteOffset + p, len);
    const ncol = dv.getUint32(0, true), nrow = dv.getUint32(4, true), rows = new Array(nrow);
    let o = 8;
    for (let r = 0; r < nrow; r++) {
      const row = new Array(ncol);
      for (let c = 0; c < ncol; c++) {
        const t = heap[p + o++];
        if (t === 1) {   // SQLITE_INTEGER
          const lo = dv.getUint32(o, true), hi = dv.getInt32(o + 4, true); o += 8;
          // within Number.MIN_SAFE_INTEGER ... MAX_SAFE_INTEGER (|v| < 2^53) a Number, as oo1's get() does
          row[c] = hi >= -0x200000 && hi < 0x200000 && !(hi === -0x200000 && lo === 0) ? hi * 4294967296 + lo
                 : dv.getBigInt64(o - 8, true);
        } else if (t === 2) { row[c] = dv.getFloat64(o, true); o += 8; }   // SQLITE_FLOAT
        else if (t === 3 || t === 4) {   // SQLITE_TEXT, SQLITE_BLOB
          const n = dv.getUint32(o, true); o += 4;
          row[c] = t === 3 ? td.decode(heap.subarray(p + o, p + o + n)) : heap.slice(p + o, p + o + n); o += n;
        } else row[c] = null;
      }
      rows[r] = row;
    }
    return rows;
  }
}

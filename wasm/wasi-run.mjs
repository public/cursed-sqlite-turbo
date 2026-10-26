// wasi-run.mjs <program.wasm> [args...]: a WASI (preview 1) program under Node's node:wasi, with the current directory
// preopened as "." (so relative paths in args work) and the environment passed through. wasmtime does the same:
// wasmtime run --dir . <program.wasm> [args...]
import fs from 'node:fs';
import { WASI } from 'node:wasi';
const [prog, ...args] = process.argv.slice(2);
if (!prog) { console.error('usage: node wasm/wasi-run.mjs <program.wasm> [args...]'); process.exit(2); }
const wasi = new WASI({ version: 'preview1', args: [prog, ...args], env: process.env, preopens: { '.': process.cwd() }, returnOnExit: true });
const { instance } = await WebAssembly.instantiate(fs.readFileSync(prog), wasi.getImportObject());
process.exitCode = wasi.start(instance);

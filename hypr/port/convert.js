// Local runner for the hyprlang2lua wasm converter (no install needed).
const fs = require("fs");
require("./wasm_exec.js");

const [, , inFile, outFile] = process.argv;
if (!inFile) {
  console.error("usage: node convert.js <in.conf> [out.lua]");
  process.exit(2);
}
const src = fs.readFileSync(inFile, "utf8");

(async () => {
  const go = new Go();
  const { instance } = await WebAssembly.instantiate(fs.readFileSync("main.wasm"), go.importObject);
  go.run(instance); // starts the Go runtime, main blocks in select{}

  for (let i = 0; i < 500 && !globalThis.hyprlang2lua; i++) {
    await new Promise((r) => setTimeout(r, 10));
  }
  if (!globalThis.hyprlang2lua) {
    console.error("converter never started");
    process.exit(1);
  }

  const res = globalThis.hyprlang2lua.convert(src, {});
  if (res.error) {
    console.error("error:", res.error);
    process.exit(1);
  }
  if (outFile) fs.writeFileSync(outFile, res.lua);
  else process.stdout.write(res.lua);

  console.error(
    `translated=${res.translated} passthrough=${res.passthrough} flagged=${res.flagged} coverage=${res.coverage}%`
  );
  for (const n of res.notes || []) console.error("note:", n);
  process.exit(res.flagged ? 3 : 0);
})();

// Compares src/layout.ts with the engine's tables and prints the demo word pairs.
// Run: bun scripts/verify-layout.ts
import { readFileSync } from "node:fs";
import { TABLES, typedInWrongLayout } from "../src/layout";

const rust = readFileSync(
  new URL("../../engine/src/layout.rs", import.meta.url),
  "utf8",
);

const table = (name: string) => {
  const body = rust.split(`const ${name}: [Glyph; 47] = [`)[1].split("];")[0];
  const glyphs = [
    ...body.matchAll(/Glyph::new\('((?:\\.|[^'\\]))', '((?:\\.|[^'\\]))'\)/gu),
  ];
  const unescape = (value: string) => value.replace(/^\\(.)$/u, "$1");
  return {
    plain: glyphs.map((glyph) => unescape(glyph[1])).join(""),
    shifted: glyphs.map((glyph) => unescape(glyph[2])).join(""),
  };
};

const engine = { US: table("US"), UA: table("UKRAINIAN_PC") };
let failed = false;
for (const code of ["US", "UA"] as const) {
  for (const row of ["plain", "shifted"] as const) {
    const same = engine[code][row] === TABLES[code][row];
    const count = [...engine[code][row]].length;
    console.log(`${same ? "ok  " : "FAIL"} ${code}.${row} (${count} keys)`);
    if (!same || count !== 47) {
      failed = true;
      console.log(`  engine: ${engine[code][row]}`);
      console.log(`  video:  ${TABLES[code][row]}`);
    }
  }
}

console.log("привіт     ->", typedInWrongLayout("привіт", "UA"));
console.log("hello      ->", typedInWrongLayout("hello", "US"));
console.log("MovaSwitch ->", typedInWrongLayout("MovaSwitch", "US"));
process.exit(failed ? 1 : 0);

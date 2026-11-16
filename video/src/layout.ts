// Key tables mirror engine/src/layout.rs (U.S. and Apple "Ukrainian – PC").
// scripts/verify-layout.ts fails if they drift from the engine.
export type LayoutCode = "US" | "UA";

export const TABLES: Record<LayoutCode, { plain: string; shifted: string }> = {
  US: {
    plain: "`1234567890-=qwertyuiop[]\\asdfghjkl;'zxcvbnm,./",
    shifted: '~!@#$%^&*()_+QWERTYUIOP{}|ASDFGHJKL:"ZXCVBNM<>?',
  },
  UA: {
    plain: "ґ1234567890-=йцукенгшщзхїʼфівапролджєячсмитьбю.",
    shifted: 'Ґ!"№;%:?*()_+ЙЦУКЕНГШЩЗХЇ₴ФІВАПРОЛДЖЄЯЧСМИТЬБЮ,',
  },
};

const other = (layout: LayoutCode): LayoutCode =>
  layout === "US" ? "UA" : "US";

/** What `intended` looks like when its keys are pressed with the other layout active. */
export const typedInWrongLayout = (
  intended: string,
  intendedLayout: LayoutCode,
): string => {
  const from = TABLES[intendedLayout];
  const to = TABLES[other(intendedLayout)];
  return [...intended]
    .map((character) => {
      const plainIndex = [...from.plain].indexOf(character);
      if (plainIndex >= 0) return [...to.plain][plainIndex];
      const shiftedIndex = [...from.shifted].indexOf(character);
      if (shiftedIndex >= 0) return [...to.shifted][shiftedIndex];
      throw new Error(`"${character}" is not on the ${intendedLayout} layout`);
    })
    .join("");
};

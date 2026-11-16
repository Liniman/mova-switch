// The sound set, shared by scripts/make-sfx.ts (which writes the WAVs)
// and src/cues.ts (which places them on the timeline).
export const SAMPLE_RATE = 48000;

export const KEY_VARIANTS = 8;
export const DELETE_VARIANTS = 3;
export const SPACE_VARIANTS = 3;

// C major pentatonic from C5: one step per letter position in a flipped word.
export const TICK_SCALE = [
  523.25, 587.33, 659.25, 783.99, 880.0, 1046.5, 1174.66, 1318.51, 1567.98,
  1760.0,
];

export const SFX_SECONDS = {
  key: 0.09,
  delete: 0.09,
  modifier: 0.1,
  space: 0.18,
  tick: 0.12,
  land: 0.6,
  undo: 0.5,
  thud: 0.3,
  fact: 0.16,
  resolve: 2.0,
} as const;

export type SfxKind = keyof typeof SFX_SECONDS;

export const sfxFile = (kind: SfxKind, variant?: number) =>
  `sfx/${kind}${variant === undefined ? "" : `-${variant}`}.wav`;

// Small deterministic generator, so variation is the same on every render.
export const seeded = (seed: number) => {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let mixed = state;
    mixed = Math.imul(mixed ^ (mixed >>> 15), mixed | 1);
    mixed ^= mixed + Math.imul(mixed ^ (mixed >>> 7), mixed | 61);
    return ((mixed ^ (mixed >>> 14)) >>> 0) / 4294967296;
  };
};

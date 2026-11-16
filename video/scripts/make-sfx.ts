// Synthesises every sound in public/sfx from scratch. No samples, no downloads.
// Run: bun scripts/make-sfx.ts
import { mkdirSync, writeFileSync } from "node:fs";
import {
  DELETE_VARIANTS,
  KEY_VARIANTS,
  SAMPLE_RATE,
  seeded,
  SFX_SECONDS,
  sfxFile,
  SPACE_VARIANTS,
  TICK_SCALE,
  type SfxKind,
} from "../src/sfx";

const TAU = Math.PI * 2;
const random = seeded(4711);
const publicDir = new URL("../public/", import.meta.url);

type Samples = Float64Array;

const blank = (seconds: number): Samples =>
  new Float64Array(Math.round(seconds * SAMPLE_RATE));

const noise = (seconds: number): Samples =>
  blank(seconds).map(() => random() * 2 - 1);

const mix = (...layers: Samples[]): Samples =>
  layers[0].map((_, index) =>
    layers.reduce((sum, layer) => sum + (layer[index] ?? 0), 0),
  );

const shape = (samples: Samples, at: (time: number) => number): Samples =>
  samples.map((value, index) => value * at(index / SAMPLE_RATE));

const decay =
  (tau: number, from = 0) =>
  (time: number) =>
    time < from ? 0 : Math.exp(-(time - from) / tau);

// Second-order filters from the RBJ audio EQ cookbook.
const biquad = (
  samples: Samples,
  kind: "low" | "high",
  cutoff: number,
  q = Math.SQRT1_2,
): Samples => {
  const omega = (TAU * cutoff) / SAMPLE_RATE;
  const alpha = Math.sin(omega) / (2 * q);
  const cosine = Math.cos(omega);
  const edge = kind === "low" ? 1 - cosine : 1 + cosine;
  const b0 = edge / 2;
  const b1 = kind === "low" ? edge : -edge;
  const a0 = 1 + alpha;
  const a1 = -2 * cosine;
  const a2 = 1 - alpha;
  const out = new Float64Array(samples.length);
  let x1 = 0;
  let x2 = 0;
  let y1 = 0;
  let y2 = 0;
  for (let index = 0; index < samples.length; index++) {
    const x0 = samples[index];
    const y0 = (b0 * x0 + b1 * x1 + b0 * x2 - a1 * y1 - a2 * y2) / a0;
    out[index] = y0;
    x2 = x1;
    x1 = x0;
    y2 = y1;
    y1 = y0;
  }
  return out;
};

const lowpass = (samples: Samples, cutoff: number) =>
  biquad(biquad(samples, "low", cutoff), "low", cutoff);
const highpass = (samples: Samples, cutoff: number) =>
  biquad(samples, "high", cutoff);

// A sine whose pitch can glide; phase is integrated so glides stay smooth.
const sine = (
  seconds: number,
  frequency: number | ((time: number) => number),
): Samples => {
  let phase = 0;
  return blank(seconds).map((_, index) => {
    const value = Math.sin(phase);
    const now =
      typeof frequency === "number"
        ? frequency
        : frequency(index / SAMPLE_RATE);
    phase += (TAU * now) / SAMPLE_RATE;
    return value;
  });
};

const glide = (from: number, to: number, over: number) => (time: number) =>
  to + (from - to) * Math.exp(-time / over);

// Raised-cosine edges so no file starts or ends on a step.
const edges = (samples: Samples, attack: number, release: number): Samples => {
  const total = samples.length / SAMPLE_RATE;
  return shape(samples, (time) => {
    const rise =
      time < attack ? 0.5 - 0.5 * Math.cos((Math.PI * time) / attack) : 1;
    const left = total - time;
    const fall =
      left < release ? 0.5 - 0.5 * Math.cos((Math.PI * left) / release) : 1;
    return rise * fall;
  });
};

// One trim for the whole set; the mixed video peaks near -6 dBFS with this.
const MASTER = 1.15;

// Nothing harsh on top, then scale so the loudest sample sits at `peak`.
const finish = (samples: Samples, peak: number, ceiling = 7000): Samples => {
  const smooth = lowpass(samples, ceiling);
  const loudest = smooth.reduce(
    (max, value) => Math.max(max, Math.abs(value)),
    0,
  );
  return smooth.map((value) => (value / loudest) * peak * MASTER);
};

const write = (kind: SfxKind, samples: Samples, variant?: number) => {
  const data = Buffer.alloc(samples.length * 4);
  samples.forEach((value, index) => {
    const quantised = Math.round(Math.max(-1, Math.min(1, value)) * 32767);
    data.writeInt16LE(quantised, index * 4);
    data.writeInt16LE(quantised, index * 4 + 2);
  });
  const header = Buffer.alloc(44);
  header.write("RIFF", 0);
  header.writeUInt32LE(36 + data.length, 4);
  header.write("WAVEfmt ", 8);
  header.writeUInt32LE(16, 16);
  header.writeUInt16LE(1, 20); // PCM
  header.writeUInt16LE(2, 22); // stereo
  header.writeUInt32LE(SAMPLE_RATE, 24);
  header.writeUInt32LE(SAMPLE_RATE * 4, 28);
  header.writeUInt16LE(4, 32);
  header.writeUInt16LE(16, 34);
  header.write("data", 36);
  header.writeUInt32LE(data.length, 40);
  const file = sfxFile(kind, variant);
  writeFileSync(new URL(file, publicDir), Buffer.concat([header, data]));
  const peak = samples.reduce(
    (max, value) => Math.max(max, Math.abs(value)),
    0,
  );
  console.log(
    `${file.padEnd(20)} ${(samples.length / SAMPLE_RATE).toFixed(2)} s  peak ${(20 * Math.log10(peak)).toFixed(1)} dBFS`,
  );
};

// A key switch: a tiny filtered-noise snap, a short woody body, and a much
// quieter snap on the way back up.
const keyClick = (
  kind: "key" | "delete" | "modifier",
  body: number,
  bright: number,
  peak: number,
) => {
  const seconds = SFX_SECONDS[kind];
  const pitch = 1 + (random() - 0.5) * 0.16;
  const release = 0.046 + random() * 0.012;
  const snap = shape(
    lowpass(highpass(noise(seconds), 1500 * pitch), bright * pitch),
    (time) => 2.4 * decay(0.003)(time),
  );
  const upstroke = shape(
    lowpass(highpass(noise(seconds), 2200 * pitch), bright * pitch),
    (time) => 0.5 * decay(0.002, release)(time),
  );
  const wood = shape(
    sine(seconds, body * pitch),
    (time) => 0.7 * decay(0.014)(time),
  );
  const knock = shape(
    sine(seconds, body * pitch * 2.6),
    (time) => 0.3 * decay(0.006)(time),
  );
  return finish(edges(mix(snap, upstroke, wood, knock), 0.0003, 0.008), peak);
};

// The spacebar: lower, longer and rounder than a letter key.
const spaceThock = () => {
  const seconds = SFX_SECONDS.space;
  const pitch = 1 + (random() - 0.5) * 0.1;
  const body = shape(
    sine(seconds, glide(128 * pitch, 96 * pitch, 0.03)),
    decay(0.036),
  );
  const overtone = shape(
    sine(seconds, 250 * pitch),
    (time) => 0.3 * decay(0.016)(time),
  );
  const snap = shape(
    lowpass(noise(seconds), 2400),
    (time) => 0.5 * decay(0.004)(time),
  );
  return finish(edges(mix(body, overtone, snap), 0.0005, 0.02), 0.2, 5000);
};

// One letter turning over: a soft pitched blip with a hint of an octave.
const flipTick = (frequency: number) => {
  const seconds = SFX_SECONDS.tick;
  const tone = shape(sine(seconds, frequency), decay(0.028));
  const octave = shape(
    sine(seconds, frequency * 2),
    (time) => 0.2 * decay(0.014)(time),
  );
  const touch = shape(
    lowpass(highpass(noise(seconds), 2000), 5500),
    (time) => 0.15 * decay(0.0015)(time),
  );
  const level = 0.17 * (TICK_SCALE[0] / frequency) ** 0.3;
  return finish(edges(mix(tone, octave, touch), 0.001, 0.02), level);
};

// Decaying sine partials with a soft low pop underneath.
const chime = (
  kind: "land" | "undo",
  partials: [frequency: number, level: number, tau: number][],
  pop: [from: number, to: number],
  peak: number,
) => {
  const seconds = SFX_SECONDS[kind];
  const tones = partials.map(([frequency, level, tau]) =>
    shape(sine(seconds, frequency), (time) => level * decay(tau)(time)),
  );
  const thump = shape(
    sine(seconds, glide(pop[0], pop[1], 0.02)),
    (time) => 0.7 * decay(0.018)(time),
  );
  return finish(edges(mix(...tones, thump), 0.002, 0.08), peak, 6000);
};

// The "ugh": a dull knock, mostly below 200 Hz.
const thud = () => {
  const seconds = SFX_SECONDS.thud;
  const body = shape(sine(seconds, glide(150, 72, 0.04)), decay(0.06));
  const knock = shape(
    lowpass(noise(seconds), 500),
    (time) => 0.5 * decay(0.02)(time),
  );
  return finish(edges(mix(body, knock), 0.003, 0.06), 0.2, 1200);
};

// A fact arriving: one soft, slightly woody tick.
const factTick = () => {
  const seconds = SFX_SECONDS.fact;
  const tone = shape(sine(seconds, 659.25), decay(0.035));
  const overtone = shape(
    sine(seconds, 1318.51),
    (time) => 0.25 * decay(0.015)(time),
  );
  const touch = shape(
    lowpass(highpass(noise(seconds), 1500), 5000),
    (time) => 0.2 * decay(0.002)(time),
  );
  return finish(edges(mix(tone, overtone, touch), 0.001, 0.03), 0.19);
};

// The end card: an open C major voicing, each partial doubled slightly sharp
// so it shimmers slowly instead of sitting dead still.
const resolve = () => {
  const seconds = SFX_SECONDS.resolve;
  const partials: [number, number][] = [
    [261.63, 1],
    [392.0, 0.7],
    [523.25, 0.6],
    [659.25, 0.35],
    [783.99, 0.15],
  ];
  const tones = partials.flatMap(([frequency, level]) => [
    shape(sine(seconds, frequency), (time) => level * decay(0.55)(time)),
    shape(
      sine(seconds, frequency * 1.004),
      (time) => level * 0.5 * decay(0.55)(time),
    ),
  ]);
  return finish(edges(mix(...tones), 0.025, 0.35), 0.34, 5000);
};

mkdirSync(new URL("sfx/", publicDir), { recursive: true });

for (let take = 0; take < KEY_VARIANTS; take++) {
  write("key", keyClick("key", 430, 5200, 0.1), take);
}
for (let take = 0; take < DELETE_VARIANTS; take++) {
  write("delete", keyClick("delete", 330, 3600, 0.1), take);
}
write("modifier", keyClick("modifier", 300, 4200, 0.14));
for (let take = 0; take < SPACE_VARIANTS; take++) {
  write("space", spaceThock(), take);
}
TICK_SCALE.forEach((frequency, step) =>
  write("tick", flipTick(frequency), step),
);
write(
  "land",
  chime(
    "land",
    [
      [523.25, 1, 0.16],
      [783.99, 0.5, 0.13],
      [1046.5, 0.45, 0.1],
      [1318.51, 0.18, 0.08],
    ],
    [420, 180],
    0.34,
  ),
);
write(
  "undo",
  chime(
    "undo",
    [
      [392.0, 1, 0.14],
      [261.63, 0.6, 0.16],
      [523.25, 0.3, 0.1],
    ],
    [300, 140],
    0.32,
  ),
);
write("thud", thud());
write("fact", factTick());
write("resolve", resolve());

import { typedInWrongLayout, type LayoutCode } from "./layout";

export const FPS = 30;

export type Key = { at: number; ch: string };
export type Flip = { at: number; to: string; reverse?: boolean };
export type Line = {
  start: number;
  keys: Key[];
  deletes?: number[];
  flips?: Flip[];
  squiggleAt?: number;
  clearAt?: number;
};

export const FLIP_FRAMES = 12;
export const FLIP_STAGGER = 3;
export const CLEAR_FRAMES = 10;

const CADENCE = [4, 5, 4, 4, 5, 4, 5];

const type = (start: number, text: string): Key[] => {
  let at = start;
  return [...text].map((ch, index) => {
    const key = { at, ch };
    at += CADENCE[index % CADENCE.length];
    return key;
  });
};

const pryvit = "привіт";
const pryvitWrong = typedInWrongLayout(pryvit, "UA"); // ghbdsn
const hello = "hello";
const helloWrong = typedInWrongLayout(hello, "US"); // руддщ

// Beat 1: the pain. Wrong word, a beat, then delete it by hand.
const pain: Line = {
  start: 0,
  keys: type(16, pryvitWrong),
  squiggleAt: 50,
  deletes: [82, 87, 92, 97, 102, 107],
};

// Beat 2: same typing, Space fixes it, typing carries on.
const fixUkrainian: Line = {
  start: 120,
  keys: [
    ...type(138, pryvitWrong),
    { at: 172, ch: " " },
    ...type(222, "як"),
    { at: 232, ch: " " },
    ...type(238, "справи"),
  ],
  flips: [{ at: 175, to: pryvit }],
  clearAt: 284,
};

const fixEnglish: Line = {
  start: 296,
  keys: [...type(300, helloWrong), { at: 330, ch: " " }, ...type(374, "again")],
  flips: [{ at: 333, to: hello }],
  clearAt: 414,
};

// Beat 3: a conversion, then Right Option puts the original back.
const undo: Line = {
  start: 426,
  keys: [...type(430, pryvitWrong), { at: 462, ch: " " }],
  flips: [
    { at: 465, to: pryvit },
    { at: 519, to: pryvitWrong, reverse: true },
  ],
};

export const LINES: Line[] = [pain, fixUkrainian, fixEnglish, undo];

export const SHAKE_AT = 50;

export const CHIP_FLIP_FRAMES = 18;
export const CHIP_FLIPS: { at: number; to: LayoutCode; undo?: boolean }[] = [
  { at: 178, to: "UA" },
  { at: 336, to: "US" },
  { at: 468, to: "UA" },
  { at: 522, to: "US", undo: true },
];

export const STATUS_IN = 120;
export const STATUS_PULSES = [175, 333, 465, 519];

export const DELETE_KEY = { in: 66, out: 112, presses: pain.deletes ?? [] };
export const SPACE_KEY = { in: 124, presses: [172, 232, 330, 462] };
export const OPTION_KEY = { in: 424, presses: [516] };

export const DEMO_OUT = 566;
export const DEMO_END = 580;

export const FACT_STARTS = [580, 624, 668];
export const FACT_FRAMES = 44;

export const END_CARD_AT = 712;
export const END_CARD_FRAMES = 128;
export const TOTAL_FRAMES = END_CARD_AT + END_CARD_FRAMES;

export const WORDMARK = "MovaSwitch";
export const WORDMARK_WRONG = typedInWrongLayout(WORDMARK, "US");

// The name arrives the way the tool works: typed in the wrong layout, then fixed.
// Frames are relative to END_CARD_AT.
export const WORDMARK_STAGGER = 2;
export const WORDMARK_LINE: Line = {
  start: 0,
  keys: [...WORDMARK_WRONG].map((ch, index) => ({ at: 4 + index * 2, ch })),
  flips: [{ at: 30, to: WORDMARK }],
};

import {
  DELETE_VARIANTS,
  KEY_VARIANTS,
  seeded,
  SFX_SECONDS,
  sfxFile,
  SPACE_VARIANTS,
  type SfxKind,
} from "./sfx";
import {
  CHIP_FLIP_FRAMES,
  CHIP_FLIPS,
  END_CARD_AT,
  FACT_STARTS,
  FLIP_FRAMES,
  FLIP_STAGGER,
  LINES,
  OPTION_KEY,
  SHAKE_AT,
  WORDMARK_LINE,
  WORDMARK_STAGGER,
  type Line,
} from "./timeline";

export type Cue = {
  at: number;
  kind: SfxKind;
  file: string;
  seconds: number;
  volume: number;
  label: string;
};

const random = seeded(20261115);

const cue = (
  at: number,
  kind: SfxKind,
  label: string,
  variant?: number,
  volume = 1,
): Cue => ({
  at,
  kind,
  file: sfxFile(kind, variant),
  seconds: SFX_SECONDS[kind],
  volume,
  label,
});

// A different take than the previous key, at a slightly different level.
const takes = (count: number) => {
  let previous = -1;
  return () => {
    let take = Math.floor(random() * count);
    if (take === previous) take = (take + 1) % count;
    previous = take;
    return take;
  };
};
const keyTake = takes(KEY_VARIANTS);
const deleteTake = takes(DELETE_VARIANTS);
const spaceTake = takes(SPACE_VARIANTS);
const touch = () => 0.72 + random() * 0.28;

// A letter changes glyph halfway through its flip; that is when it ticks.
const SWAP = FLIP_FRAMES / 2;

const lineCues = (
  line: Line,
  offset: number,
  stagger: number,
  level: number,
): Cue[] => {
  const typed = line.keys.map((key) =>
    key.ch === " "
      ? cue(offset + key.at, "space", "Space", spaceTake(), touch())
      : cue(
          offset + key.at,
          "key",
          `Key ${key.ch}`,
          keyTake(),
          touch() * level,
        ),
  );
  const deleted = (line.deletes ?? []).map((at) =>
    cue(offset + at, "delete", "Delete", deleteTake(), touch()),
  );
  // Each letter position has its own pitch, so a left-to-right flip rises
  // and the right-to-left undo falls.
  const flipped = (line.flips ?? []).flatMap((flip) => {
    const letters = [...flip.to];
    return letters.map((letter, index) => {
      const order = flip.reverse ? letters.length - 1 - index : index;
      return cue(
        offset + flip.at + order * stagger + SWAP,
        "tick",
        `Flip ${letter}`,
        index,
      );
    });
  });
  return [...typed, ...deleted, ...flipped];
};

const wordmarkCues = lineCues(
  WORDMARK_LINE,
  END_CARD_AT,
  WORDMARK_STAGGER,
  0.8,
);

export const CUES: Cue[] = [
  ...LINES.flatMap((line) => lineCues(line, 0, FLIP_STAGGER, 1)),
  cue(SHAKE_AT, "thud", "Shake"),
  ...OPTION_KEY.presses.map((at) => cue(at, "modifier", "Right Option")),
  // The indicator lands when its flip completes.
  ...CHIP_FLIPS.map((flip) =>
    cue(
      flip.at + CHIP_FLIP_FRAMES,
      flip.undo ? "undo" : "land",
      `Layout ${flip.to}`,
    ),
  ),
  ...FACT_STARTS.map((at, index) => cue(at, "fact", `Fact ${index + 1}`)),
  ...wordmarkCues,
  // The end card resolves as the last letter of the name turns over.
  cue(
    Math.max(...wordmarkCues.filter((c) => c.kind === "tick").map((c) => c.at)),
    "resolve",
    "End card",
  ),
].sort((a, b) => a.at - b.at);

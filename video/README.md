# MovaSwitch explainer video

A 28-second, 1920×1080 explainer with sound effects, built with [Remotion](https://www.remotion.dev). The finished file is `out/mova-switch.mp4`.

```sh
bun install
bun run verify-layout   # key tables match engine/src/layout.rs
bun run sfx             # rewrites public/sfx/*.wav
bun run render          # writes out/mova-switch.mp4
```

`npm install` fails here when npm is configured to refuse install scripts, so use bun.

## Where things live

- `src/timeline.ts`: every keystroke, flip, key press and layout change, in frames at 30 fps.
- `src/MovaSwitch.tsx`: scene, caption, fact and end-card timing.
- `src/layout.ts`: the U.S. and Ukrainian-PC key tables. Wrong-layout words are derived from them, never typed by hand.
- `src/components/`: the field, flipping letters, layout chip, keycaps, facts and end card.
- `src/cues.ts`: one sound cue per timeline event, so sound and picture share the same frame numbers.
- `scripts/make-sfx.ts`: synthesises every sound from sine tones and filtered noise. Nothing is sampled or downloaded, and a fixed seed makes each run produce the same files.

All motion is computed from the current frame. There are no CSS transitions or timers.

Remotion needs a company license for some organisations. [Read the terms](https://github.com/remotion-dev/remotion/blob/main/LICENSE.md).

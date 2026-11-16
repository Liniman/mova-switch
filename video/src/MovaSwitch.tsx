import React from "react";
import { AbsoluteFill, Sequence } from "remotion";
import { Caption } from "./components/Caption";
import { Demo } from "./components/Demo";
import { EndCard } from "./components/EndCard";
import { Fact } from "./components/Fact";
import { OptionGlyph } from "./components/Glyphs";
import { Sound } from "./components/Sound";
import { color } from "./theme";
import {
  DEMO_END,
  END_CARD_AT,
  END_CARD_FRAMES,
  FACT_FRAMES,
  FACT_STARTS,
} from "./timeline";

// The typing demo is computed per frame from src/timeline.ts, so its keystrokes
// are edited there. Captions are timed here. Every sound is placed by
// src/cues.ts from the same timeline data as the picture.
export const MovaSwitch: React.FC = () => {
  return (
    <AbsoluteFill style={{ backgroundColor: color.paper }}>
      <Sequence name="Typing demo" durationInFrames={DEMO_END}>
        <Demo />
      </Sequence>

      <Sequence name="Caption: the pain" from={54} durationInFrames={62}>
        <Caption>Wrong layout. Again.</Caption>
      </Sequence>
      <Sequence name="Caption: the fix" from={186} durationInFrames={96}>
        <Caption>Hit space. Fixed.</Caption>
      </Sequence>
      <Sequence name="Caption: both ways" from={344} durationInFrames={68}>
        <Caption>Both ways.</Caption>
      </Sequence>
      <Sequence name="Caption: undo" from={496} durationInFrames={78}>
        <Caption>
          Tap right
          <OptionGlyph size={62} stroke={2.4} />
          to undo.
        </Caption>
      </Sequence>

      <Sequence
        name="Fact: local"
        from={FACT_STARTS[0]}
        durationInFrames={FACT_FRAMES}
      >
        <Fact icon="mac">Runs entirely on your Mac</Fact>
      </Sequence>
      <Sequence
        name="Fact: passwords"
        from={FACT_STARTS[1]}
        durationInFrames={FACT_FRAMES}
      >
        <Fact icon="password">Never in password fields</Fact>
      </Sequence>
      <Sequence
        name="Fact: open source"
        from={FACT_STARTS[2]}
        durationInFrames={FACT_FRAMES}
      >
        <Fact icon="source">Open source</Fact>
      </Sequence>

      <Sequence
        name="End card"
        from={END_CARD_AT}
        durationInFrames={END_CARD_FRAMES}
      >
        <EndCard />
      </Sequence>

      <Sound />
    </AbsoluteFill>
  );
};

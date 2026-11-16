import React from "react";
import { interpolate, useCurrentFrame } from "remotion";
import { clamp, color, easeOut, mono, sans } from "../theme";
import { WORDMARK_LINE, WORDMARK_STAGGER } from "../timeline";
import { BothWaysGlyph } from "./Glyphs";
import { TypedLine } from "./TypedLine";

const TAGLINE_IN = 48;
const LINK_IN = 56;

export const EndCard: React.FC = () => {
  const frame = useCurrentFrame();

  return (
    <div
      style={{
        position: "absolute",
        inset: 0,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      <TypedLine
        line={WORDMARK_LINE}
        fontSize={172}
        fontWeight={800}
        stagger={WORDMARK_STAGGER}
      />
      <div
        style={{
          marginTop: 40,
          display: "flex",
          alignItems: "center",
          gap: 20,
          fontFamily: sans,
          fontWeight: 600,
          fontSize: 60,
          letterSpacing: -1,
          color: color.ink,
          opacity: interpolate(
            frame,
            [TAGLINE_IN, TAGLINE_IN + 10],
            [0, 1],
            clamp,
          ),
          translate: interpolate(
            frame,
            [TAGLINE_IN, TAGLINE_IN + 14],
            ["0px 18px", "0px 0px"],
            { ...clamp, easing: easeOut },
          ),
        }}
      >
        Ukrainian
        <span style={{ display: "flex", color: color.blue }}>
          <BothWaysGlyph size={58} stroke={2.2} />
        </span>
        English, as you type
      </div>
      <div
        style={{
          marginTop: 76,
          padding: "22px 44px",
          borderRadius: 999,
          backgroundColor: color.surface,
          border: `2px solid ${color.hairline}`,
          fontFamily: mono,
          fontWeight: 500,
          fontSize: 42,
          color: color.ink,
          opacity: interpolate(frame, [LINK_IN, LINK_IN + 10], [0, 1], clamp),
          translate: interpolate(
            frame,
            [LINK_IN, LINK_IN + 14],
            ["0px 18px", "0px 0px"],
            { ...clamp, easing: easeOut },
          ),
        }}
      >
        github.com/Liniman/mova-switch
      </div>
    </div>
  );
};

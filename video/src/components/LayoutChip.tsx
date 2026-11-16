import React from "react";
import { interpolate, useCurrentFrame } from "remotion";
import type { LayoutCode } from "../layout";
import { color, easeInOut, mono } from "../theme";
import { CHIP_FLIP_FRAMES, CHIP_FLIPS } from "../timeline";

const face: Record<LayoutCode, { background: string; text: string }> = {
  US: { background: color.ink, text: color.paper },
  UA: { background: color.blue, text: "#FFFFFF" },
};

export const LayoutChip: React.FC = () => {
  const frame = useCurrentFrame();

  let shown: LayoutCode = "US";
  let tilt = 0;
  for (const flip of CHIP_FLIPS) {
    const local = frame - flip.at;
    if (local < 0) break;
    if (local >= CHIP_FLIP_FRAMES) {
      shown = flip.to;
      tilt = 0;
      continue;
    }
    const angle = interpolate(local, [0, CHIP_FLIP_FRAMES], [0, 180], {
      easing: easeInOut,
    });
    if (angle >= 90) shown = flip.to;
    tilt = angle >= 90 ? angle - 180 : angle;
  }

  return (
    <div
      style={{
        width: 136,
        height: 96,
        borderRadius: 24,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        fontFamily: mono,
        fontWeight: 700,
        fontSize: 46,
        letterSpacing: 1,
        backgroundColor: face[shown].background,
        color: face[shown].text,
        transform: `perspective(700px) rotateX(${tilt}deg)`,
      }}
    >
      {shown}
    </div>
  );
};

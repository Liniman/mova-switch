import React from "react";
import { interpolate, useCurrentFrame, useVideoConfig } from "remotion";
import { clamp, color, easeOut, sans } from "../theme";

export const Caption: React.FC<{ children: React.ReactNode }> = ({
  children,
}) => {
  const frame = useCurrentFrame();
  const { durationInFrames } = useVideoConfig();

  return (
    <div
      style={{
        position: "absolute",
        left: 0,
        right: 0,
        top: 792,
        display: "flex",
        justifyContent: "center",
        alignItems: "center",
        gap: 18,
        fontFamily: sans,
        fontWeight: 700,
        fontSize: 66,
        letterSpacing: -1,
        color: color.ink,
        opacity:
          interpolate(frame, [0, 8], [0, 1], clamp) *
          interpolate(
            frame,
            [durationInFrames - 8, durationInFrames],
            [1, 0],
            clamp,
          ),
        translate: interpolate(frame, [0, 12], ["0px 18px", "0px 0px"], {
          ...clamp,
          easing: easeOut,
        }),
      }}
    >
      {children}
    </div>
  );
};

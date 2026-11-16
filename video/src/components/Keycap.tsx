import React from "react";
import { interpolate, useCurrentFrame } from "remotion";
import { clamp, color, popOut } from "../theme";

const DEPTH = 9;

export const Keycap: React.FC<{
  width: number;
  left: number;
  top: number;
  enterAt: number;
  exitAt?: number;
  presses: number[];
  children?: React.ReactNode;
}> = ({ width, left, top, enterAt, exitAt, presses, children }) => {
  const frame = useCurrentFrame();
  const pressed = Math.max(
    0,
    ...presses.map((at) =>
      interpolate(frame, [at - 2, at, at + 4], [0, 1, 0], clamp),
    ),
  );
  const gone =
    exitAt === undefined
      ? 0
      : interpolate(frame, [exitAt, exitAt + 8], [0, 1], clamp);

  return (
    <div
      style={{
        position: "absolute",
        left,
        top,
        width,
        height: 92,
        opacity:
          interpolate(frame, [enterAt, enterAt + 6], [0, 1], clamp) *
          (1 - gone),
        scale: interpolate(frame, [enterAt, enterAt + 12], [0.8, 1], {
          ...clamp,
          easing: popOut,
          output: "perceptual-scale",
        }),
      }}
    >
      <div
        style={{
          width: "100%",
          height: "100%",
          borderRadius: 22,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          color: color.ink,
          backgroundColor: pressed > 0.5 ? "#FBF9F4" : color.surface,
          border: `2px solid ${color.edge}`,
          boxShadow: `0 ${DEPTH - pressed * (DEPTH - 2)}px 0 ${color.edge}`,
          translate: `0px ${pressed * (DEPTH - 2)}px`,
        }}
      >
        {children}
      </div>
    </div>
  );
};

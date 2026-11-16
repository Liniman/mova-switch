import React from "react";
import { interpolate, useCurrentFrame, useVideoConfig } from "remotion";
import { clamp, color, easeInOut, easeOut, popOut, sans } from "../theme";

type Icon = "mac" | "password" | "source";

const stroke = {
  fill: "none",
  stroke: color.ink,
  strokeWidth: 6,
  strokeLinecap: "round",
  strokeLinejoin: "round",
  pathLength: 1,
  strokeDasharray: 1,
} as const;

const FactIcon: React.FC<{ icon: Icon }> = ({ icon }) => {
  const frame = useCurrentFrame();
  const draw = interpolate(frame, [1, 18], [1, 0], {
    ...clamp,
    easing: easeInOut,
  });

  if (icon === "mac") {
    return (
      <svg width={264} height={198} viewBox="0 0 160 120">
        <rect
          x={30}
          y={14}
          width={100}
          height={68}
          rx={10}
          {...stroke}
          strokeDashoffset={draw}
        />
        <path d="M12 98H148" {...stroke} strokeDashoffset={draw} />
        <rect
          x={48}
          y={36}
          width={6}
          height={24}
          rx={3}
          fill={color.blue}
          opacity={frame >= 14 && (frame - 14) % 20 < 12 ? 1 : 0}
        />
      </svg>
    );
  }

  if (icon === "password") {
    return (
      <svg width={396} height={198} viewBox="0 0 240 120">
        <rect
          x={8}
          y={28}
          width={224}
          height={64}
          rx={32}
          {...stroke}
          strokeDashoffset={draw}
        />
        {[52, 86, 120, 154, 188].map((cx, index) => (
          <circle
            key={cx}
            cx={cx}
            cy={60}
            fill={color.ink}
            r={interpolate(frame, [9 + index * 3, 15 + index * 3], [0, 8.5], {
              ...clamp,
              easing: popOut,
            })}
          />
        ))}
      </svg>
    );
  }

  return (
    <svg width={264} height={198} viewBox="0 0 160 120">
      <path d="M56 30L22 60L56 90" {...stroke} strokeDashoffset={draw} />
      <path d="M104 30L138 60L104 90" {...stroke} strokeDashoffset={draw} />
      <path
        d="M90 22L70 98"
        {...stroke}
        stroke={color.blue}
        strokeDashoffset={draw}
      />
    </svg>
  );
};

export const Fact: React.FC<{ icon: Icon; children: React.ReactNode }> = ({
  icon,
  children,
}) => {
  const frame = useCurrentFrame();
  const { durationInFrames } = useVideoConfig();

  return (
    <div
      style={{
        position: "absolute",
        inset: 0,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        gap: 44,
        opacity:
          interpolate(frame, [0, 7], [0, 1], clamp) *
          interpolate(
            frame,
            [durationInFrames - 6, durationInFrames],
            [1, 0],
            clamp,
          ),
        translate: interpolate(
          frame,
          [0, 12, durationInFrames - 6, durationInFrames],
          ["0px 22px", "0px 0px", "0px 0px", "0px -18px"],
          { ...clamp, easing: [easeOut, easeOut, easeInOut] },
        ),
      }}
    >
      <FactIcon icon={icon} />
      <div
        style={{
          fontFamily: sans,
          fontWeight: 700,
          fontSize: 84,
          letterSpacing: -1.5,
          color: color.ink,
        }}
      >
        {children}
      </div>
    </div>
  );
};

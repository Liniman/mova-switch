import React from "react";
import { interpolate, interpolateColors, useCurrentFrame } from "remotion";
import { clamp, color, easeInOut, easeOut, mono } from "../theme";
import {
  CLEAR_FRAMES,
  FLIP_FRAMES,
  FLIP_STAGGER,
  type Line,
} from "../timeline";

// JetBrains Mono advances 600 of 1000 units, so Latin and Cyrillic share one cell.
const CELL_EM = 0.6;

type Cell = {
  glyph: string;
  next?: string;
  progress: number;
  settledFor: number;
  reverse: boolean;
  age: number;
};

const resolve = (line: Line, frame: number, stagger: number) => {
  const typed = line.keys.filter((key) => key.at <= frame);
  const deletes = (line.deletes ?? []).filter((at) => at <= frame);
  const visible = typed.slice(0, Math.max(0, typed.length - deletes.length));
  let lastActivity = Math.max(
    line.start,
    ...typed.map((key) => key.at),
    ...deletes,
  );

  const cells = visible.map((key, index): Cell => {
    const cell: Cell = {
      glyph: key.ch,
      progress: 0,
      settledFor: Number.POSITIVE_INFINITY,
      reverse: false,
      age: frame - key.at,
    };
    for (const flip of line.flips ?? []) {
      const target = [...flip.to];
      if (index >= target.length) continue;
      const order = flip.reverse ? target.length - 1 - index : index;
      const local = frame - (flip.at + order * stagger);
      if (local < 0) break;
      cell.reverse = Boolean(flip.reverse);
      if (local >= FLIP_FRAMES) {
        cell.glyph = target[index];
        cell.next = undefined;
        cell.settledFor = local - FLIP_FRAMES;
      } else {
        cell.next = target[index];
        cell.progress = local / FLIP_FRAMES;
        cell.settledFor = Number.POSITIVE_INFINITY;
      }
    }
    return cell;
  });

  for (const flip of line.flips ?? []) {
    if (flip.at > frame) continue;
    const end = flip.at + ([...flip.to].length - 1) * stagger + FLIP_FRAMES;
    lastActivity = Math.max(lastActivity, Math.min(frame, end));
  }

  return { cells, idleFor: frame - lastActivity };
};

const squigglePath = (width: number) => {
  const half = 13;
  let d = "M0 8";
  for (let x = 0, up = true; x < width; x += half, up = !up) {
    d += ` q ${half / 2} ${up ? -9 : 9} ${half} 0`;
  }
  return d;
};

export const TypedLine: React.FC<{
  line: Line;
  fontSize: number;
  fontWeight?: number;
  stagger?: number;
}> = ({ line, fontSize, fontWeight = 500, stagger = FLIP_STAGGER }) => {
  const frame = useCurrentFrame();
  if (frame < line.start) return null;
  if (line.clearAt !== undefined && frame >= line.clearAt + CLEAR_FRAMES) {
    return null;
  }

  const { cells, idleFor } = resolve(line, frame, stagger);
  const caretOn = idleFor < 14 || (idleFor - 14) % 28 >= 14;
  const cleared =
    line.clearAt === undefined
      ? 0
      : interpolate(
          frame,
          [line.clearAt, line.clearAt + CLEAR_FRAMES],
          [0, 1],
          { ...clamp, easing: easeInOut },
        );
  const wordWidth = cells.length * CELL_EM * fontSize;
  const flipLength = Math.max(
    0,
    ...(line.flips ?? []).map((flip) => [...flip.to].length),
  );
  const corner = fontSize * 0.1;

  return (
    <div
      style={{
        position: "relative",
        display: "flex",
        alignItems: "center",
        fontFamily: mono,
        fontSize,
        fontWeight,
        lineHeight: 1.2,
        whiteSpace: "pre",
        color: color.ink,
        opacity: 1 - cleared,
        translate: `0px ${-44 * cleared}px`,
      }}
    >
      {cells.map((cell, index) => {
        const angle = interpolate(cell.progress, [0, 1], [0, 180], {
          easing: easeInOut,
        });
        const flipping = cell.next !== undefined;
        const showNext = flipping && angle >= 90;
        const tilt = (showNext ? angle - 180 : angle) * (cell.reverse ? -1 : 1);
        const settled = Number.isFinite(cell.settledFor);
        const heat = flipping
          ? interpolate(cell.progress, [0, 0.45], [0, 1], clamp)
          : settled
            ? interpolate(cell.settledFor, [4, 22], [1, 0], clamp)
            : 0;
        const glyph = showNext ? cell.next : cell.glyph;
        return (
          <span
            key={index}
            style={{
              position: "relative",
              display: "inline-block",
              width: `${CELL_EM}em`,
              textAlign: "center",
            }}
          >
            <span
              style={{
                position: "absolute",
                top: "0.06em",
                bottom: "0.06em",
                left: 0,
                right: index === flipLength - 1 ? 0 : -1,
                borderRadius: `${index === 0 ? corner : 0}px ${index === flipLength - 1 ? corner : 0}px ${index === flipLength - 1 ? corner : 0}px ${index === 0 ? corner : 0}px`,
                backgroundColor: color.yellow,
                opacity: heat,
              }}
            />
            <span
              style={{
                position: "relative",
                display: "inline-block",
                color: showNext
                  ? color.blue
                  : settled
                    ? interpolateColors(
                        cell.settledFor,
                        [6, 26],
                        [color.blue, color.ink],
                      )
                    : color.ink,
                transform: `perspective(${fontSize * 5}px) rotateX(${tilt}deg)`,
                opacity: interpolate(cell.age, [0, 2], [0.3, 1], clamp),
                scale: interpolate(cell.age, [0, 4], [0.8, 1], {
                  ...clamp,
                  easing: easeOut,
                }),
              }}
            >
              {glyph === " " ? " " : glyph}
            </span>
          </span>
        );
      })}
      <span
        style={{
          display: "inline-block",
          width: Math.max(4, fontSize * 0.055),
          height: "1.02em",
          marginLeft: fontSize * 0.05,
          borderRadius: 4,
          backgroundColor: color.blue,
          opacity: caretOn ? 1 : 0,
        }}
      />
      {line.squiggleAt !== undefined && frame >= line.squiggleAt ? (
        <svg
          width={wordWidth}
          height={16}
          viewBox={`0 0 ${Math.max(wordWidth, 1)} 16`}
          style={{
            position: "absolute",
            left: 0,
            top: "100%",
            marginTop: -4,
            overflow: "hidden",
          }}
        >
          <path
            d={squigglePath(wordWidth)}
            pathLength={1}
            fill="none"
            stroke={color.red}
            strokeWidth={5}
            strokeLinecap="round"
            strokeDasharray={1}
            strokeDashoffset={interpolate(
              frame,
              [line.squiggleAt, line.squiggleAt + 10],
              [1, 0],
              { ...clamp, easing: easeOut },
            )}
          />
        </svg>
      ) : null}
    </div>
  );
};

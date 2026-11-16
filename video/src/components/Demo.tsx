import React from "react";
import { interpolate, useCurrentFrame } from "remotion";
import { clamp, color, easeInOut, easeOut, popOut, sans } from "../theme";
import {
  DELETE_KEY,
  DEMO_END,
  DEMO_OUT,
  LINES,
  OPTION_KEY,
  SHAKE_AT,
  SPACE_KEY,
  STATUS_IN,
  STATUS_PULSES,
} from "../timeline";
import { DeleteGlyph, OptionGlyph } from "./Glyphs";
import { Keycap } from "./Keycap";
import { LayoutChip } from "./LayoutChip";
import { TypedLine } from "./TypedLine";

const FIELD = { left: 240, top: 300, width: 1440, height: 220 };
const KEY_TOP = 590;
const SPACE_WIDTH = 460;
const OPTION_WIDTH = 132;
const KEY_GAP = 24;

const StatusPill: React.FC = () => {
  const frame = useCurrentFrame();
  return (
    <div
      style={{
        position: "absolute",
        left: FIELD.left + 20,
        top: FIELD.top - 84,
        display: "flex",
        alignItems: "center",
        gap: 18,
        fontFamily: sans,
        fontWeight: 700,
        fontSize: 40,
        letterSpacing: -0.5,
        color: color.ink,
        opacity: interpolate(frame, [STATUS_IN, STATUS_IN + 8], [0, 1], clamp),
        translate: interpolate(
          frame,
          [STATUS_IN, STATUS_IN + 14],
          ["0px 14px", "0px 0px"],
          { ...clamp, easing: easeOut },
        ),
      }}
    >
      <span style={{ position: "relative", width: 20, height: 20 }}>
        {STATUS_PULSES.map((at) => (
          <span
            key={at}
            style={{
              position: "absolute",
              inset: 0,
              borderRadius: "50%",
              backgroundColor: color.blue,
              opacity: interpolate(frame, [at, at + 22], [0.45, 0], clamp),
              scale: interpolate(frame, [at, at + 22], [1, 3], {
                ...clamp,
                easing: easeOut,
              }),
            }}
          />
        ))}
        <span
          style={{
            position: "absolute",
            inset: 0,
            borderRadius: "50%",
            backgroundColor: color.blue,
            scale: interpolate(frame, [STATUS_IN, STATUS_IN + 14], [0, 1], {
              ...clamp,
              easing: popOut,
            }),
          }}
        />
      </span>
      MovaSwitch
    </div>
  );
};

export const Demo: React.FC = () => {
  const frame = useCurrentFrame();
  const shake = frame - SHAKE_AT;
  const shakeX =
    shake >= 0 && shake < 20
      ? Math.sin(shake * 1.35) * 16 * (1 - shake / 20)
      : 0;
  const pairLeft = 960 - (SPACE_WIDTH + KEY_GAP + OPTION_WIDTH) / 2;
  const spaceLeft = interpolate(
    frame,
    [OPTION_KEY.in - 4, OPTION_KEY.in + 10],
    [960 - SPACE_WIDTH / 2, pairLeft],
    { ...clamp, easing: easeInOut },
  );

  return (
    <div
      style={{
        position: "absolute",
        inset: 0,
        opacity: interpolate(frame, [DEMO_OUT, DEMO_END], [1, 0], clamp),
        scale: interpolate(frame, [DEMO_OUT, DEMO_END], [1, 0.97], {
          ...clamp,
          easing: easeInOut,
        }),
      }}
    >
      <StatusPill />
      <div
        style={{
          position: "absolute",
          ...FIELD,
          boxSizing: "border-box",
          borderRadius: 48,
          backgroundColor: color.surface,
          border: `2px solid ${color.hairline}`,
          boxShadow: "0 36px 70px -40px rgba(60, 48, 20, 0.28)",
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          paddingLeft: 68,
          paddingRight: 46,
          opacity: interpolate(frame, [0, 10], [0, 1], clamp),
          translate: `${shakeX}px ${interpolate(frame, [0, 18], [28, 0], {
            ...clamp,
            easing: easeOut,
          })}px`,
        }}
      >
        <div style={{ position: "relative", flex: 1, height: 130 }}>
          {LINES.filter(
            (line, index) =>
              frame >= line.start &&
              (index === LINES.length - 1 || frame < LINES[index + 1].start),
          ).map((line) => (
            <div
              key={line.start}
              style={{
                position: "absolute",
                inset: 0,
                display: "flex",
                alignItems: "center",
              }}
            >
              <TypedLine line={line} fontSize={104} />
            </div>
          ))}
        </div>
        <LayoutChip />
      </div>

      <Keycap
        width={150}
        left={960 - 75}
        top={KEY_TOP}
        enterAt={DELETE_KEY.in}
        exitAt={DELETE_KEY.out}
        presses={DELETE_KEY.presses}
      >
        <DeleteGlyph size={46} />
      </Keycap>
      <Keycap
        width={SPACE_WIDTH}
        left={spaceLeft}
        top={KEY_TOP}
        enterAt={SPACE_KEY.in}
        presses={SPACE_KEY.presses}
      />
      <Keycap
        width={OPTION_WIDTH}
        left={pairLeft + SPACE_WIDTH + KEY_GAP}
        top={KEY_TOP}
        enterAt={OPTION_KEY.in}
        presses={OPTION_KEY.presses}
      >
        <OptionGlyph size={46} />
      </Keycap>
    </div>
  );
};

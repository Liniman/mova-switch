import React from "react";

type GlyphProps = { size: number; stroke?: number };

const base = (size: number, stroke: number) =>
  ({
    width: size,
    height: size,
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "currentColor",
    strokeWidth: stroke,
    strokeLinecap: "round",
    strokeLinejoin: "round",
  }) as const;

export const OptionGlyph: React.FC<GlyphProps> = ({ size, stroke = 2 }) => (
  <svg {...base(size, stroke)}>
    <path d="M3 6h5.5l7 12H21" />
    <path d="M14 6h7" />
  </svg>
);

export const DeleteGlyph: React.FC<GlyphProps> = ({ size, stroke = 2 }) => (
  <svg {...base(size, stroke)}>
    <path d="M9 5h11a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H9l-6.2-7z" />
    <path d="M12.2 9.4l5.2 5.2M17.4 9.4l-5.2 5.2" />
  </svg>
);

export const BothWaysGlyph: React.FC<GlyphProps> = ({ size, stroke = 2 }) => (
  <svg {...base(size, stroke)}>
    <path d="M3 12h18" />
    <path d="M7.5 7.5L3 12l4.5 4.5" />
    <path d="M16.5 7.5L21 12l-4.5 4.5" />
  </svg>
);

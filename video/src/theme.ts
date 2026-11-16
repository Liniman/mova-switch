import { loadFont as loadMono } from "@remotion/google-fonts/JetBrainsMono";
import { loadFont as loadSans } from "@remotion/google-fonts/Manrope";
import { Easing } from "remotion";

export const mono = loadMono("normal", {
  weights: ["500", "700", "800"],
  subsets: ["latin", "cyrillic", "cyrillic-ext"],
}).fontFamily;

export const sans = loadSans("normal", {
  weights: ["600", "700"],
  subsets: ["latin", "cyrillic"],
}).fontFamily;

export const color = {
  paper: "#F2EFE7",
  surface: "#FFFFFF",
  ink: "#1C1B18",
  muted: "#8B8678",
  edge: "#D6D0C0",
  hairline: "#E4DFD2",
  blue: "#2457C5",
  yellow: "#FFD84D",
  red: "#D8472B",
};

export const easeOut = Easing.bezier(0.16, 1, 0.3, 1);
export const easeInOut = Easing.bezier(0.45, 0, 0.2, 1);
export const popOut = Easing.bezier(0.34, 1.56, 0.64, 1);

export const clamp = {
  extrapolateLeft: "clamp",
  extrapolateRight: "clamp",
} as const;

import { Audio } from "@remotion/media";
import React from "react";
import { Sequence, staticFile, useVideoConfig } from "remotion";
import { CUES } from "../cues";

export const Sound: React.FC = () => {
  const { fps } = useVideoConfig();

  return (
    <>
      {CUES.map((cue, index) => (
        <Sequence
          key={index}
          name={`Sound: ${cue.label}`}
          from={cue.at}
          durationInFrames={Math.ceil(cue.seconds * fps)}
          layout="none"
        >
          <Audio src={staticFile(cue.file)} volume={cue.volume} />
        </Sequence>
      ))}
    </>
  );
};

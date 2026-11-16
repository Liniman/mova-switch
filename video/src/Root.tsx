import { Composition } from "remotion";
import { MovaSwitch } from "./MovaSwitch";

export const RemotionRoot: React.FC = () => {
  return (
    <Composition
      id="MovaSwitch"
      component={MovaSwitch}
      durationInFrames={840}
      fps={30}
      width={1920}
      height={1080}
    />
  );
};

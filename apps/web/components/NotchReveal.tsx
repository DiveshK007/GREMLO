import { Reveal } from "./Reveal";
import { Sprite } from "./PetArt";

/** A MacBook top edge: on scroll the hidden door glows, swings open and the pet drops out. */
export function NotchReveal() {
  return (
    <Reveal className="notch-stage">
      <div className="screen-top">
        <div className="notch">
          <div className="door" />
        </div>
      </div>
      <div className="drop"><Sprite row={3} frames={4} scale={0.9} /></div>
      <p className="mono notch-caption">Claude Code starts working · the door opens · the pet drops out</p>
    </Reveal>
  );
}

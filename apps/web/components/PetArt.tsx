// The Ink avatar from the v2 sprite pack (assets/pets/notchi-ink). Cells are 192x208, 8 per row.
const CELL_W = 192, CELL_H = 208, SHEET_W = 1536, SHEET_H = 2288;

/** One sprite row; animates through `frames` cells at 8 fps when frames > 1. Decorative. */
export function Sprite({ row, frames = 1, scale = 1, className = "" }: { row: number; frames?: number; scale?: number; className?: string }) {
  const w = CELL_W * scale, h = CELL_H * scale;
  const style = {
    width: w,
    height: h,
    backgroundSize: `${SHEET_W * scale}px ${SHEET_H * scale}px`,
    backgroundPositionY: -row * h,
    "--sx": `${-frames * w}px`,
    "--frames": frames,
  } as React.CSSProperties;
  return <span aria-hidden className={`sprite ${frames > 1 ? "animated" : ""} ${className}`} style={style} />;
}

/** Small idle pet for status panels and the "moved in" screen. */
export function PetSmall() {
  return <Sprite row={5} scale={0.4} className="pet-small" />;
}

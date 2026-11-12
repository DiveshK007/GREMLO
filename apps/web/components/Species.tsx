// A v6 species sheet from public/pets: 8 columns of 192x208 cells, 39 rows (docs/design/1.0).
export const ROWS = { idle: 5, greet: 3, celebrate: 4, backflip: 35 } as const;

export function SpeciesSprite({ species, row, scale = 0.5, frames = 1 }: { species: string; row: number; scale?: number; frames?: number }) {
  const w = 192 * scale, h = 208 * scale;
  const style = {
    width: w,
    height: h,
    backgroundImage: `url(/pets/${species}.webp)`,
    backgroundSize: `${1536 * scale}px ${8112 * scale}px`,
    backgroundPositionY: -row * h,
    "--sx": `${-frames * w}px`,
    "--frames": frames,
  } as React.CSSProperties;
  return <span aria-hidden className={`sprite ${frames > 1 ? "animated" : ""}`} style={style} />;
}

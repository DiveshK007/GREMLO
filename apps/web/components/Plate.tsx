import { Pet } from "./Pet";
import { kitUrl, speciesOf } from "@/lib/species";

/** The pet holding a sponsored line on its sign kit, with the AD tab (R2 §2). The line is shown whole, never
 *  truncated, and screen readers hear "Sponsored, <brand>: <line>". */
export function Plate({ species, line, brand, scale = 0.5714, k = 4, className }: { species?: string | null; line: string; brand?: string; scale?: number; k?: number; className?: string }) {
  const s = speciesOf(species);
  const sign = { "--k": `${k}px`, borderImageSource: `url(${kitUrl(s)})`, top: Math.round(s.plate * scale) } as React.CSSProperties;
  return (
    <span className={`held${className ? ` ${className}` : ""}`}>
      <Pet species={s.id} row="hold" fps={4.5} scale={scale} />
      <span className="sign" style={sign} role="img" aria-label={`Sponsored, ${brand || "brand"}: ${line}`}>
        <span aria-hidden="true">{line}</span>
        <span className="ad" aria-hidden="true">AD</span>
      </span>
    </span>
  );
}

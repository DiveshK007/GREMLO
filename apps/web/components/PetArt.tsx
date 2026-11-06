// Original pixel pet for the web pages (the Mac spritesheet is placeholder art, not for public pages).
const PET = [
  "..X........X..",
  ".XBX......XBX.",
  ".XBBXXXXXXBBX.",
  "XBBBBBBBBBBBBX",
  "XBBEBBBBBBEBBX",
  "XBBEBBBBBBEBBX",
  "XBCBBBMMBBBCBX",
  "XBBBBBBBBBBBBX",
  ".XBBBBBBBBBBX.",
  "..XXBXXXXBXX..",
  "...XX....XX...",
];
const FILL: Record<string, string> = { X: "var(--pet-edge)", B: "var(--pet)", E: "var(--pet-edge)", C: "var(--cheek)", M: "var(--pet-edge)" };

function Pixels({ x, y, s }: { x: number; y: number; s: number }) {
  return (
    <g>
      {PET.flatMap((row, r) =>
        [...row].map((ch, c) =>
          FILL[ch] ? <rect key={`${r}-${c}`} x={x + c * s} y={y + r * s} width={s} height={s} fill={FILL[ch]} /> : null,
        ),
      )}
    </g>
  );
}

/** The pet hanging under the notch, holding the sponsor sign. Decorative. */
export function NotchPet() {
  return (
    <svg className="notch-pet" viewBox="0 0 320 140" role="img" aria-label="Notchi hanging under the MacBook notch, holding a sign">
      <rect x="0" y="0" width="320" height="10" fill="var(--screen-edge)" />
      <rect x="110" y="0" width="100" height="26" rx="10" fill="#000" />
      <rect x="146" y="8" width="28" height="10" rx="3" fill="var(--door)" />
      <rect x="157" y="26" width="2" height="22" fill="var(--pet-edge)" />
      <rect x="161" y="26" width="2" height="22" fill="var(--pet-edge)" />
      <Pixels x={139} y={44} s={3} />
      <rect x="92" y="88" width="136" height="34" rx="3" fill="var(--sign)" stroke="var(--sign-edge)" strokeWidth="2" />
      <text x="160" y="110" textAnchor="middle" fontSize="13" fontFamily="var(--mono)" fill="#2a2416">
        your line here
      </text>
      <rect x="132" y="122" width="3" height="14" fill="var(--sign-edge)" />
      <rect x="185" y="122" width="3" height="14" fill="var(--sign-edge)" />
    </svg>
  );
}

/** Small standalone pet for the "moved in" screen. */
export function PetSmall() {
  return (
    <svg className="pet-small" viewBox="0 0 42 33" aria-hidden>
      <Pixels x={0} y={0} s={3} />
    </svg>
  );
}

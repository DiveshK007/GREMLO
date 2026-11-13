// The eight species as the web draws them: v6 sheets in public/site/sprites (8 columns of 192x208 cells, 39 rows),
// the sign kit, and the plate anchor from each pet.json. Shared by the home page's sheets and every app page.

export type SpeciesId = "gremlo" | "pip" | "moss" | "gloop" | "byte" | "puff" | "wisp" | "tako";
export type Species = { id: SpeciesId; name: string; kind: string; accent: string; safe: string; plate: number };

export const SPECIES: Species[] = [
  { id: "gremlo", name: "Gremlo", kind: "bean", accent: "#FF5A3C", safe: "#C1442D", plate: 26 },
  { id: "pip", name: "Pip", kind: "bird", accent: "#FFC93C", safe: "#876A1F", plate: 47 },
  { id: "moss", name: "Moss", kind: "sprout", accent: "#8FD14F", safe: "#52792D", plate: 47 },
  { id: "gloop", name: "Gloop", kind: "slime", accent: "#2ED3B7", safe: "#1B7C6B", plate: 104 },
  { id: "byte", name: "Byte", kind: "robot", accent: "#4CC9FF", safe: "#2C7696", plate: 54 },
  { id: "puff", name: "Puff", kind: "cloud", accent: "#8FA8FF", safe: "#5B6BA3", plate: 62 },
  { id: "wisp", name: "Wisp", kind: "flame", accent: "#B48CFF", safe: "#7C60AF", plate: 26 },
  { id: "tako", name: "Tako", kind: "octopus", accent: "#FF7AB6", safe: "#AA5179", plate: 61 },
];
export const SP = Object.fromEntries(SPECIES.map((s) => [s.id, s])) as Record<SpeciesId, Species>;

/** "gremlo-pip" (the Mac's and the park's id) or "pip" to the web's id; anything unknown is Gremlo. */
export function speciesOf(id: string | null | undefined): Species {
  const short = String(id ?? "").replace(/^gremlo-/, "");
  return SP[short as SpeciesId] ?? SP.gremlo;
}
export const knownSpecies = (id: string | null | undefined) => !!id && String(id).replace(/^gremlo-/, "") in SP;

/** Frames per row, and the row names (docs/design/1.0, packs v6). */
export const FRAMES = [6, 8, 8, 4, 5, 8, 6, 6, 6, 4, 6, 4, 6, 6, 4, 4, 6, 5, 4, 4, 4, 4, 4, 6, 6, 6, 4, 4, 6, 6, 8, 6, 6, 4, 4, 6, 4, 4, 4];
export const ROW = {
  eat: 0, walk: 1, climb: 2, greet: 3, celebrate: 4, idle: 5, sign: 6, flag: 7, fail: 8, hover: 9, annoy: 10, special: 11, evolve: 12,
  wardrobe: 13, peek: 14, turn: 15, startstop: 16, gaze: 17, sit: 18, edgepeek: 19, yawn: 20, grabbed: 21, thrown: 22, land: 23,
  social: 24, tools: 25, night: 26, focus: 27, hold: 28, wardrobe2: 29, hatch: 30, chase: 31, gulp: 32, covereyes: 33, tangled: 34,
  backflip: 35, juggle: 36, moonwalk: 37, wrist: 38,
} as const;
export type RowName = keyof typeof ROW;

export const sheetUrl = (s: Species) => `/site/sprites/${s.id}.webp`;
export const kitUrl = (s: Species) => `/site/sprites/${s.id}-kit.png`;

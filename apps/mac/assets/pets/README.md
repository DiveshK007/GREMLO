# Pet folders

One folder per pet: `assets/pets/<name>/`. Put local-only pets in `assets/demo-pets/<name>/` (gitignored, third-party packs). The default is `notchi-ink`; `NOTCHI_SKIN=<name>` picks another. If the chosen pet doesn't load, the first one that does is used.

## Sheet format (notchi-bone, notchi-ink, notchi-signal)

`pet.json` (Codex pet format, `spritesheetPath` defaults to `spritesheet.webp`) plus one sheet: 192x208 cells, 8 columns, one animation per row, frames left-aligned. The row map, baseline, pixel scale and per-mood fps come from `rows.json` in the folder if present, else `assets/pets/notchi-rows.json`.

## Strip format (mochi)

Each folder has:

- `<state>.png`: one horizontal strip per state, frames side by side, all the same size, transparent background. States: `greet`, `walk`, `climb`, `idle`, `sign`, `flag`, `celebrate`, `fail`, `eat`. Only `walk` is required; a missing state uses walk.
- `pet.json`:

```json
{
  "fps": 8,
  "pixel": 7,
  "baseline": 190,
  "frames": { "greet": 4, "walk": 8, "idle": 8, "sign": 6, "flag": 6, "celebrate": 5, "fail": 6, "climb": 8, "eat": 6 }
}
```

`frames` is the frame count of each strip. `pixel` is how many strip pixels make one art pixel (one art pixel is drawn at 2 points). `baseline` is the strip row the feet stand on. Walk frames face right; climb frames face left.

Optional door art: `door_closed.png`, `door_glowing.png`, `door_open.png`, `door_locked.png`, at the same `pixel` scale. All four or none.

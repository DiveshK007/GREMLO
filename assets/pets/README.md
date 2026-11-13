# Species packs

Eight original species, one folder each: `assets/pets/<id>/`. Format and rules: `docs/design/1.0/` (base spec §3, round 2 §1, round 3 §1, round 4 §1).

| File | What |
|---|---|
| `pet.json` | id, name, `spriteVersionNumber`, and `gremlo`: accent, cell, rows (name → row, frames), plate anchors, sign kit, head anchors, accessories, anchors, arcs |
| `spritesheet.webp` / `.png` | 39 rows of 192 × 208 cells, 8 columns, feet on y = 194 |
| `ext3.png` | rows 31–38 on their own, for lazy loading |
| `signkit.png` | the 20 × 11 nine-slice plate the pet holds; the app draws the line on it |
| `accessories.png` | 12 accessories, 40 × 40 sprite units each, anchor at (20, 12) |

The Mac app (`GremloCore`) loads packs from v3 (15 rows) to v6 (39 rows); missing rows fall back as the spec says, and a pack without the hold row, plate anchors and a sign kit can't be the earner.
Regenerate with `tools/sprites/roster4.py`. Third-party packs for local demos go in the gitignored `assets/demo-pets/`; only these eight species ship.

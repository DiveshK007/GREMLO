# Pet folders

One folder per pet: `assets/pets/<name>/`. Put local-only pets in `assets/demo-pets/<name>/` (gitignored); if that folder has a pet, the app uses it instead. `NOTCHI_SKIN=<name>` picks one by name.

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

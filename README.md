# Candy House · 甜蜜糖果屋

Godot 4.7.2 tile-matching game (English default; 简体中文 / 日本語 / 한국어 in Settings, following the device language until the player picks one).

## Run

A fresh clone has no imported assets yet (`.godot/` is not in git), so the art, fonts and sounds will not load until Godot imports them once:

- **Editor:** open `project.godot` in the Godot 4.7 editor, wait for the import to finish, then press Play.
- **Command line:** import once, then run.

```sh
godot --path . --headless --import
godot --path .
```

On macOS the binary is `/Applications/Godot.app/Contents/MacOS/Godot`.

## Tests

```sh
godot --headless --path . -s tests/run_tests.gd
godot --headless --path . -s tests/meta_tests.gd
```

## Docs

- `docs/full_game_plan.md` — page and feature plan
- `docs/google_play_integration.md` — Google Play billing and AdMob plan

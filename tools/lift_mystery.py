"""Moves mystery tiles off the bottom layer of authored boards (build/boards).

Producer 2026-11-10: a "?" on the bottom layer means nothing, the level is as
good as won by then. The flag moves to a plain tile on a higher layer (middle
layers first); the winning order is untouched since mystery only hides a
dessert. Usage: python3 tools/lift_mystery.py [seed=N] [src=DIR] [out=DIR] [ids...]
Several seeds give different placements; tools pick the one whose measured
difficulty stays closest to the original board's."""
import json, pathlib, random, sys
root = pathlib.Path(__file__).resolve().parents[1]
MECH = ("mystery", "ice", "key", "lock", "fuse", "stack")
opts = dict(a.split("=", 1) for a in sys.argv[1:] if "=" in a)
ids = [int(a) for a in sys.argv[1:] if "=" not in a] or None
seed = int(opts.get("seed", 0))
src = root / opts.get("src", "build/boards")
out = root / opts.get("out", "build/boards")
out.mkdir(parents=True, exist_ok=True)
for f in sorted(src.glob("*.json"), key=lambda p: int(p.stem)):
    if ids and int(f.stem) not in ids:
        continue
    b = json.loads(f.read_text())
    tiles = b["board"]["tiles"]
    board = [t for t in tiles if "stack" not in t]
    low = [t for t in board if t.get("mystery") and t["layer"] == 0]
    if not low:
        continue
    top = max(t["layer"] for t in board)
    rng = random.Random(int(f.stem) * 1000 + seed)
    plain = [t for t in board if t["layer"] > 0 and not any(t.get(k) for k in MECH)]
    rng.shuffle(plain)
    plain.sort(key=lambda t: 0 if t["layer"] < top else 1)
    for t, to in zip(low, plain):
        del t["mystery"]
        to["mystery"] = True
    (out / f.name).write_text(json.dumps(b))
    print(f.stem, "moved", min(len(low), len(plain)), "of", len(low))

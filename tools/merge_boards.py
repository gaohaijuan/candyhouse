"""Merges data/level_plan.json with authored boards in build/boards into data/levels.json."""
import json, pathlib
root = pathlib.Path(__file__).resolve().parents[1]
plan = json.loads((root / "data" / "level_plan.json").read_text())["levels"]
out = []
for L in plan:
    f = root / "build" / "boards" / f"{L['id']}.json"
    b = json.loads(f.read_text())
    if not b.get("board"):
        raise SystemExit(f"level {L['id']}: no authored board")
    L = dict(L)
    L["types"] = b["types"]
    L["board"] = b["board"]
    L["rating"] = round(b["rating"], 1)
    L["measured"] = {"skilled": round(b["skilled"], 2), "casual": round(b["casual"], 2)}
    out.append(L)
(root / "data" / "levels.json").write_text(json.dumps({"levels": out}, ensure_ascii=False, separators=(",", ":")))
print("merged", len(out))

"""Builds data/levels.json from a readable level plan.

Each new mechanic gets five levels of rising difficulty, then it is combined
with an earlier one, as agreed with the producer (2026-11-07). Tile counts are
trimmed to a multiple of three. Run: python3 tools/build_levels.py
"""
import json, pathlib

def rect(c, r, ox=0, oy=0, mask=None):
    layer = {"cols": c, "rows": r, "offset": [ox, oy]}
    if mask:
        layer["mask"] = mask
    return layer

SHAPES = {
    "mini":     [rect(4, 3), rect(3, 2, 1, 1)],
    "small":    [rect(5, 4), rect(4, 3, 1, 1)],
    "brick":    [rect(6, 4), rect(5, 3, 1, 1)],
    "brick3":   [rect(6, 4), rect(5, 3, 1, 1), rect(3, 2, 3, 2)],
    "heart":    [rect(6, 5, mask=["110011", "111111", "111111", "011110", "001100"]),
                 rect(5, 4, 1, 1, mask=["11111", "11111", "01110", "00100"])],
    "heart3":   [rect(6, 5, mask=["110011", "111111", "111111", "011110", "001100"]),
                 rect(5, 4, 1, 1, mask=["11111", "11111", "01110", "00100"]), rect(4, 3, 2, 2)],
    "diamond":  [rect(7, 5, mask=["0011100", "0111110", "1111111", "0111110", "0011100"]),
                 rect(6, 4, 1, 1, mask=["001100", "011110", "011110", "001100"]), rect(4, 3, 3, 2)],
    "butterfly":[rect(7, 5, mask=["1100011", "1110111", "0111110", "1110111", "1100011"]),
                 rect(6, 4, 1, 1, mask=["110011", "111111", "111111", "110011"]), rect(4, 3, 3, 2)],
    "flower":   [rect(7, 5, mask=["0111110", "1111111", "1111111", "1111111", "0111110"]),
                 rect(6, 4, 1, 1, mask=["011110", "111111", "111111", "011110"]),
                 rect(4, 3, 3, 2, mask=["0110", "1111", "0110"])],
    "cake":     [rect(7, 5, mask=["0011100", "0111110", "1111111", "1111111", "1111111"]),
                 rect(6, 4, 1, 1, mask=["011110", "111111", "111111", "111111"]),
                 rect(4, 3, 3, 2, mask=["0110", "1111", "1111"])],
    "tower":    [rect(7, 5), rect(6, 4, 1, 1), rect(4, 3, 3, 2), rect(2, 2, 5, 3)],
    "grand":    [rect(7, 5, mask=["0111110", "1111111", "1111111", "1111111", "0111110"]),
                 rect(6, 4, 1, 1), rect(5, 3, 2, 2), rect(3, 2, 4, 3)],
}

# Dense boards: a shape's base mask, the inner mask on the half-offset grid,
# then the base again on top (and the inner again for the deepest levels), so
# most tiles start covered. Agreed after the 2026-11-07 difficulty review.
PAIRS = {
    "mini": (["1111", "1111", "1111"], ["111", "111"]),
    "small": (["11111"] * 4, ["1111"] * 3),
    "brick": (["111111"] * 4, ["11111"] * 3),
    "brick3": (["111111"] * 4, ["11111"] * 3),
    "heart": (["110011", "111111", "111111", "011110", "001100"], ["11111", "11111", "01110", "00100"]),
    "heart3": (["110011", "111111", "111111", "011110", "001100"], ["11111", "11111", "01110", "00100"]),
    "diamond": (["0011100", "0111110", "1111111", "0111110", "0011100"], ["001100", "011110", "011110", "001100"]),
    "butterfly": (["1100011", "1110111", "0111110", "1110111", "1100011"], ["110011", "111111", "111111", "110011"]),
    "flower": (["0111110", "1111111", "1111111", "1111111", "0111110"], ["011110", "111111", "111111", "011110"]),
    "cake": (["0011100", "0111110", "1111111", "1111111", "1111111"], ["011110", "111111", "111111", "111111"]),
    "tower": (["1111111"] * 5, ["111111"] * 4),
    "grand": (["0111110", "1111111", "1111111", "1111111", "0111110"], ["111111"] * 4),
}

def dense(shape, depth, airy=False):
    """`airy`: the top copy of the base keeps a checkerboard of its tiles, so
    lower tiles peek through (needed where candles must be covered yet seen)."""
    a, b = PAIRS[shape]
    base = rect(len(a[0]), len(a), 0, 0, a)
    inner = rect(len(b[0]), len(b), 1, 1, b)
    top = json.loads(json.dumps(base))
    if airy:
        top["mask"] = ["".join(ch if (r + c) % 2 == 0 else "0" for c, ch in enumerate(row)) for r, row in enumerate(a)]
    layers = [base, inner, top]
    if depth <= 2:
        layers = [base, inner]
    if depth >= 4:
        layers.append(json.loads(json.dumps(inner)))
    return layers

def count(layers, stacks):
    n = 0
    for L in layers:
        n += sum(r.count("1") for r in L["mask"]) if "mask" in L else L["cols"] * L["rows"]
    return n + sum(stacks)

def trim(layers, stacks):
    """Removes cells from the top layer's middle until the total divides by 3."""
    layers = json.loads(json.dumps(layers))
    while count(layers, stacks) % 3:
        top = layers[-1]
        if "mask" not in top:
            top["mask"] = ["1" * top["cols"] for _ in range(top["rows"])]
        rows = top["mask"]
        r = len(rows) // 2
        c = rows[r].find("1", len(rows[r]) // 2) if "1" in rows[r][len(rows[r]) // 2:] else rows[r].find("1")
        rows[r] = rows[r][:c] + "0" + rows[r][c + 1:]
    return layers

# id: (shape, types, mechanics, target win %)
PLAN = [
    # Basics
    ("mini", 6, {"tutorial": True}, 92),
    ("brick", 6, {}, 75),
    ("brick3", 7, {}, 58),
    # Mystery x5
    # 2026-11-08 producer: the first mystery levels were far too hard.
    ("heart", 6, {"mystery": 5, "intro": "mystery"}, 86),
    ("brick", 6, {"mystery": 5}, 74),
    ("heart3", 7, {"mystery": 6}, 60),
    ("diamond", 7, {"mystery": 8}, 50),
    ("flower", 7, {"mystery": 10}, 40),
    # Ice x5. 2026-11-08 producer: ice was too weak (one or two blocks that
    # thawed after one triple); now more blocks, stronger, over other tiles.
    ("small", 6, {"ice": [3, 3, 4, 4], "intro": "ice"}, 86),
    ("brick", 6, {"ice": [3, 3, 4, 4]}, 74),
    ("heart3", 7, {"ice": [3, 4, 4, 5]}, 60),
    ("butterfly", 7, {"ice": [3, 4, 4, 5, 5]}, 50),
    ("cake", 7, {"ice": [4, 4, 5, 5, 6]}, 40),
    # Mystery + Ice x5
    ("heart", 6, {"mystery": 4, "ice": [2, 2]}, 72),
    ("brick3", 7, {"mystery": 6, "ice": [2, 2, 3]}, 60),
    ("diamond", 7, {"mystery": 8, "ice": [2, 3, 3]}, 50),
    ("flower", 8, {"mystery": 10, "ice": [3, 3, 4]}, 40),
    ("tower", 8, {"mystery": 10, "ice": [3, 3, 4]}, 32),  # eased 2026-11-09: rarely winnable without boosters
    # Box x5
    ("small", 6, {"stacks": [8, 8], "intro": "box"}, 84),
    ("brick", 6, {"stacks": [6, 6]}, 72),
    ("heart3", 7, {"stacks": [7, 7]}, 60),
    ("butterfly", 7, {"stacks": [8, 8]}, 50),
    ("cake", 7, {"stacks": [9, 9]}, 40),
    # Lock x5
    ("brick", 6, {"locks": 2, "intro": "lock"}, 84),
    ("brick3", 6, {"locks": 1}, 72),
    ("heart3", 7, {"locks": 2}, 60),
    ("diamond", 7, {"locks": 2}, 50),
    ("flower", 7, {"locks": 3}, 40),
    # Box + Lock x5
    ("brick", 6, {"stacks": [6, 6], "locks": 1}, 70),
    ("heart3", 7, {"stacks": [6, 6], "locks": 1}, 60),
    ("butterfly", 7, {"stacks": [7, 7], "locks": 2}, 50),
    ("cake", 7, {"stacks": [8, 8], "locks": 2}, 40),
    ("tower", 8, {"stacks": [9, 9], "locks": 3}, 32),
    # Candle x5
    ("brick3", 6, {"candles": [12], "intro": "candle"}, 82),
    ("heart3", 6, {"candles": [10]}, 72),
    ("diamond", 7, {"candles": [8]}, 60),
    ("butterfly", 7, {"candles": [7, 9]}, 50),
    ("flower", 7, {"candles": [8, 10]}, 40),  # [6, 8] left no winnable board without boosters
    # Candle + Ice x5
    ("brick3", 6, {"candles": [10], "ice": [2, 2]}, 70),
    ("heart3", 7, {"candles": [9], "ice": [2, 2, 3]}, 60),
    ("diamond", 7, {"candles": [8, 10], "ice": [2, 3, 3]}, 50),
    ("cake", 7, {"candles": [7, 9], "ice": [3, 3, 4]}, 40),
    ("tower", 8, {"candles": [6, 8], "ice": [3, 3, 4, 4]}, 32),
    # Three mechanics
    ("heart3", 7, {"mystery": 6, "ice": [2, 2, 3], "stacks": [6, 6]}, 55),
    ("flower", 7, {"mystery": 8, "ice": [2, 3, 3], "stacks": [7, 7]}, 45),
    ("diamond", 7, {"locks": 2, "candles": [9], "stacks": [6, 6]}, 50),
    ("cake", 8, {"locks": 2, "candles": [8, 10], "stacks": [7, 7]}, 40),
    ("tower", 8, {"locks": 2, "candles": [8], "mystery": 10}, 35),
    # Finale
    ("grand", 8, {"mystery": 8, "ice": [3, 3, 4], "stacks": [8, 8], "locks": 2, "candles": [9]}, 25),
    # Eased 2026-11-09: with every mechanic at full strength no board was winnable without boosters.
    ("grand", 8, {"mystery": 8, "ice": [3, 3, 4], "stacks": [8, 8], "locks": 2, "candles": [10, 12], "boss": True}, 18),
]

INTROS = {
    "mystery": {"title": "神秘方块", "text": "问号方块里的甜点看不见\n拿进托盘时才会揭晓"},
    "ice": {"title": "冰封方块", "text": "冰上的数字是还要消除的次数\n每消除一组,冰就融化一点"},
    "box": {"title": "甜点盒", "text": "两侧的甜点盒一次只能拿最上面一块"},
    "lock": {"title": "糖果锁", "text": "带锁的方块暂时不能拿\n消除带钥匙的那组甜点,锁就会打开"},
    "candle": {"title": "生日蜡烛", "text": "蜡烛上的数字是剩余步数\n烧完之前一定要把它拿走"},
}

def build(overrides=None):
    overrides = overrides or {}
    levels = []
    for i, (shape, types, mech, target) in enumerate(PLAN):
        lid = i + 1
        o = overrides.get(lid, {})
        shape = o.get("shape", shape)
        types = o.get("types", types)
        mech = {**mech, **o.get("mech", {})}
        stacks = mech.get("stacks", [])
        level = {"id": lid, "types": types, "max_open": 1, "seed": lid * 101, "shape": shape,
                 "layers": trim(SHAPES[shape], stacks)}
        if stacks:
            level["stacks"] = [{"count": c} for c in stacks]
        for key in ("mystery", "ice", "locks", "candles"):
            if mech.get(key):
                level[key] = mech[key]
        if mech.get("tutorial"):
            level["tutorial"] = True
        if mech.get("boss"):
            level["boss"] = True
        if mech.get("intro"):
            level["intro"] = INTROS[mech["intro"]]
        t = o.get("target", target)
        level["target_win_pct"] = [max(0, t - 18), min(100, t + 18)]
        levels.append(level)
    return levels

# Target difficulty (1-10, see tests/sweep_levels.gd rating) agreed with the
# producer on 2026-11-07: most levels about 6, a block's last level about 8,
# a mechanic's first level a little lower so it can be learned.
BLOCK_TARGETS = {
    # 2026-11-08 producer: level 1 was unwinnable without boosters. The
    # first levels are an on-ramp a newcomer clears without boosters.
    "basics": [1.0, 2.5, 4.0],
    # 2026-11-09 producer: after the no-booster re-author everything was too
    # easy. Middle ground: a mechanic's first level is ordinary (anyone wins
    # and learns what it is for), ordinary levels need patience and skill, a
    # block's last level needs a clever, patient and slightly lucky player.
    "single": [5.0, 6.0, 6.5, 7.0, 8.8],
    # Hidden desserts are harder for people than the bots measure; gentler.
    "mystery": [4.5, 5.5, 6.0, 6.5, 8.3],
    "pair": [6.0, 6.5, 7.0, 7.5, 8.8],
    "triple": [6.5, 7.0, 7.5, 8.0, 9.0],
    "finale": [9.0, 9.3],
}
BLOCKS = [("basics", 3), ("mystery", 5), ("single", 5), ("pair", 5), ("single", 5), ("single", 5),
          ("pair", 5), ("single", 5), ("pair", 5), ("triple", 5), ("finale", 2)]

def targets():
    out = []
    for kind, n in BLOCKS:
        out.extend(BLOCK_TARGETS[kind][:n])
    return out

# Ratings are measured without boosters (2026-11-08), which needs fewer
# desserts than before; the author steps through the range towards the target.
def types_range(t):
    # Widened 2026-11-09: the first harder run hit the old ceilings (11-12
    # desserts) and still came out easy; there are 20 desserts in the art.
    if t < 1.5: return [3, 5]
    if t < 2.5: return [4, 6]
    if t < 4.0: return [4, 9]
    if t < 5.0: return [5, 11]
    if t < 6.6: return [7, 15]
    if t < 7.6: return [8, 16]
    if t < 8.6: return [9, 17]
    return [10, 18]

def plan():
    levels = build({})
    for L, t in zip(levels, targets()):
        stacks = [s["count"] for s in L.get("stacks", [])]
        depth = 2 if t < 2.5 else (4 if t >= 7.0 else 3)
        L["layers"] = trim(dense(L["shape"], depth, airy=bool(L.get("candles"))), stacks)
        L["target_rating"] = t
        L["types_range"] = types_range(t)
        L["types"] = sum(types_range(t)) // 2
        L.pop("target_win_pct", None)
        # A mechanic's first level must make it matter (producer 2026-11-09:
        # ice that is gone after two triples teaches nothing): the careful
        # player's win rate must drop this much when the mechanic is on.
        if L.get("intro") and not L.get("stacks"):
            L["impact"] = 0.2
    return levels

if __name__ == "__main__" and "--plan" in __import__("sys").argv:
    root = pathlib.Path(__file__).resolve().parents[1]
    levels = plan()
    (root / "data" / "level_plan.json").write_text(json.dumps({"levels": levels}, ensure_ascii=False, indent=1))
    print("plan levels:", len(levels))
    raise SystemExit

if __name__ == "__main__":
    root = pathlib.Path(__file__).resolve().parents[1]
    over_path = root / "tools" / "level_overrides.json"
    overrides = {}
    if over_path.exists():
        overrides = {int(k): v for k, v in json.loads(over_path.read_text()).items()}
    levels = build(overrides)
    (root / "data" / "levels.json").write_text(json.dumps({"levels": levels}, ensure_ascii=False, indent=1))
    for L in levels:
        n = count(L["layers"], [s["count"] for s in L.get("stacks", [])])
        assert n % 3 == 0, (L["id"], n)
    print("levels:", len(levels))

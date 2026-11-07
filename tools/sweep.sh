#!/bin/bash
# Parallel difficulty sweep: tools/sweep.sh [trials] [level ids...]  (default: all levels)
cd "$(dirname "$0")/.."
TRIALS=${1:-40}; shift
LEVELS=${LEVELS:-data/levels.json}
IDS="$@"
if [ -z "$IDS" ]; then IDS=$(python3 -c "import json,sys;print(' '.join(str(l['id']) for l in json.load(open(sys.argv[1]))['levels']))" "$LEVELS"); fi
OUT=$(mktemp -d)
for id in $IDS; do
  (timeout 1500 godot --headless --path . --script res://tests/sweep_levels.gd -- trials=$TRIALS levels=$(realpath "$LEVELS") $id 2>&1 | grep -E "^L" > "$OUT/$id.txt") &
  while [ "$(jobs -r | wc -l)" -ge 24 ]; do sleep 1; done
done
wait
for id in $IDS; do cat "$OUT/$id.txt"; done
rm -rf "$OUT"

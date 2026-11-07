#!/bin/bash
# Authors every level in parallel: tools/author_all.sh [candidates] [trials] [ids...]
cd "$(dirname "$0")/.."
C=${1:-10}; T=${2:-16}; shift 2
IDS="$@"
if [ -z "$IDS" ]; then IDS=$(python3 -c "import json;print(' '.join(str(l['id']) for l in json.load(open('data/level_plan.json'))['levels']))"); fi
mkdir -p build/boards build/author_logs
for id in $IDS; do
  (timeout 5400 godot --headless --path . --script res://tools/author.gd -- $id candidates=$C trials=$T > build/author_logs/$id.log 2>&1) &
  while [ "$(jobs -r | wc -l)" -ge 26 ]; do sleep 2; done
done
wait
for id in $IDS; do grep -h "^L$id target" build/author_logs/$id.log; done

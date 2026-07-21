#!/usr/bin/env bash
# End-to-end smoke checks: drive the plugin against the REAL `but` CLI in this
# workspace. Unlike `make test` (pure, hermetic), these need a live GitButler
# workspace. They SKIP steps whose state is absent and only FAIL on a
# regression, so this is safe to run on any GitButler repo.
#
# Exits 0 and skips (not fails) when `but` is unavailable or this is not a
# GitButler workspace, so CI without `but` stays green.
set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root" || exit 1

if ! command -v but >/dev/null 2>&1; then
  echo "smoke: 'but' CLI not on PATH — skipping end-to-end checks."
  exit 0
fi
if ! but status >/dev/null 2>&1; then
  echo "smoke: not a GitButler workspace (run 'but setup') — skipping."
  exit 0
fi
if ! command -v nvim >/dev/null 2>&1; then
  echo "smoke: nvim not on PATH — skipping."
  exit 0
fi

scratch="SMOKE_SCRATCH.txt"
cleanup() { rm -f "$scratch"; }
trap cleanup EXIT INT TERM

printf 'smoke scratch line one\nsmoke scratch line two\n' >"$scratch"

phases=(
  tests/smoke/phase1_graph.lua
  tests/smoke/phase2_modes.lua
  tests/smoke/phase3_details.lua
)

rc=0
for phase in "${phases[@]}"; do
  echo "=== $phase ==="
  if ! nvim --clean --headless -l "$phase"; then
    echo "  -> FAILED"
    rc=1
  fi
  echo
done

if [ "$rc" -eq 0 ]; then
  echo "smoke: all phases passed."
else
  echo "smoke: one or more phases FAILED."
fi
exit "$rc"

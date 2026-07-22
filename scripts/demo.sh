#!/usr/bin/env bash
# Regenerate the README demo GIFs from the .tape scripts in doc/demo/.
# Requires vhs (https://github.com/charmbracelet/vhs) and a GitButler workspace.
# Run from the repo root: `make demo`.
set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root" || exit 1

if ! command -v vhs >/dev/null 2>&1; then
  echo "demo: 'vhs' not on PATH — install charmbracelet/vhs to regenerate the GIFs."
  exit 1
fi
if ! command -v but >/dev/null 2>&1 || ! but status >/dev/null 2>&1; then
  echo "demo: needs a GitButler workspace (run 'but setup')."
  exit 1
fi

# The graph needs an uncommitted change to show; stage a throwaway file.
scratch="DEMO.md"
cleanup() { rm -f "$scratch"; }
trap cleanup EXIT INT TERM
printf '# Demo change\n\nA new file so the workspace has an uncommitted change to show.\nAssign it to a branch, commit it, or open it — from the graph.\n' >"$scratch"

for tape in doc/demo/butler.tape doc/demo/rub.tape; do
  echo "=== $tape ==="
  vhs "$tape" || { echo "  -> FAILED"; exit 1; }
done

echo "demo: GIFs regenerated in doc/demo/."

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

# For the richest recording the graph wants an applied feature branch with a
# couple of commits, an uncommitted change, and landed history below the base.
# This script only stages the uncommitted change; set up (and later tear down)
# a demo branch by hand for the full hero — e.g.
#   printf 'local M = {}\nreturn M\n' > .demo/auth.lua
#   but commit demo/auth-endpoint -c -m "feat(auth): token verification" --changes <id>
# The landed history below the common base is whatever `git log <base>` already
# shows, so no setup is needed for the landed-history / details recordings.
scratch="DEMO.md"
cleanup() { rm -f "$scratch"; }
trap cleanup EXIT INT TERM
printf '# Release notes\n\n- Token verification on the login route\n- Inline landed history in the graph\n' >"$scratch"

for tape in doc/demo/butler.tape doc/demo/rub.tape doc/demo/landed-history.tape doc/demo/details.tape; do
  echo "=== $tape ==="
  vhs "$tape" || { echo "  -> FAILED"; exit 1; }
done

echo "demo: GIFs regenerated in doc/demo/."

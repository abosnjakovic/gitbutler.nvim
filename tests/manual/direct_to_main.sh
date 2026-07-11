#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

ORIGIN=$(mktemp -d)
WORK=$(mktemp -d)

cleanup() {
  rm -rf "$ORIGIN" "$WORK"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# --- Scenario 1: happy path ---------------------------------------------------
#
# direct_to_main commits the change to an ephemeral branch, then `but land`s it
# straight onto the target. Land fast-forwards origin's target, pushes it, and
# reconciles the workspace — leaving no ephemeral branch behind. Note that land
# operates on GitButler's target, not the local plain `main` ref, so we assert on
# origin/main (the local `main` checkout is not expected to move).

git init --bare --initial-branch=main "$ORIGIN" >/dev/null
git clone "$ORIGIN" "$WORK" >/dev/null 2>&1
cd "$WORK"
git config user.email "test@example.com"
git config user.name "Test"
echo "seed" > a.txt
git add a.txt
git commit -q -m "init"
git push -q origin main

but setup >/dev/null 2>&1 || fail "but setup failed in $WORK"

echo "change-1" >> a.txt

nvim --headless --cmd "set rtp^=$REPO_ROOT" -u "$REPO_ROOT/tests/minimal_init.lua" \
  -c "lua local err = require('gitbutler.actions').direct_to_main_test_harness('a.txt', 'commit msg 1'); if err then vim.cmd('cquit 1') end" \
  -c "qa" 2>&1 || fail "headless run errored"

git fetch -q origin
git log origin/main -1 --format=%s | grep -q "commit msg 1" || fail "commit msg 1 not on origin/main"

git branch | grep -q "direct-to-main-" && fail "local ephemeral branch lingered"
remote_ephemeral=$(git ls-remote origin "refs/heads/direct-to-main-*" || true)
[ -z "$remote_ephemeral" ] || fail "remote ephemeral branch lingered: $remote_ephemeral"

echo "OK scenario 1 (happy path)"

echo "ALL OK"

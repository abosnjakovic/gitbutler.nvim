#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

ORIGIN=$(mktemp -d)
WORK=$(mktemp -d)
WORK_DIVERGE=$(mktemp -d)

cleanup() {
  rm -rf "$ORIGIN" "$WORK" "$WORK_DIVERGE"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# --- Scenario 1: happy path ---------------------------------------------------

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
local_main=$(git rev-parse main)
origin_main=$(git rev-parse origin/main)
[ "$local_main" = "$origin_main" ] || fail "main not pushed (local=$local_main origin=$origin_main)"
git log origin/main -1 --format=%s | grep -q "commit msg 1" || fail "commit msg 1 not on origin/main"

git branch | grep -q "direct-to-main-" && fail "local ephemeral branch lingered"
remote_ephemeral=$(git ls-remote origin "refs/heads/direct-to-main-*" || true)
[ -z "$remote_ephemeral" ] || fail "remote ephemeral branch lingered: $remote_ephemeral"

echo "OK scenario 1 (happy path)"

# --- Scenario 2: divergent local target --------------------------------------

git clone "$ORIGIN" "$WORK_DIVERGE" >/dev/null 2>&1
cd "$WORK_DIVERGE"
git config user.email "test@example.com"
git config user.name "Test"

# Make local main diverge from origin/main BEFORE but setup installs its pre-commit hook.
# Then in a *different* commit chain, the test harness will commit on the workspace
# target (also origin/main), producing a commit whose parent equals origin/main but
# which is NOT a descendant of the new local main tip — so is_fast_forward returns false.
echo "divergent-local-change" >> a.txt
git add a.txt
git commit -q -m "divergent local commit"
# (no push — local main is now ahead of origin/main)

but setup >/dev/null 2>&1 || fail "but setup failed in $WORK_DIVERGE"

before_local=$(git rev-parse main)
before_origin=$(git rev-parse origin/main)

echo "change-2" >> a.txt

# Expect the harness to return an error (cquit 1). Don't fail the script on it.
set +e
nvim --headless --cmd "set rtp^=$REPO_ROOT" -u "$REPO_ROOT/tests/minimal_init.lua" \
  -c "lua local err = require('gitbutler.actions').direct_to_main_test_harness('a.txt', 'commit msg 2'); if err then vim.cmd('cquit 1') end" \
  -c "qa" >/dev/null 2>&1
rc=$?
set -e

[ "$rc" -ne 0 ] || fail "scenario 2: harness should have failed but returned 0"

after_local=$(git rev-parse main)
after_origin=$(git rev-parse origin/main)
[ "$before_local" = "$after_local" ] || fail "scenario 2: local main mutated ($before_local → $after_local)"
[ "$before_origin" = "$after_origin" ] || fail "scenario 2: origin/main mutated ($before_origin → $after_origin)"

echo "OK scenario 2 (divergent local target rejected)"

echo "ALL OK"

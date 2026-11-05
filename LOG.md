# Log

One entry per unit of work, newest at the bottom. Earlier entries are not
rewritten; a box is ticked in place when the work lands, and the newer entry
says where.

## 2026-11-04 · feat/but-0-23 · the 0.23 migration

**Done** — `but` 0.23 moved three things under the plugin: worktrees joined the
status payload, `land` became `merge`, and `but setup` disappeared.

The version floor is 0.23.0 (`lua/gitbutler/cli.lua`), probed by asking whether
`but worktree --help` exits zero. That retired three capability probes and the
help cache behind them: the uncommitted area is always `@`, and `split` and
`move -m` always exist, so `uncommitted_id`, `has_split` and `move_takes_message`
are gone along with their guards in `actions.lua` and `ui/modes.lua`.

Worktrees render between the stacks and the upstream row (`ui/graph.lua`). The
section reuses the existing row types, so diff, amend, squash and move address a
worktree with no new code; building it needed `push_file` and `push_branch`,
which the stacks loop now shares as well. `W` opens worktree mode — new,
archive, unarchive, remove — over five `cli.worktree_*` wrappers.

Verified: `make ci` green, 476 tests. Live against a scratch repo — created a
worktree, rendered it, diffed `li:@`, entered the mode with `W`, removed it with
the discarding answer, and watched the section leave the graph.
`tests/manual/direct_to_main.sh` passes with no `but setup` and `but merge`
doing the landing.

Assumed: that `but land` stays an alias of `merge` for as long as people have
0.23 installed. The plugin sends `merge`.

**Version control** — branch `feat/but-0-23`, commit `oyo`
("feat(cli)!: speak but 0.23 — worktrees, merge, no setup"). Nothing pushed.

**Deferred**
- [x] Committed hunk ids. `but diff <commit>` prints `yqxn:nkns:b211` but
  `--json` omits `id` on committed changes on 0.23.0, so the TUI's committed-hunk
  marking is unreachable. Re-probe on 0.23.2. *(Done in the next entry.)*
- [x] `--status-after` would fold each mutation and its refresh into one call.
  Measure before building. *(Measured in the next entry; declined.)*

**Open**
- [x] `changeId` now rides on status commits, but `upstreamCommits[]` entries
  return `changeId: null`, so `commit_dot`'s subject heuristic for rewritten
  commits cannot be upgraded. *(Re-checked on 0.23.2 in the next entry; still
  null, and the comment now records that.)*
- No `LOG.md` entry. That rule is written for the dotfiles repo; this one has
  none and generates its changelog with release-please. *(This file is the
  answer, added in the next entry.)*

**What I need from you** — 1. Update `but` to 0.23.2 and say so, since the one
thing blocking committed-hunk ops is whether the ids reached `--json`.

## 2026-11-04 · feat/but-0-23 · the deferred items

**Done** — all three deferred items closed, two of them with code.

Committed hunk ids: on 0.23.2 `but diff <commit> --json` still has no `id` on
its changes, but the ids exist and every mutation takes them — `but discard
oqko:rlnq:5604` and `but squash -t … oqko:nkns:940e` both work. They are
published in the text output's header boxes, so `cli._parse_hunk_ids` reads them
and `details._attach_hunk_ids` pairs them with the decoded hunks by path in
order. A mismatch leaves the remaining hunks without an id rather than labelling
one with another's. `details.build` now prefers a per-hunk id over the change's,
which is what makes a multi-hunk committed file work at all.

That makes the pane's existing verbs live on a commit's diff: `<Space>` marks,
`x` discards from the commit. Added `S` (squash into another commit) and `m`
(move out into a new commit or onto a branch), both through the modes that
already exist; the three share `hunks_to_mode`. `a` now refuses a committed hunk
and names `S`, since `but amend` takes uncommitted changes only.

`--status-after`: declined. Measured with 0.23.2 — `status --json -f -v` is
17 ms in a scratch repo and 20 ms in this one. Threading an embedded status
through every mutation callback, and keeping the separate-refresh path for the
commands that do not support the flag, costs more than one 20 ms spawn is worth.

Upstream change ids: still null on 0.23.2, so `commit_dot` keeps matching on
subject text. The comment in `ui/graph.lua` now records the probe so nobody
repeats it.

Verified: `make ci` green, 483 tests. Live against a scratch repo with a
three-hunk commit — the pane showed `uzls:rlnq:7940`, `uzls:nkns:01f5` and
`uzls:nkns:940e`, `a` refused with the squash hint, `S` entered squash mode, and
`x` discarded `uzls:nkns:01f5`, after which `but diff uzls` listed only the other
two.

**Version control** — branch `feat/but-0-23`. Nothing pushed.

**Open**
- [x] `/opt/homebrew/bin/but` is a symlink into `/Applications/GitButler.app`
  and still reports 0.23.0; `~/.local/bin/but` is the 0.23.2 one that `but
  update install` wrote. Whichever comes first in `PATH` is the one the plugin
  runs. *(Fixed in the next entry.)*

**What I need from you** — nothing.

## 2026-11-04 · the two `but` installs, and landing defaults to Yes

**Done** — the version split was not a `PATH` problem so much as two apps. All
three `but` symlinks pointed into a GitButler bundle: `/opt/homebrew/bin/but`
and `/usr/local/bin/but` at `/Applications/GitButler.app` (0.23.0, 55 MB, 3
November), `~/.local/bin/but` at `~/Applications/GitButler.app` (0.23.2, 106 MB,
4 November). `but update install` had written a second copy beside the first
rather than replacing it, and `/opt/homebrew/bin` comes first in the fish
`PATH`, so every shell got the old one.

Consolidated on one app: moved the 0.23.0 bundle to `~/.Trash/GitButler-0.23.0.app`,
moved the 0.23.2 bundle from `~/Applications` into `/Applications`, and
repointed `~/.local/bin/but` at it so nothing dangles. All three paths now
report 0.23.2, `codesign --verify --deep --strict` passes, and no `sudo` was
needed: the root-owned symlink in `/usr/local/bin` was never touched, only what
it points at.

Landing now defaults to Yes (`lua/gitbutler/actions.lua`). `L` on branch or
commit rows offered `{ 'No', 'Yes' }`, so `<CR>` declined; the prompt is there
to name the branches, not to argue, and the keystroke already said what it
wanted. Every other confirmation keeps its old default: discard, undo, redo,
branch delete, oplog restore and worktree remove all lose work, where a stray
`<CR>` should cost nothing.

Verified: `make ci` green, 484 tests, one of them pinning the option order
through `actions.direct_to_main`. Live against a scratch repo with a bare
origin — the prompt read "Land ship-it onto the target? Yes / No", answering
with the first option (what `<CR>` takes) landed `ship this` onto `origin/main`
and left the workspace on a single stack.

**Version control** — branch `feat/but-0-23`. Nothing pushed.

**What I need from you** — nothing. Worth knowing for next time: when the
in-app updater runs, check `~/Applications` for a second bundle rather than
trusting `but --version` from whichever shell you happen to be in.

## 2026-11-05 · PR #33 and the review round

**Done** — opened the branch as a draft PR and ran two reviews over it, one
for correctness and one for safety. Eight of their findings landed as code.

From the code review: `worktree list` only shows the three most recently
updated archived worktrees in its human output, so the unarchive picker now
calls `worktree list --archived` through `cli.worktree_archived`. A worktree's
uncommitted rows share paths with the workspace's, and `row_ref` returned nil
for both, so a review comment written on one surfaced on the other; worktree
rows now anchor on the worktree name. `committed_diff()` reads `entity.scope`
rather than the row kind, so a landed commit gets an honest message. A missing
`cliId` renders `??` and makes the header unselectable instead of building the
target `:@`. The test that claimed to cover the commit path stubbed neither
call and passed on `show`'s initial `selected = 1` while spawning a real
`but`; it now stubs both and asserts the ids reached the hunks.

From the security review: `but diff <commit>` abbreviates the commit segment
to whatever prefix is unique inside that one diff (`o:uy:f3` where status says
`oyo:uy`), and a prefix only holds in the context that printed it, so
`_attach_hunk_ids` rewrites it with the commit the pane is showing. A path
whose text and JSON hunk counts disagree now keeps no ids at all, which makes
the docstring's "never labels a hunk with another hunk's id" true rather than
true-by-luck. The pane's discard prompt names the commit it rewrites, the way
the status view's own does. Worktree mutations send the CLI id instead of the
display name, since `but worktree remove` takes an id, a name or a path in one
argument and a linked checkout's uncommitted work is not in the oplog.
`Buffer:_set_keymaps` checks the buffer is still valid, because a mode can now
exit from an async callback after the view closed under it.

Not taken: the reviewer's call to revert the land prompt to `No` first. You
asked for `Yes`, so it stays, and the prompt carries the cost instead: "Land X
onto the target? This pushes to the remote." Their evidence stands and is worth
recording — `cli.merge` passes `--yes`, which suppresses but's own guard, so
this prompt is the only one left, and `but undo` cannot unpush.

Also corrected: the claim in the `land defaults to Yes` commit message that
every work-losing confirmation keeps `No` first. It does not. Discard, undo,
redo, branch delete and oplog restore are all `Yes` first already, and all are
oplog-recoverable. Land and worktree remove were the two `No`-first ones, and
they are exactly the two `but undo` cannot reverse.

Verified: `make ci` green, 488 tests. Live against a scratch repo — a commit's
hunk ids came back qualified (`utwx:nkns:01f5`), the discard prompt read
"Discard 1 hunk(s) in a.txt from commit 06fd02d?", the discard resolved, and
`W` `x` sent `si` rather than `side-work`.

**Version control** — branch `feat/but-0-23`, pushed. PR
[#33](https://github.com/abosnjakovic/gitbutler.nvim/pull/33), draft.

**Open**
- [ ] The land prompt defaults to `Yes` on an action `but undo` cannot
  reverse. Reverting is two words in `lua/gitbutler/actions.lua:534`.

**What I need from you** — 1. Say whether the land prompt keeps `Yes` first
now that the cost is spelled out, or goes back to `No`. 2. Mark PR #33 ready
when you want it out of draft.

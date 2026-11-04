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
- `/opt/homebrew/bin/but` is a symlink into `/Applications/GitButler.app` and
  still reports 0.23.0; `~/.local/bin/but` is the 0.23.2 one that `but update
  install` wrote. Whichever comes first in `PATH` is the one the plugin runs.

**What I need from you** — nothing.

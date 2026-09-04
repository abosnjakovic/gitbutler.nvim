## [3.1.0] - 2026-09-04

### Features

- feat(details): comment on landed commits, through the one diff renderer
- feat(details): re-place the pane when the layout changes under it
- feat(details): place the pane below the status window when it is narrow
- feat(float): <CR> saves in normal mode, and Esc no longer discards
- feat(help): generate the float per context from the registry
- feat(hints): fall back to the view's own registry keys
- feat(hotbar): take items from the registry
- feat(keys): one registry for what every key does
- feat(details): C comments a diff line and Y yanks the review
- feat(details): thread the diff's scope and ref onto the entity
- feat(float): let a caller opt into empty submits
- feat(details): render line comments as rows with a stale check
- feat(details): keep the side and line number the gutter computes
- feat(review): format the collected comments for the clipboard
- feat(review): comment store keyed on scope, ref, path, side and line
- feat(config): rename watch_interval to watch_debounce and document it
- feat(watch): wire filesystem and focus triggers to the view lifecycle
- feat(watch): debounced refresh gate with mode and in-flight suppression
- feat(views): add done and quiet options to the three refresh paths
- feat(buffer): keep the cursor on its row identity across renders

### Bug Fixes

- fix(details): say why a git show render takes no comments
- fix(details): measure the split grid, not a floating status window
- fix(details): keep a failed re-place from throwing out of a resize handler
- fix(spinner): stack concurrent operations in one float
- fix(hotbar): one hint item per action, and open file ahead of the scroll keys
- fix(keys): order the pane's curated keys so its core verbs survive truncation
- fix(keys): surface the pane's verbs, guard the live bindings, drop dead lists
- fix(tests): assert the yank writes both registers, not that the OS kept them
- fix(details): tell nameless lanes apart when anchoring comments
- fix(tests): stop the hunk-copy test clobbering the system clipboard
- fix(review): share the row key, guard a NIL message, tighten the docs
- fix(ui): make <Tab> and details navigation consistent across the graph
- fix(cli): route spawn failures and hangs into the err convention

### Other

- refactor(log): show a commit in the details pane instead of a raw diff split
- docs(details): document the pane's placement rule and min_width
- refactor(details): route <Tab> on a file row to the details pane
- docs(demo): record the review workflow, and stage GIF output while recording
- refactor(keys): bind the details pane from the registry, drop both duplicates
- refactor(details): the pane becomes a Buffer with its own view
- refactor(buffer): split window creation from attachment
- docs: document the review keys in the details pane
- chore: wire strap harness (ledger + debug recipe lesson)
- docs: retarget the demo tapes at the 0.22 amend keys
- chore: ignore .serena/
- docs: backfill the 3.0.1 changelog section
- ci: list non-user-facing commits under Other in release notes

## [3.0.1] - 2026-08-08

### Other

- style: format action_spec quit_neovim_on_quit test
- test: assert default keymaps resolve to registered handlers

## [3.0.0] - 2026-08-01

### Features

- feat: add quit_neovim_on_quit config
- feat(cli)!: cut over to the but 0.22 command surface

## [3.0.0] - 2026-08-01

### Features

- feat(cli)!: migrate to the but 0.22 command surface; requires but 0.22.0+
- feat(cli)!: refuse pre-0.22 CLIs instead of adapting the JSON flag
- feat(cli)!: replace rub with explicit amend, squash and uncommit verbs
- feat(cli)!: target commit and move with --branch/--above/--below/--unstack
- feat(cli)!: drop CLI assignments — no assign, unassign or reassign verb
- feat(cli): batch discard into a single call, so one undoable oplog entry
- feat(tui)!: keymap a amend, R amend-all, S squash, w uncommit; r unbound
- feat(details)!: a amends the marked hunks; the pane's r binding is gone
- feat(log): S squashes a commit into the one below it, its parent
- feat(cli): squash with -u, keeping the target's message, so no editor opens

### Bug Fixes

- fix(cli): unapply no longer passes the removed -f flag
- fix(actions): read the commitId that but 0.22 returns from commit --json

## [2.0.0] - 2026-07-22

### Features

- feat(details): show commit meta header for workspace commits too
- feat(details): d shows landed commits via git show; hint submit key
- feat(graph)!: fold timeline into the main view as landed history
- feat(land): L lands selected branches, not just files

### Bug Fixes

- fix(tui): warn instead of silent no-op on discard/describe off-target
- fix(tui): guard push-all footgun; Enter saves in new-branch/snapshot inputs
- fix(branch): Enter saves in rename popup

## [1.0.0] - 2026-07-22

### Features

- feat(ui): open a commit in a diff tool via the commit_diff setting
- feat(ui): jump to code — open files at the hunk line, keeping the TUI open
- feat(ui): fold indicators, commit dot states, and carry-over fixes
- feat(ui): hunk-level mark, discard, copy and rub
- feat(ui): details focus switching and hunk cursor
- feat(ui): details pane window with follow-the-cursor diffs
- feat(ui): details pane diff renderer
- feat(ui): mode keymap final, file-list toggles, per-mode hotbar
- feat(ui): jump mode, command modes, copy, undo confirm and redo
- feat(ui): stack mode, fuzzy picker, goto-branch
- feat(ui): commit and move modes with insert anchors
- feat(ui): rub mode with verb pills and but-rub execution
- feat(ui): mode engine core with rub verb table
- feat(ui): official but-tui keymap; extras move to free keys
- feat(ui): mode-pill hotbar for status view
- feat(ui): official nav keys with selectable-row skipping
- feat(ui): status view renders but-tui graph
- feat(ui): span rendering and homogeneous marks in buffer
- feat(ui): add graph renderer for but-tui style status view

### Bug Fixes

- fix(ui): guard remaining vim.NIL crash sites in graph renderer
- fix(ui): register details_focus handler; test keymap dispatch coverage

## [0.4.0] - 2026-07-11

### Features

- feat(cli): land M-key directly via `but land`

### Bug Fixes

- fix(fmt): satisfy stylua; add `make ci` target

## [0.3.1] - 2026-06-23

### Bug Fixes

- fix(cli): use --format=json for but 0.20.3 compatibility (#25)

## [0.3.0] - 2026-05-11

### Features

- feat: collapse release flow to one manual action (#19)

### Bug Fixes

- fix(ci): remove unresolved conflict markers from release.yml (#21)
- fix(release): drop ref pin, fallback auto-bump, fix trailing-newline parse (#20)

# Changelog

## [0.2.0](https://github.com/abosnjakovic/gitbutler.nvim/compare/v0.1.4...v0.2.0) (2026-05-07)


### Features

* document commit body display in log view ([#17](https://github.com/abosnjakovic/gitbutler.nvim/issues/17)) ([4e7990a](https://github.com/abosnjakovic/gitbutler.nvim/commit/4e7990ac3c8eb02c18b4b1bc98218acf6d4f55e0))

## 0.1.4 — 2026-05-07

- feat: show commit body in log view on expand

## 0.1.3 — 2026-04-24

- feat: pin context hint to bottom of view

## 0.1.2 — 2026-04-24

- feat: context-aware bottom hint line
- fix: after a insert required actin like creating a branch, go back to normal mode
- fix: toggle diff mode with tab, tab now closes diff views

## 0.1.1 — 2026-04-09

- make release target
- release workflow
- seed files
- fix commit to respect file selection
- update readme
- uncommit action bound to U
- bind timeline to t in status buffer
- fix refresh losing expanded file state
- fix spec compliance: file status, per-field highlights
- register ButlerTimeline command
- open, refresh, keymaps
- build_lines with TDD tests
- parse_diff_tree with TDD tests
- parse_git_log with TDD tests
- highlights, config, fixtures for timeline view
- test: add coverage for actions.toggle_select and push
- feat(cli): sync with upstream before pushing
- feat(ui): auto-advance cursor on spacebar selection
- feat: add pull action, notify_start feedback, single-line branch input
- fix: single line branch creation
- feat: multi select files
- Update README with installation instructions
- feat: show recent commits, merge base info, and inline commit details
- docs: add README with installation, usage, and configuration
- feat: test suite and GitHub Actions CI
- feat: commit log and operations log views
- feat: branch management popup
- feat: status view and interactive actions
- feat: UI framework — managed buffer, floats, and highlights
- feat: async CLI wrapper for the but command
- feat: project scaffold with config and plugin entrypoint

All notable changes to this project will be documented in this file.

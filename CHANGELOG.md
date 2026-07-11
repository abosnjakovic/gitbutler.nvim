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

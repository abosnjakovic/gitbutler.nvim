# Multi-Select for GitButler Status Buffer

## Summary

Add spacebar-toggled multi-select to the status buffer, allowing users to select multiple files and commits then apply batch actions. Selections are keyed by stable identifiers (cli_id for files, sha for commits) so they survive re-renders. Selection clears automatically after an action completes, but is preserved across watcher-triggered and manual refreshes.

## Selection State

The `Buffer` class gains:

- `selected = {}` — a set keyed by stable identifier strings
- `toggle_select()` — toggles the line under cursor in/out of the set
- `is_selected(line)` — checks a line's data against the set
- `clear_selection()` — empties the set
- `get_selected_lines()` — returns all `self.lines` whose key is in the selected set, preserving display order

Key extraction logic:

- `file` and `committed_file` lines: `data.cli_id`
- `commit` lines: `data.sha`
- All other line types (blank, section_header, branch, help, info, recent_commit): not selectable. `recent_commit` lines have a sha but are excluded because they represent git log history, not commits on applied branches — `but` commands cannot operate on them.

Pressing space on a non-selectable line is a silent no-op.

## Rendering

Selected lines receive a `●` prefix inserted after indent but before the line text. Selectable lines are never foldable (only branch headers and section headers are foldable), so there is no conflict with the fold indicator. The entire line is highlighted with `GitButlerSelected` (linked to `Visual` by default).

Example rendered output:

```
  ● M  src/main.lua        (selected file, indent=1)
    M  src/other.lua        (unselected file)
  ● abc1234 fix the thing   (selected commit, indent=1)
```

The selection marker is a render-time concern only. The underlying `GitButlerLine` objects are not modified. During `Buffer:render()`, each line is checked via `self:is_selected(line)` and the text and highlight are adjusted accordingly.

## Keybinding

`<Space>` maps to a new `toggle_select` action in `config.defaults.keymaps.status`. Users can remap it via their config like any other binding.

No bulk select/clear keybindings in the first pass. Deselection is manual (spacebar again) or automatic (on action completion only — refreshes preserve selection).

The help popup gains an entry: `<Space>   Select / deselect`.

## Action Integration

Actions that support multi-select follow a shared pattern:

1. Call `buf:get_selected_lines()`, filtered to the relevant line type(s)
2. If empty, fall back to `buf:get_cursor_line()` wrapped in a single-item list
3. Execute the CLI operation for each item
4. After all operations complete, clear selection and refresh once

### Batch behaviour per action

| Action | Line types | CLI calls | Notes |
|---|---|---|---|
| `assign_to_branch` | file, committed_file | One `but stage <cli_id> <branch>` per file, sequential | Picker shown once, applies to all. Note: current code passes `data.path` to `cli.stage()` — multi-select switches to `data.cli_id` which is what `but stage` actually expects (a file/hunk ID from `but status`) |
| `discard` | file | One `but discard <cli_id>` per file, sequential | Single confirmation listing all file paths. Switches from `git checkout --` to `but discard` which accepts the cli_id shown in `but status`. Adds `cli.discard()` convenience method |
| `squash` | commit | One `but squash <sha1> <sha2> ... --json` call | Native batch support: "squashes all commits except the last into the last commit" per CLI docs. `cli.squash()` updated to accept a list of commits |
| `move` | commit | One `but move <sha> <target>` per commit, sequential | Sequential to avoid races |
| `open_file` | file, committed_file | N/A (vim buffers) | Multi-select: opens each file via `vim.cmd('edit')` without closing the status buffer. Single-file (cursor fallback): retains existing behaviour of closing the status buffer |

### Actions that ignore multi-select

commit, push, push_all, amend, absorb, describe, branch_new, undo, toggle_fold, log, oplog, branches, help, close, refresh — these operate on branch context or are global operations, so they behave as today regardless of selection state.

## Cross-context selection

Selection is allowed across different branches and sections. No contextual validation is performed in the UI. Each CLI call receives the data from its own line, and the CLI determines validity. Errors are surfaced via `vim.notify`.

## Highlight Groups

New group added to `highlights.lua`:

- `GitButlerSelected` — linked to `Visual` by default

## Implementation Notes

The `GitButlerLine` type annotation in `buffer.lua` currently lists types as `'branch', 'commit', 'file', 'section_header', 'blank', 'help'` but the actual codebase also produces `committed_file`, `recent_commit`, and `info` line types. The type annotation should be updated as part of this work.

The existing `assign_to_branch` action passes `line.data.path` to `cli.stage()`, but `but stage` expects a file/hunk ID (cli_id). This should be corrected as part of the multi-select implementation for both the single and multi-select paths.

## Files Modified

- `lua/gitbutler/ui/buffer.lua` — selection state, new methods, render changes
- `lua/gitbutler/ui/highlights.lua` — new highlight group
- `lua/gitbutler/config.lua` — new keymap entry
- `lua/gitbutler/actions.lua` — multi-select support in applicable actions, new toggle_select action
- `lua/gitbutler/ui/status.lua` — register toggle_select handler
- `lua/gitbutler/cli.lua` — update squash to accept multiple commits, add discard convenience method

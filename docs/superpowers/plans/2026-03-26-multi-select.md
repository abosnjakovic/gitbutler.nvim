# Multi-Select Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add spacebar-toggled multi-select to the status buffer so users can select files and commits, then apply batch actions.

**Architecture:** Selection state lives in the Buffer object as a set keyed by stable identifiers (cli_id/sha). The render loop checks selection state and prepends a `●` marker with a highlight. Actions check for selections first and iterate over them, falling back to cursor line when nothing is selected.

**Tech Stack:** Lua, Neovim API, `but` CLI

**Spec:** `docs/superpowers/specs/2026-03-25-multi-select-design.md`

---

### Task 1: Selection state in Buffer

Add the core selection data model and methods to `Buffer`.

**Files:**
- Modify: `lua/gitbutler/ui/buffer.lua`
- Test: `tests/run.lua`

- [ ] **Step 1: Write failing tests for selection methods**

Add to `tests/run.lua` before the summary section:

```lua
-- ── Selection tests ─────────────────────────────────────

print('\n=== Selection tests ===')

test('select_key returns cli_id for file lines', function()
  local buf = mock_buffer()
  local line = { type = 'file', data = { cli_id = 'up', path = 'foo.lua' } }
  assert_eq('up', buf:select_key(line))
end)

test('select_key returns sha for commit lines', function()
  local buf = mock_buffer()
  local line = { type = 'commit', data = { sha = 'abc123' } }
  assert_eq('abc123', buf:select_key(line))
end)

test('select_key returns cli_id for committed_file lines', function()
  local buf = mock_buffer()
  local line = { type = 'committed_file', data = { cli_id = 'c4:xw' } }
  assert_eq('c4:xw', buf:select_key(line))
end)

test('select_key returns nil for non-selectable lines', function()
  local buf = mock_buffer()
  assert_eq(nil, buf:select_key({ type = 'blank', data = nil }))
  assert_eq(nil, buf:select_key({ type = 'section_header', data = {} }))
  assert_eq(nil, buf:select_key({ type = 'branch', data = { name = 'main' } }))
  assert_eq(nil, buf:select_key({ type = 'help', data = nil }))
  assert_eq(nil, buf:select_key({ type = 'recent_commit', data = { sha = 'abc' } }))
end)

test('toggle_select adds and removes from selection', function()
  local buf = mock_buffer()
  buf.lines = {
    { type = 'file', data = { cli_id = 'up', path = 'foo.lua' }, text = 'M  foo.lua' },
    { type = 'file', data = { cli_id = 'qu', path = 'bar.lua' }, text = 'M  bar.lua' },
  }
  -- Mock cursor at line 1
  buf.win = true
  buf._cursor_row = 1

  buf:toggle_select()
  assert_truthy(buf:is_selected(buf.lines[1]))
  assert_falsy(buf:is_selected(buf.lines[2]))

  -- Toggle again to deselect
  buf:toggle_select()
  assert_falsy(buf:is_selected(buf.lines[1]))
end)

test('get_selected_lines returns selected lines in order', function()
  local buf = mock_buffer()
  buf.lines = {
    { type = 'file', data = { cli_id = 'a1' }, text = 'first' },
    { type = 'file', data = { cli_id = 'b2' }, text = 'second' },
    { type = 'file', data = { cli_id = 'c3' }, text = 'third' },
  }
  buf.selected = { a1 = true, c3 = true }

  local selected = buf:get_selected_lines()
  assert_eq(2, #selected)
  assert_eq('a1', selected[1].data.cli_id)
  assert_eq('c3', selected[2].data.cli_id)
end)

test('get_selected_lines can filter by type', function()
  local buf = mock_buffer()
  buf.lines = {
    { type = 'file', data = { cli_id = 'a1' }, text = 'file' },
    { type = 'commit', data = { sha = 'abc' }, text = 'commit' },
  }
  buf.selected = { a1 = true, abc = true }

  local files = buf:get_selected_lines({ 'file' })
  assert_eq(1, #files)
  assert_eq('file', files[1].type)

  local commits = buf:get_selected_lines({ 'commit' })
  assert_eq(1, #commits)
  assert_eq('commit', commits[1].type)
end)

test('clear_selection empties the set', function()
  local buf = mock_buffer()
  buf.selected = { a1 = true, b2 = true }
  buf:clear_selection()
  assert_eq(0, vim.tbl_count(buf.selected))
end)

test('toggle_select on non-selectable line is a no-op', function()
  local buf = mock_buffer()
  buf.lines = {
    { type = 'blank', data = nil, text = '' },
  }
  buf.win = true
  buf._cursor_row = 1
  buf:toggle_select()
  assert_eq(0, vim.tbl_count(buf.selected))
end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test`
Expected: FAIL — `select_key`, `toggle_select`, `is_selected`, `get_selected_lines`, `clear_selection` methods do not exist

- [ ] **Step 3: Implement selection methods in Buffer**

In `lua/gitbutler/ui/buffer.lua`, add `selected = {}` in `Buffer.new()`, then add these methods:

```lua
---Extract a stable selection key from a line, or nil if not selectable.
---@param line GitButlerLine
---@return string?
function Buffer:select_key(line)
  if not line or not line.data then return nil end
  if line.type == 'file' or line.type == 'committed_file' then
    return line.data.cli_id
  elseif line.type == 'commit' then
    return line.data.sha
  end
  return nil
end

---Toggle selection for the line under cursor.
function Buffer:toggle_select()
  local row = self._cursor_row
  if not row then
    if not self.win or not vim.api.nvim_win_is_valid(self.win) then return end
    row = vim.api.nvim_win_get_cursor(self.win)[1]
  end
  local line = self.lines[row]
  local key = self:select_key(line)
  if not key then return end
  if self.selected[key] then
    self.selected[key] = nil
  else
    self.selected[key] = true
  end
end

---Check if a line is currently selected.
---@param line GitButlerLine
---@return boolean
function Buffer:is_selected(line)
  local key = self:select_key(line)
  return key ~= nil and self.selected[key] == true
end

---Return all selected lines from self.lines, in display order.
---@param types? string[] Optional filter: only return lines of these types
---@return GitButlerLine[]
function Buffer:get_selected_lines(types)
  local result = {}
  for _, line in ipairs(self.lines) do
    if self:is_selected(line) then
      if not types then
        table.insert(result, line)
      else
        for _, t in ipairs(types) do
          if line.type == t then
            table.insert(result, line)
            break
          end
        end
      end
    end
  end
  return result
end

---Clear all selections.
function Buffer:clear_selection()
  self.selected = {}
end
```

Also update `Buffer.new()` to initialise `self.selected = {}`.

Update the `GitButlerLine` type annotation to include the missing types:

```lua
---@field type string Line type: 'branch', 'commit', 'file', 'committed_file', 'section_header', 'blank', 'help', 'info', 'recent_commit'
```

- [ ] **Step 4: Update mock_buffer in tests/run.lua**

The `mock_buffer()` in `tests/run.lua` needs a `_cursor_row` field for testing `toggle_select` without a real window. Add to the mock:

```lua
local function mock_buffer()
  local buf = buffer_mod.Buffer.new()
  buf.is_folded = function(_, _) return false end
  buf._cursor_row = nil -- set per test to simulate cursor position
  return buf
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `make test`
Expected: All selection tests PASS

- [ ] **Step 6: Commit**

```bash
git add lua/gitbutler/ui/buffer.lua tests/run.lua
git commit -m "feat: add selection state and methods to Buffer"
```

---

### Task 2: Selection rendering

Modify `Buffer:render()` to show `●` prefix and `GitButlerSelected` highlight on selected lines.

**Files:**
- Modify: `lua/gitbutler/ui/buffer.lua`
- Modify: `lua/gitbutler/ui/highlights.lua`
- Test: `tests/run.lua`

- [ ] **Step 1: Write failing tests for selection rendering**

Add to `tests/run.lua` in the selection tests section:

```lua
test('render adds selection marker to selected lines', function()
  local buf = buffer_mod.Buffer.new()
  buf.buf = vim.api.nvim_create_buf(false, true)
  buf.ns = vim.api.nvim_create_namespace('gitbutler-test-render')
  buf.selected = { up = true }

  buf:render({
    { type = 'file', data = { cli_id = 'up' }, text = 'M  foo.lua', indent = 1 },
    { type = 'file', data = { cli_id = 'qu' }, text = 'M  bar.lua', indent = 1 },
  })

  local rendered = vim.api.nvim_buf_get_lines(buf.buf, 0, -1, false)
  assert_truthy(rendered[1]:find('●'), 'selected line has marker')
  assert_falsy(rendered[2]:find('●'), 'unselected line has no marker')

  vim.api.nvim_buf_delete(buf.buf, { force = true })
end)

test('render applies GitButlerSelected highlight to selected lines', function()
  local buf = buffer_mod.Buffer.new()
  buf.buf = vim.api.nvim_create_buf(false, true)
  buf.ns = vim.api.nvim_create_namespace('gitbutler-test-hl')
  buf.selected = { up = true }

  -- Ensure highlight group exists
  require('gitbutler.ui.highlights').setup()

  buf:render({
    { type = 'file', data = { cli_id = 'up' }, hl = 'GitButlerFileMod', text = 'M  foo.lua', indent = 1 },
  })

  local extmarks = vim.api.nvim_buf_get_extmarks(buf.buf, buf.ns, 0, -1, { details = true })
  local found_selected_hl = false
  for _, mark in ipairs(extmarks) do
    if mark[4] and mark[4].hl_group == 'GitButlerSelected' then
      found_selected_hl = true
      break
    end
  end
  assert_truthy(found_selected_hl, 'selected line has GitButlerSelected highlight')

  vim.api.nvim_buf_delete(buf.buf, { force = true })
end)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test`
Expected: FAIL — no `●` marker in rendered text, no `GitButlerSelected` highlight group

- [ ] **Step 3: Add GitButlerSelected highlight group**

In `lua/gitbutler/ui/highlights.lua`, add to the `groups` table:

```lua
GitButlerSelected = { link = 'Visual' },
```

- [ ] **Step 4: Update Buffer:render() to show selection markers**

In `lua/gitbutler/ui/buffer.lua`, modify the render loop that builds `text_lines`:

```lua
for _, line in ipairs(lines) do
  local indent = string.rep('  ', line.indent or 0)
  local prefix = ''
  if line.foldable then
    prefix = line.folded and '▸ ' or '▾ '
  end
  local select_marker = ''
  if self:is_selected(line) then
    select_marker = '● '
  end
  table.insert(text_lines, indent .. select_marker .. prefix .. line.text)
end
```

And update the highlight application loop:

```lua
for i, line in ipairs(lines) do
  if self:is_selected(line) then
    vim.api.nvim_buf_add_highlight(self.buf, self.ns, 'GitButlerSelected', i - 1, 0, -1)
  elseif line.hl then
    vim.api.nvim_buf_add_highlight(self.buf, self.ns, line.hl, i - 1, 0, -1)
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `make test`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add lua/gitbutler/ui/buffer.lua lua/gitbutler/ui/highlights.lua tests/run.lua
git commit -m "feat: render selection markers and highlights"
```

---

### Task 3: Keybinding and toggle_select action

Wire up `<Space>` to toggle selection in the status buffer.

**Files:**
- Modify: `lua/gitbutler/config.lua`
- Modify: `lua/gitbutler/actions.lua`
- Modify: `lua/gitbutler/ui/status.lua`

- [ ] **Step 1: Add keymap to config defaults**

In `lua/gitbutler/config.lua`, add to `keymaps.status`:

```lua
['<Space>'] = 'toggle_select',
```

- [ ] **Step 2: Add toggle_select action**

In `lua/gitbutler/actions.lua`, add:

```lua
---Toggle selection on the line under cursor.
function M.toggle_select(buf)
  buf:toggle_select()
  -- Re-render to show updated markers without a full refresh (preserves selection)
  if buf.lines and #buf.lines > 0 then
    buf:render(buf.lines)
  end
end
```

- [ ] **Step 3: Register handler in status.lua**

In `lua/gitbutler/ui/status.lua`, in the `M.open()` function, add alongside the other `buf:on()` calls:

```lua
buf:on('toggle_select', actions.toggle_select)
```

- [ ] **Step 4: Update help text**

In `lua/gitbutler/actions.lua`, in the `M.help()` function, add to `help_lines` before the `'?        This help'` entry:

```lua
'<Space>  Select / deselect',
```

- [ ] **Step 5: Run tests to verify nothing broke**

Run: `make test`
Expected: All existing and new tests PASS

- [ ] **Step 6: Commit**

```bash
git add lua/gitbutler/config.lua lua/gitbutler/actions.lua lua/gitbutler/ui/status.lua
git commit -m "feat: wire up space bar for multi-select toggle"
```

---

### Task 4: Multi-select assign_to_branch

Update `assign_to_branch` to operate on selected files.

**Files:**
- Modify: `lua/gitbutler/actions.lua`

- [ ] **Step 1: Write failing test**

Add to `tests/run.lua`:

```lua
-- ── Action multi-select tests ───────────────────────────

print('\n=== Action multi-select tests ===')

test('get_selected_lines falls back to cursor line when no selection', function()
  local buf = mock_buffer()
  buf.lines = {
    { type = 'file', data = { cli_id = 'a1', path = 'foo.lua' }, text = 'M  foo.lua' },
    { type = 'file', data = { cli_id = 'b2', path = 'bar.lua' }, text = 'M  bar.lua' },
  }
  buf._cursor_row = 2

  local selected = buf:get_selected_lines()
  assert_eq(0, #selected)

  -- The action pattern: fall back to cursor line
  local targets = #selected > 0 and selected or { buf.lines[buf._cursor_row] }
  assert_eq(1, #targets)
  assert_eq('b2', targets[1].data.cli_id)
end)
```

- [ ] **Step 2: Run test to verify it passes**

Run: `make test`
Expected: PASS (this tests the fallback pattern actions will use)

- [ ] **Step 3: Update assign_to_branch for multi-select**

Replace `M.assign_to_branch` in `lua/gitbutler/actions.lua`:

```lua
---Assign file(s) to a branch via inline picker.
function M.assign_to_branch(buf)
  local selected = buf:get_selected_lines({ 'file', 'committed_file' })
  local targets
  if #selected > 0 then
    targets = selected
  else
    local line = buf:get_cursor_line()
    if not line or (line.type ~= 'file' and line.type ~= 'committed_file') or not line.data then return end
    targets = { line }
  end

  cli.branch_list(function(err, data)
    if err then
      vim.notify('gitbutler: ' .. err, vim.log.levels.ERROR)
      return
    end

    local names = extract_branch_names(data)
    if #names == 0 then
      vim.notify('gitbutler: no branches available', vim.log.levels.WARN)
      return
    end

    float.picker({
      title = 'Assign to branch',
      items = names,
      on_select = function(branch_name)
        local i = 0
        local function stage_next()
          i = i + 1
          if i > #targets then
            buf:clear_selection()
            vim.notify('gitbutler: staged ' .. #targets .. ' file(s) → ' .. branch_name, vim.log.levels.INFO)
            refresh()
            return
          end
          local id = targets[i].data.cli_id or targets[i].data.path
          cli.stage(id, branch_name, function(stage_err, _)
            if stage_err then
              buf:clear_selection()
              vim.notify('gitbutler stage: ' .. stage_err, vim.log.levels.ERROR)
              refresh()
              return
            end
            stage_next()
          end)
        end
        stage_next()
      end,
    })
  end)
end
```

- [ ] **Step 4: Run tests**

Run: `make test`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add lua/gitbutler/actions.lua tests/run.lua
git commit -m "feat: multi-select support for assign_to_branch"
```

---

### Task 5: Multi-select discard

Switch discard from `git checkout` to `but discard` and support multiple files.

**Files:**
- Modify: `lua/gitbutler/cli.lua`
- Modify: `lua/gitbutler/actions.lua`

- [ ] **Step 1: Add cli.discard() convenience method**

In `lua/gitbutler/cli.lua`, add:

```lua
---Convenience: but discard
function M.discard(id, callback)
  M.run({ 'discard', id, '--json' }, callback)
end
```

- [ ] **Step 2: Update discard action for multi-select**

Replace `M.discard` in `lua/gitbutler/actions.lua`:

```lua
---Discard changes for file(s) under cursor or selected.
function M.discard(buf)
  local selected = buf:get_selected_lines({ 'file' })
  local targets
  if #selected > 0 then
    targets = selected
  else
    local line = buf:get_cursor_line()
    if not line or line.type ~= 'file' or not line.data then return end
    targets = { line }
  end

  local paths = {}
  for _, t in ipairs(targets) do
    table.insert(paths, t.data.path or t.data.cli_id)
  end
  local prompt = 'Discard changes to ' .. table.concat(paths, ', ') .. '?'

  vim.ui.select({ 'Yes', 'No' }, { prompt = prompt }, function(choice)
    if choice ~= 'Yes' then return end
    local i = 0
    local function discard_next()
      i = i + 1
      if i > #targets then
        buf:clear_selection()
        vim.notify('gitbutler: discarded ' .. #targets .. ' file(s)', vim.log.levels.INFO)
        refresh()
        return
      end
      cli.discard(targets[i].data.cli_id, function(err, _)
        if err then
          buf:clear_selection()
          vim.notify('gitbutler discard: ' .. err, vim.log.levels.ERROR)
          refresh()
          return
        end
        discard_next()
      end)
    end
    discard_next()
  end)
end
```

- [ ] **Step 3: Run tests**

Run: `make test`
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add lua/gitbutler/cli.lua lua/gitbutler/actions.lua
git commit -m "feat: multi-select discard using but discard CLI"
```

---

### Task 6: Multi-select squash

Update squash to pass multiple commit SHAs in a single CLI call.

**Files:**
- Modify: `lua/gitbutler/cli.lua`
- Modify: `lua/gitbutler/actions.lua`

- [ ] **Step 1: Update cli.squash() to accept multiple commits**

Replace `M.squash` in `lua/gitbutler/cli.lua`:

```lua
---Convenience: but squash (accepts single commit string or list of commit strings)
function M.squash(commits, callback)
  local args = { 'squash', '--json' }
  if type(commits) == 'table' then
    for _, c in ipairs(commits) do
      table.insert(args, c)
    end
  elseif commits then
    table.insert(args, commits)
  end
  M.run(args, callback)
end
```

- [ ] **Step 2: Update squash action for multi-select**

Replace `M.squash` in `lua/gitbutler/actions.lua`:

```lua
---Squash: combine selected commits or commit under cursor into parent.
function M.squash(buf)
  local selected = buf:get_selected_lines({ 'commit' })
  if #selected > 0 then
    local shas = {}
    for _, line in ipairs(selected) do
      table.insert(shas, line.data.sha)
    end
    cli.squash(shas, function(err, result)
      buf:clear_selection()
      notify_result('squash ' .. #shas .. ' commits', err, result)
    end)
    return
  end

  -- Single commit fallback
  local line = buf:get_cursor_line()
  if not line or line.type ~= 'commit' or not line.data then return end
  local sha = line.data.sha
  if not sha then return end
  cli.squash(sha, function(err, result)
    notify_result('squash', err, result)
  end)
end
```

- [ ] **Step 3: Run tests**

Run: `make test`
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add lua/gitbutler/cli.lua lua/gitbutler/actions.lua
git commit -m "feat: multi-select squash with batch CLI call"
```

---

### Task 7: Multi-select move

Update move to operate on multiple selected commits sequentially.

**Files:**
- Modify: `lua/gitbutler/actions.lua`

- [ ] **Step 1: Update move action for multi-select**

Replace `M.move` in `lua/gitbutler/actions.lua`:

```lua
---Move commit(s) to a different branch.
function M.move(buf)
  local selected = buf:get_selected_lines({ 'commit' })
  local targets
  if #selected > 0 then
    targets = selected
  else
    local line = buf:get_cursor_line()
    if not line or line.type ~= 'commit' or not line.data then return end
    targets = { line }
  end

  cli.branch_list(function(err, data)
    if err then
      vim.notify('gitbutler: ' .. err, vim.log.levels.ERROR)
      return
    end

    local names = extract_branch_names(data)

    float.picker({
      title = 'Move commit(s) to',
      items = names,
      on_select = function(target_branch)
        local i = 0
        local function move_next()
          i = i + 1
          if i > #targets then
            buf:clear_selection()
            vim.notify('gitbutler: moved ' .. #targets .. ' commit(s) → ' .. target_branch, vim.log.levels.INFO)
            refresh()
            return
          end
          local sha = targets[i].data.sha
          cli.move(sha, target_branch, function(move_err, _)
            if move_err then
              buf:clear_selection()
              vim.notify('gitbutler move: ' .. move_err, vim.log.levels.ERROR)
              refresh()
              return
            end
            move_next()
          end)
        end
        move_next()
      end,
    })
  end)
end
```

- [ ] **Step 2: Run tests**

Run: `make test`
Expected: All tests PASS

- [ ] **Step 3: Commit**

```bash
git add lua/gitbutler/actions.lua
git commit -m "feat: multi-select move commits sequentially"
```

---

### Task 8: Multi-select open_file

Open multiple selected files without destroying the status buffer.

**Files:**
- Modify: `lua/gitbutler/actions.lua`

- [ ] **Step 1: Update open_file for multi-select**

Replace `M.open_file` in `lua/gitbutler/actions.lua`. The key change: when multiple files are selected, open them via `vim.cmd('edit')` without closing the status buffer. Single-file (cursor fallback) retains the existing close-on-open behaviour:

```lua
---Open the file(s) under cursor or selected, or show commit details for recent commits.
function M.open_file(buf)
  -- Multi-select: open each selected file without closing status buffer
  local selected = buf:get_selected_lines({ 'file', 'committed_file' })
  if #selected > 0 then
    buf:clear_selection()
    for _, line in ipairs(selected) do
      if line.data and line.data.path then
        vim.cmd('edit ' .. vim.fn.fnameescape(line.data.path))
      end
    end
    return
  end

  -- Single file / recent commit: existing behaviour
  local line = buf:get_cursor_line()
  if not line or not line.data then return end

  if line.type == 'recent_commit' then
    local sha = line.data.sha
    if not sha then return end

    local result = vim.system(
      { 'git', 'show', '--patch', '--stat', '--format=%H%n%an <%ae>%n%aD%n%n%B', sha },
      { text = true }
    ):wait()

    if result.code ~= 0 or not result.stdout then
      vim.notify('gitbutler: failed to show commit', vim.log.levels.ERROR)
      return
    end

    local show_lines = vim.split(result.stdout, '\n')
    vim.cmd('belowright split')
    local diff_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(0, diff_buf)
    vim.api.nvim_buf_set_lines(diff_buf, 0, -1, false, show_lines)
    vim.bo[diff_buf].buftype = 'nofile'
    vim.bo[diff_buf].bufhidden = 'wipe'
    vim.bo[diff_buf].filetype = 'diff'
    vim.keymap.set('n', 'q', '<cmd>close<CR>', { buffer = diff_buf })
    return
  end

  if not line.data.path then return end
  local path = line.data.path

  buf:close()
  local status = require('gitbutler.ui.status')
  status.instance = nil
  vim.cmd('edit ' .. vim.fn.fnameescape(path))
end
```

- [ ] **Step 2: Run tests**

Run: `make test`
Expected: All tests PASS

- [ ] **Step 3: Commit**

```bash
git add lua/gitbutler/actions.lua
git commit -m "feat: multi-select open files without closing status buffer"
```

---

### Task 9: Selection preserved across refresh

Ensure watcher-triggered and manual refreshes don't clear the selection.

**Files:**
- Modify: `lua/gitbutler/ui/buffer.lua` (no change needed — selection already persists in `self.selected` across `render()` calls)
- Test: `tests/run.lua`

- [ ] **Step 1: Write test to verify selection survives re-render**

Add to `tests/run.lua`:

```lua
test('selection survives re-render', function()
  local buf = buffer_mod.Buffer.new()
  buf.buf = vim.api.nvim_create_buf(false, true)
  buf.ns = vim.api.nvim_create_namespace('gitbutler-test-persist')
  buf.selected = { up = true }

  local lines = {
    { type = 'file', data = { cli_id = 'up' }, text = 'M  foo.lua', indent = 1 },
    { type = 'file', data = { cli_id = 'qu' }, text = 'M  bar.lua', indent = 1 },
  }

  -- First render
  buf:render(lines)
  assert_truthy(buf:is_selected(lines[1]))

  -- Second render (simulates refresh)
  buf:render(lines)
  assert_truthy(buf:is_selected(lines[1]), 'selection preserved after re-render')

  local rendered = vim.api.nvim_buf_get_lines(buf.buf, 0, -1, false)
  assert_truthy(rendered[1]:find('●'), 'marker still shown after re-render')

  vim.api.nvim_buf_delete(buf.buf, { force = true })
end)
```

- [ ] **Step 2: Run test to verify it passes**

Run: `make test`
Expected: PASS — `selected` is not cleared by `render()`

- [ ] **Step 3: Commit**

```bash
git add tests/run.lua
git commit -m "test: verify selection persists across re-renders"
```

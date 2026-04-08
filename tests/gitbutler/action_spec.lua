local h = require('tests.gitbutler.helpers')
local cli = require('gitbutler.cli')
local actions = require('gitbutler.actions')
local test, assert_eq, assert_truthy = h.test, h.assert_eq, h.assert_truthy

print('\n=== Action tests ===')

test('actions.toggle_select moves cursor down if successful', function()
  local buf = h.mock_buffer()
  buf.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf.buf, 0, -1, false, { "line 1", "line 2", "line 3" })

  buf.win = vim.api.nvim_open_win(buf.buf, true, {
    relative = 'editor', width = 10, height = 10, row = 0, col = 0
  })

  vim.api.nvim_win_set_cursor(buf.win, { 1, 0 })

  buf.toggle_select = function() return true end
  buf.render = function() end
  buf.lines = { "dummy" }

  actions.toggle_select(buf)

  local cursor = vim.api.nvim_win_get_cursor(buf.win)
  assert_eq(2, cursor[1], 'cursor should move to line 2')

  vim.api.nvim_win_close(buf.win, true)
  vim.api.nvim_buf_delete(buf.buf, { force = true })
end)

test('actions.push does a pull first', function()
  local pull_called = false
  local push_called = false

  local original_pull = cli.pull
  local original_push = cli.push

  cli.pull = function(cb)
    pull_called = true
    cb(nil, "pulled")
  end

  cli.push = function(branch_name, cb)
    assert_truthy(pull_called, 'pull must be called before push')
    push_called = true
    assert_eq("test-branch", branch_name)
    cb(nil, "pushed")
  end

  local buf = h.mock_buffer()
  buf.get_cursor_branch = function() return { name = "test-branch" } end

  local original_notify = vim.notify
  vim.notify = function() end

  actions.push(buf)

  assert_truthy(pull_called)
  assert_truthy(push_called)

  cli.pull = original_pull
  cli.push = original_push
  vim.notify = original_notify
end)

test('actions.push_all does a pull first', function()
  local pull_called = false
  local push_called = false

  local original_pull = cli.pull
  local original_push = cli.push

  cli.pull = function(cb)
    pull_called = true
    cb(nil, "pulled")
  end

  cli.push = function(branch_name, cb)
    assert_truthy(pull_called, 'pull must be called before push_all')
    push_called = true
    assert_eq(nil, branch_name)
    cb(nil, "pushed")
  end

  local buf = h.mock_buffer()

  local original_notify = vim.notify
  vim.notify = function() end

  actions.push_all(buf)

  assert_truthy(pull_called)
  assert_truthy(push_called)

  cli.pull = original_pull
  cli.push = original_push
  vim.notify = original_notify
end)

-- ── Select files > create branch > commit ───────────────

test('commit with selected files passes only those file IDs via -p', function()
  local committed_branch = nil
  local committed_message = nil
  local committed_file_ids = nil

  local original_commit = cli.commit
  local original_notify = vim.notify
  vim.notify = function() end

  -- Mock commit: records args including file_ids
  cli.commit = function(branch, message, cb, file_ids)
    committed_branch = branch
    committed_message = message
    committed_file_ids = file_ids
    cb(nil, 'ok')
  end

  -- Mock float.input to immediately call on_submit
  local float = require('gitbutler.ui.float')
  local original_input = float.input
  float.input = function(opts)
    opts.on_submit('add selected files')
  end

  -- Set up buffer with 3 unallocated files, select only 2
  local buf = h.mock_buffer()
  buf.lines = {
    { type = 'branch', data = { name = 'new-feature' }, text = '  new-feature' },
    { type = 'file', data = { cli_id = 'f1', path = 'src/a.lua', unassigned = true }, text = 'M  src/a.lua' },
    { type = 'file', data = { cli_id = 'f2', path = 'src/b.lua', unassigned = true }, text = 'M  src/b.lua' },
    { type = 'file', data = { cli_id = 'f3', path = 'src/c.lua', unassigned = true }, text = 'A  src/c.lua' },
  }
  buf.selected = { f1 = true, f3 = true }
  buf._cursor_row = 1
  buf.get_cursor_branch = function() return { name = 'new-feature' } end
  buf.clear_selection = function(self) self.selected = {} end

  actions.commit(buf)

  assert_eq('new-feature', committed_branch)
  assert_eq('add selected files', committed_message)
  assert_truthy(committed_file_ids, 'file_ids should be passed')
  assert_eq(2, #committed_file_ids, 'only 2 of 3 files')
  assert_eq('f1', committed_file_ids[1])
  assert_eq('f3', committed_file_ids[2])

  -- Restore
  cli.commit = original_commit
  float.input = original_input
  vim.notify = original_notify
end)

test('commit without selection commits all (no file_ids)', function()
  local committed_file_ids = 'sentinel'

  local original_commit = cli.commit
  local original_notify = vim.notify
  vim.notify = function() end

  cli.commit = function(_branch, _message, cb, file_ids)
    committed_file_ids = file_ids
    cb(nil, 'ok')
  end

  local float = require('gitbutler.ui.float')
  local original_input = float.input
  float.input = function(opts)
    opts.on_submit('commit all')
  end

  local buf = h.mock_buffer()
  buf.lines = {
    { type = 'branch', data = { name = 'main' }, text = '  main' },
    { type = 'file', data = { cli_id = 'f1', path = 'a.lua' }, text = 'M  a.lua' },
  }
  buf.selected = {}
  buf._cursor_row = 1
  buf.get_cursor_branch = function() return { name = 'main' } end
  buf.clear_selection = function(self) self.selected = {} end

  actions.commit(buf)

  assert_eq(nil, committed_file_ids, 'no file_ids means commit all')

  cli.commit = original_commit
  float.input = original_input
  vim.notify = original_notify
end)

test('assign_to_branch stages only selected files', function()
  local staged_files = {}

  local original_stage = cli.stage
  local original_branch_list = cli.branch_list
  local original_notify = vim.notify
  vim.notify = function() end

  -- Mock stage
  cli.stage = function(file_id, branch, cb)
    table.insert(staged_files, { file_id = file_id, branch = branch })
    cb(nil, 'ok')
  end

  -- We can't easily test assign_to_branch end-to-end because it opens a picker,
  -- but we can verify the selection logic that feeds into it.
  local buf = h.mock_buffer()
  buf.lines = {
    { type = 'file', data = { cli_id = 'f1', path = 'a.lua', unassigned = true }, text = 'M  a.lua' },
    { type = 'file', data = { cli_id = 'f2', path = 'b.lua', unassigned = true }, text = 'M  b.lua' },
    { type = 'file', data = { cli_id = 'f3', path = 'c.lua', unassigned = true }, text = 'A  c.lua' },
  }
  buf.selected = { f1 = true, f3 = true }

  local selected = buf:get_selected_lines({ 'file' })
  assert_eq(2, #selected, 'only 2 of 3 files selected')
  assert_eq('f1', selected[1].data.cli_id)
  assert_eq('f3', selected[2].data.cli_id)

  -- Simulate what assign_to_branch does after picker selection
  for _, target in ipairs(selected) do
    local id = target.data.cli_id or target.data.path
    cli.stage(id, 'target-branch', function() end)
  end

  assert_eq(2, #staged_files, 'only selected files are staged')
  assert_eq('f1', staged_files[1].file_id)
  assert_eq('f3', staged_files[2].file_id)

  cli.stage = original_stage
  cli.branch_list = original_branch_list
  vim.notify = original_notify
end)

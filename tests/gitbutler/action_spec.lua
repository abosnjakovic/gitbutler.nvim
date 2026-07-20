local actions = require('gitbutler.actions')
local cli = require('gitbutler.cli')
local h = require('tests.gitbutler.helpers')
local test, assert_eq, assert_truthy = h.test, h.assert_eq, h.assert_truthy

print('\n=== Action tests ===')

test('actions.toggle_select moves cursor down if successful', function()
  local buf = h.mock_buffer()
  buf.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf.buf, 0, -1, false, { 'line 1', 'line 2', 'line 3' })

  buf.win = vim.api.nvim_open_win(buf.buf, true, {
    relative = 'editor',
    width = 10,
    height = 10,
    row = 0,
    col = 0,
  })

  vim.api.nvim_win_set_cursor(buf.win, { 1, 0 })

  buf.toggle_select = function()
    return true
  end
  buf.render = function() end
  buf.lines = {
    { selectable = true, type = 'file' },
    { selectable = true, type = 'file' },
    { selectable = true, type = 'file' },
  }

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
    cb(nil, 'pulled')
  end

  cli.push = function(branch_name, cb)
    assert_truthy(pull_called, 'pull must be called before push')
    push_called = true
    assert_eq('test-branch', branch_name)
    cb(nil, 'pushed')
  end

  local buf = h.mock_buffer()
  buf.get_cursor_branch = function()
    return { name = 'test-branch' }
  end

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
    cb(nil, 'pulled')
  end

  cli.push = function(branch_name, cb)
    assert_truthy(pull_called, 'pull must be called before push_all')
    push_called = true
    assert_eq(nil, branch_name)
    cb(nil, 'pushed')
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

-- ── Empty commit insertion (`n`) ───────────────

test('insert_empty_commit anchors after the cursor commit or branch', function()
  local captured
  local original_commit_empty = cli.commit_empty
  local original_notify = vim.notify
  vim.notify = function() end
  cli.commit_empty = function(anchor, cb)
    captured = anchor
    cb(nil, 'ok')
  end

  local buf = h.mock_buffer()
  buf.lines = {
    { type = 'commit', selectable = true, data = { cli_id = 'cd', branch_name = 'feat' } },
    { type = 'branch', selectable = true, data = { cli_id = 'bb', name = 'feat' } },
    { type = 'file', selectable = true, data = { cli_id = 'f1', path = 'a.lua' } },
  }
  local cursor_row = 1
  buf.get_cursor_line = function(self)
    return self.lines[cursor_row]
  end

  actions.insert_empty_commit(buf)
  assert_eq('cd', captured.after, 'commit row anchors after its cli id')

  cursor_row = 2
  actions.insert_empty_commit(buf)
  assert_eq('bb', captured.after, 'branch row anchors after the branch cli id')

  captured = nil
  cursor_row = 3
  actions.insert_empty_commit(buf)
  assert_eq(nil, captured, 'file rows are rejected')

  cli.commit_empty = original_commit_empty
  vim.notify = original_notify
end)

test('rub_start captures only the marked files as source (assignment via rub)', function()
  -- Assignment is now done by rubbing files onto a branch; the invariant the
  -- old assign_to_branch test protected — only the marked files get operated
  -- on — must hold for the rub source capture.
  local modes = require('gitbutler.ui.modes')
  local captured
  local original_enter_rub = modes.enter_rub
  local original_notify = vim.notify
  modes.enter_rub = function(_, source)
    captured = source
  end
  vim.notify = function() end

  local buf = h.mock_buffer()
  buf.lines = {
    { type = 'file', data = { cli_id = 'f1', path = 'a.lua', unassigned = true }, text = 'M  a.lua' },
    { type = 'file', data = { cli_id = 'f2', path = 'b.lua', unassigned = true }, text = 'M  b.lua' },
    { type = 'file', data = { cli_id = 'f3', path = 'c.lua', unassigned = true }, text = 'A  c.lua' },
  }
  buf.selected = { f1 = true, f3 = true }

  actions.rub_start(buf)

  assert_eq('file', captured.kind)
  assert_eq(2, #captured.ids, 'only the 2 marked files become sources')
  assert_eq('f1', captured.ids[1])
  assert_eq('f3', captured.ids[2])
  assert_eq(1, captured.rows[1])
  assert_eq(3, captured.rows[2])

  modes.enter_rub = original_enter_rub
  vim.notify = original_notify
end)

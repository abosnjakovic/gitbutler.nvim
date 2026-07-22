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

-- `p` with the cursor off any branch (e.g. the uncommitted area) must NOT fall
-- through to `but push` with no branch — that would push every branch. It
-- refuses; `P` (push_all) is the deliberate all-branches action.
test('actions.push refuses when there is no branch under the cursor', function()
  local push_called = false
  local original_pull, original_push = cli.pull, cli.push
  cli.pull = function(cb)
    cb(nil, 'pulled')
  end
  cli.push = function(_, cb)
    push_called = true
    cb(nil, 'pushed')
  end

  local buf = h.mock_buffer()
  buf.get_cursor_branch = function()
    return nil
  end
  local original_notify = vim.notify
  vim.notify = function() end

  actions.push(buf)

  assert_truthy(not push_called, 'push must not run without a branch under the cursor')

  cli.pull, cli.push, vim.notify = original_pull, original_push, original_notify
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

-- ── Undo / redo confirm gating ───────────────

test('actions.undo does not call cli.undo when the user declines the confirm', function()
  local called = false
  local original_undo, original_select, original_notify = cli.undo, vim.ui.select, vim.notify
  cli.undo = function()
    called = true
  end
  vim.ui.select = function(_, opts, cb)
    assert_eq('Undo last operation?', opts.prompt)
    cb('No')
  end
  vim.notify = function() end

  actions.undo(h.mock_buffer())
  assert_eq(false, called, 'declining the confirm must not run cli.undo')

  cli.undo, vim.ui.select, vim.notify = original_undo, original_select, original_notify
end)

test('actions.undo calls cli.undo when the user confirms', function()
  local called = false
  local original_undo, original_select, original_notify = cli.undo, vim.ui.select, vim.notify
  cli.undo = function(cb)
    called = true
    cb(nil, {})
  end
  vim.ui.select = function(_, _, cb)
    cb('Yes')
  end
  vim.notify = function() end

  actions.undo(h.mock_buffer())
  assert_truthy(called, 'confirming must run cli.undo')

  cli.undo, vim.ui.select, vim.notify = original_undo, original_select, original_notify
end)

test('actions.redo does not call cli.redo when the user declines the confirm', function()
  local called = false
  local original_redo, original_select, original_notify = cli.redo, vim.ui.select, vim.notify
  cli.redo = function()
    called = true
  end
  vim.ui.select = function(_, opts, cb)
    assert_eq('Redo?', opts.prompt)
    cb('No')
  end
  vim.notify = function() end

  actions.redo(h.mock_buffer())
  assert_eq(false, called, 'declining the confirm must not run cli.redo')

  cli.redo, vim.ui.select, vim.notify = original_redo, original_select, original_notify
end)

test('actions.redo calls cli.redo when the user confirms', function()
  local called = false
  local original_redo, original_select, original_notify = cli.redo, vim.ui.select, vim.notify
  cli.redo = function(cb)
    called = true
    cb(nil, {})
  end
  vim.ui.select = function(_, _, cb)
    cb('Yes')
  end
  vim.notify = function() end

  actions.redo(h.mock_buffer())
  assert_truthy(called, 'confirming must run cli.redo')

  cli.redo, vim.ui.select, vim.notify = original_redo, original_select, original_notify
end)

-- ── Command modes (`:`, `!`) ───────────────

test('actions.but_command splits input on whitespace and runs it raw', function()
  local captured_args, captured_opts
  local original_run, original_input, original_notify = cli.run, vim.fn.input, vim.notify
  cli.run = function(args, opts, cb)
    captured_args, captured_opts = args, opts
    cb(nil, 'output text')
  end
  vim.fn.input = function()
    return 'status --json'
  end
  local notified
  vim.notify = function(msg, level)
    notified = { msg = msg, level = level }
  end

  actions.but_command(h.mock_buffer())

  assert_eq(2, #captured_args)
  assert_eq('status', captured_args[1])
  assert_eq('--json', captured_args[2])
  assert_truthy(captured_opts.raw, 'raw mode requested')
  assert_eq('output text', notified.msg)
  assert_eq(vim.log.levels.INFO, notified.level)

  cli.run, vim.fn.input, vim.notify = original_run, original_input, original_notify
end)

test('actions.but_command aborts on empty input without calling cli.run', function()
  local called = false
  local original_run, original_input = cli.run, vim.fn.input
  cli.run = function()
    called = true
  end
  vim.fn.input = function()
    return ''
  end

  actions.but_command(h.mock_buffer())
  assert_eq(false, called)

  cli.run, vim.fn.input = original_run, original_input
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

h.test('toggle_fold parks the cursor back on the fold header after rerender', function()
  local buf = h.mock_buffer()
  buf.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf.buf, 0, -1, false, { 'a', 'b', 'c' })
  buf.win = vim.api.nvim_open_win(buf.buf, true, { relative = 'editor', width = 20, height = 5, row = 0, col = 0 })
  -- Post-rerender rows: the folded branch header slid from row 3 to row 1.
  buf.lines = {
    { selectable = true, type = 'branch', data = { fold_id = 'branch:feat' } },
    { selectable = true, type = 'commit', data = {} },
    { selectable = true, type = 'commit', data = {} },
  }
  vim.api.nvim_win_set_cursor(buf.win, { 3, 0 })

  actions._restore_fold_cursor(buf, 'branch:feat')

  h.assert_eq(1, vim.api.nvim_win_get_cursor(buf.win)[1], 'cursor follows the header row')
  vim.api.nvim_win_close(buf.win, true)
  vim.api.nvim_buf_delete(buf.buf, { force = true })
end)

test('open_file: a commit row routes to the commit_diff tool with its sha', function()
  local buf = h.mock_buffer()
  buf.lines = {
    { type = 'commit', selectable = true, data = { sha = 'deadbeef', cli_id = 'c1' } },
  }
  buf.get_cursor_line = function(self)
    return self.lines[1]
  end

  local commit_diff = require('gitbutler.ui.commit_diff')
  local opened
  local orig = commit_diff.open
  commit_diff.open = function(sha)
    opened = sha
  end
  actions.open_file(buf)
  commit_diff.open = orig

  assert_eq('deadbeef', opened, 'o on a commit opens its sha in the diff tool')
end)

test('open_file target: cursor file wins, else first selected file', function()
  local buf = h.mock_buffer()
  buf.lines = {
    { type = 'branch', selectable = true, data = { name = 'feat' } },
    { type = 'file', selectable = true, data = { cli_id = 'f1', path = 'a.lua' } },
    { type = 'file', selectable = true, data = { cli_id = 'f2', path = 'b.lua' } },
  }
  local cursor_row = 2
  buf.get_cursor_line = function(self)
    return self.lines[cursor_row]
  end

  assert_eq('a.lua', actions._open_target(buf).data.path, 'cursor file row is the target')

  -- Cursor on a non-file row falls back to the first selected file.
  cursor_row = 1
  buf.get_selected_lines = function(_, _)
    return { buf.lines[3] }
  end
  assert_eq('b.lua', actions._open_target(buf).data.path, 'first selected file is the fallback')
end)

-- Every action named in the status keymap must be registered as a handler in
-- status.M.open, or the key silently does nothing at runtime. Unit tests that
-- call actions.<name> directly bypass this dispatch layer and cannot catch it
-- (a missing `details_focus` registration shipped exactly that way).
test('every status keymap action has a registered handler', function()
  local config = require('gitbutler.config')
  local status = require('gitbutler.ui.status')

  local registered = {}
  local buffer_mod = require('gitbutler.ui.buffer')
  local probe = buffer_mod.Buffer.new()
  probe.on = function(_, name)
    registered[name] = true
  end
  probe.open = function() end

  local orig_new, orig_refresh = buffer_mod.Buffer.new, status.refresh
  buffer_mod.Buffer.new = function()
    return probe
  end
  status.refresh = function() end
  local prev_instance = status.instance
  status.instance = nil
  status.open()
  buffer_mod.Buffer.new, status.refresh = orig_new, orig_refresh
  status.instance = prev_instance

  local missing = {}
  for key, action in pairs(config.values.keymaps.status or {}) do
    if action and not registered[action] then
      table.insert(missing, key .. ' -> ' .. action)
    end
  end
  table.sort(missing)
  h.assert_eq('', table.concat(missing, ', '), 'keymap actions without handlers')
end)

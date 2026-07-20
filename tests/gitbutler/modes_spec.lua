local h = require('tests.gitbutler.helpers')
local modes = require('gitbutler.ui.modes')

h.test('modes: rub verb matrix matches but rub', function()
  h.assert_eq('assign', modes.rub_verb('file', 'branch'))
  h.assert_eq('amend', modes.rub_verb('file', 'commit'))
  h.assert_eq('unassign', modes.rub_verb('file', 'uncommitted_header'))
  h.assert_eq('squash', modes.rub_verb('commit', 'commit'))
  h.assert_eq('undo commit', modes.rub_verb('commit', 'uncommitted_header'))
  h.assert_eq('move commit', modes.rub_verb('commit', 'branch'))
  h.assert_eq('uncommit', modes.rub_verb('committed_file', 'uncommitted_header'))
  h.assert_eq('move file', modes.rub_verb('committed_file', 'commit'))
  h.assert_eq('reassign', modes.rub_verb('branch', 'branch'))
  h.assert_eq('amend all', modes.rub_verb('uncommitted_header', 'commit'))
  h.assert_falsy(modes.rub_verb('file', 'file'))
  h.assert_falsy(modes.rub_verb('merge_base', 'commit'))
  h.assert_falsy(modes.rub_verb('commit', 'merge_base'))
end)

h.test('modes: current() reflects state', function()
  h.assert_eq('normal', modes.current())
  modes.state = { mode = 'rub' }
  h.assert_eq('rub', modes.current())
  modes.state = nil
end)

h.test('modes: is_rub_target excludes source, non-selectable and verbless rows', function()
  local state = { mode = 'rub', source = { kind = 'file', ids = { 'aa' }, rows = { 2 } } }
  h.assert_falsy(
    modes.is_rub_target(state, { selectable = true, type = 'file', data = { cli_id = 'aa' } }, 2),
    'source row excluded'
  )
  h.assert_falsy(modes.is_rub_target(state, { selectable = false, type = 'blank' }, 3), 'non-selectable excluded')
  h.assert_falsy(modes.is_rub_target(state, { selectable = true, type = 'merge_base' }, 5), 'verbless type excluded')
  h.assert_truthy(
    modes.is_rub_target(state, { selectable = true, type = 'branch', data = { cli_id = 'bb' } }, 4),
    'branch target accepted'
  )
end)

h.test('modes: _rub_target_id is zz for uncommitted header, else cli_id', function()
  h.assert_eq('zz', modes._rub_target_id({ type = 'uncommitted_header', data = { cli_id = 'zz' } }))
  h.assert_eq('bb', modes._rub_target_id({ type = 'branch', data = { cli_id = 'bb' } }))
  h.assert_eq('cd', modes._rub_target_id({ type = 'commit', data = { cli_id = 'cd', sha = 'deadbeef' } }))
  h.assert_falsy(modes._rub_target_id({ type = 'file', data = {} }))
end)

h.test('cli.rub builds but rub <source> <target> --json', function()
  local cli = require('gitbutler.cli')
  local captured
  local orig_run = cli.run
  cli.run = function(args, cb)
    captured = args
    cb(nil, {})
  end
  cli.rub('aa', 'bb', function() end)
  cli.run = orig_run
  h.assert_eq('rub', captured[1])
  h.assert_eq('aa', captured[2])
  h.assert_eq('bb', captured[3])
  h.assert_eq('--json', captured[4])
end)

h.test('modes: rub confirm exits mode, rubs each source id, then refreshes', function()
  local cli = require('gitbutler.cli')
  local status = require('gitbutler.ui.status')
  local calls = {}
  local refreshed = false
  local orig_rub, orig_refresh = cli.rub, status.refresh
  cli.rub = function(source, target, cb)
    h.assert_eq('normal', modes.current(), 'mode must exit before the CLI chain runs')
    table.insert(calls, { source, target })
    cb(nil, {})
  end
  status.refresh = function()
    refreshed = true
  end

  local buf = h.mock_buffer()
  buf.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf.buf, 0, -1, false, { 'a', 'b', 'c' })
  buf.win = vim.api.nvim_open_win(buf.buf, true, { relative = 'editor', width = 20, height = 5, row = 0, col = 0 })
  buf.lines = {
    { selectable = true, type = 'file', data = { cli_id = 'aa' } },
    { selectable = true, type = 'file', data = { cli_id = 'ab' } },
    { selectable = true, type = 'branch', data = { cli_id = 'bb', name = 'feat' } },
  }

  modes.enter_rub(buf, { kind = 'file', ids = { 'aa', 'ab' }, rows = { 1, 2 }, label = 'x' })
  h.assert_truthy(buf.mode_filter, 'mode_filter set on enter')
  h.assert_eq(3, vim.api.nvim_win_get_cursor(buf.win)[1], 'cursor moved to first valid target')

  modes._rub_confirm(buf)

  h.assert_eq(2, #calls)
  h.assert_eq('aa', calls[1][1])
  h.assert_eq('bb', calls[1][2])
  h.assert_eq('ab', calls[2][1])
  h.assert_eq('bb', calls[2][2])
  h.assert_truthy(refreshed, 'refresh after chain completes')
  h.assert_falsy(buf.mode_filter, 'mode_filter cleared on exit')

  cli.rub, status.refresh = orig_rub, orig_refresh
  vim.api.nvim_win_close(buf.win, true)
  vim.api.nvim_buf_delete(buf.buf, { force = true })
end)

h.test('modes: rub confirm stops the chain on first error but still refreshes', function()
  local cli = require('gitbutler.cli')
  local status = require('gitbutler.ui.status')
  local calls = 0
  local refreshes = 0
  local orig_rub, orig_refresh, orig_notify = cli.rub, status.refresh, vim.notify
  cli.rub = function(_, _, cb)
    calls = calls + 1
    cb('boom')
  end
  status.refresh = function()
    refreshes = refreshes + 1
  end
  vim.notify = function() end

  local buf = h.mock_buffer()
  buf.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf.buf, 0, -1, false, { 'a', 'b', 'c' })
  buf.win = vim.api.nvim_open_win(buf.buf, true, { relative = 'editor', width = 20, height = 5, row = 0, col = 0 })
  buf.lines = {
    { selectable = true, type = 'file', data = { cli_id = 'aa' } },
    { selectable = true, type = 'file', data = { cli_id = 'ab' } },
    { selectable = true, type = 'branch', data = { cli_id = 'bb', name = 'feat' } },
  }

  modes.enter_rub(buf, { kind = 'file', ids = { 'aa', 'ab' }, rows = { 1, 2 }, label = 'x' })
  modes._rub_confirm(buf)

  h.assert_eq(1, calls, 'second source never rubbed after error')
  h.assert_eq(1, refreshes, 'refresh still called exactly once')

  cli.rub, status.refresh, vim.notify = orig_rub, orig_refresh, orig_notify
  vim.api.nvim_win_close(buf.win, true)
  vim.api.nvim_buf_delete(buf.buf, { force = true })
end)

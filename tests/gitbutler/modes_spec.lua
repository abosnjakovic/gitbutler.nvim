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

h.test('modes: is_commit_target accepts branch and commit rows only', function()
  h.assert_truthy(modes.is_commit_target({ selectable = true, type = 'branch', data = { name = 'feat' } }))
  h.assert_truthy(modes.is_commit_target({ selectable = true, type = 'commit', data = { cli_id = 'cd' } }))
  h.assert_falsy(modes.is_commit_target({ selectable = true, type = 'file', data = {} }), 'file rejected')
  h.assert_falsy(modes.is_commit_target({ selectable = true, type = 'merge_base', data = {} }), 'merge_base rejected')
  h.assert_falsy(modes.is_commit_target({ selectable = false, type = 'branch', data = {} }), 'non-selectable rejected')
end)

h.test('modes: is_move_target for a commit source', function()
  local state = { mode = 'move', source = { kind = 'commit', ids = { 'cd' }, rows = { 2 } }, opts = {} }
  h.assert_falsy(
    modes.is_move_target(state, { selectable = true, type = 'commit', data = { cli_id = 'cd' } }, 2),
    'source row excluded'
  )
  h.assert_falsy(modes.is_move_target(state, { selectable = true, type = 'merge_base' }, 5), 'merge_base rejected')
  h.assert_falsy(modes.is_move_target(state, { selectable = true, type = 'file' }, 6), 'file rejected')
  h.assert_truthy(modes.is_move_target(state, { selectable = true, type = 'commit', data = { cli_id = 'ce' } }, 3))
  h.assert_truthy(modes.is_move_target(state, { selectable = true, type = 'branch', data = { cli_id = 'bb' } }, 4))
end)

h.test('modes: is_move_target accepts merge_base only for a branch source', function()
  local state = { mode = 'move', source = { kind = 'branch', ids = { 'bb' }, rows = { 1 } }, opts = {} }
  h.assert_truthy(modes.is_move_target(state, { selectable = true, type = 'merge_base' }, 5), 'unstack target')
  h.assert_truthy(modes.is_move_target(state, { selectable = true, type = 'branch', data = { cli_id = 'cc' } }, 3))
  h.assert_falsy(
    modes.is_move_target(state, { selectable = true, type = 'commit', data = { cli_id = 'cd' } }, 4),
    'branch onto commit is not a documented but move operation'
  )
end)

h.test('cli.commit_at builds but commit <branch> -m <msg> with anchor flags', function()
  local cli = require('gitbutler.cli')
  local captured
  local orig_run = cli.run
  cli.run = function(args, cb)
    captured = args
    cb(nil, {})
  end
  cli.commit_at('feat', 'msg', { after = 'cd' }, function() end)
  h.assert_eq('commit feat -m msg --after cd --json', table.concat(captured, ' '))
  cli.commit_at('feat', 'msg', { before = 'cd' }, function() end)
  h.assert_eq('commit feat -m msg --before cd --json', table.concat(captured, ' '))
  cli.run = orig_run
end)

h.test('cli.commit_empty builds but commit empty with anchor flags', function()
  local cli = require('gitbutler.cli')
  local captured
  local orig_run = cli.run
  cli.run = function(args, cb)
    captured = args
    cb(nil, {})
  end
  cli.commit_empty({ after = 'bb' }, function() end)
  h.assert_eq('commit empty --after bb --json', table.concat(captured, ' '))
  cli.commit_empty({ before = 'cd' }, function() end)
  h.assert_eq('commit empty --before cd --json', table.concat(captured, ' '))
  cli.run = orig_run
end)

h.test('cli.move appends --after before --json only when opts.after', function()
  local cli = require('gitbutler.cli')
  local captured
  local orig_run = cli.run
  cli.run = function(args, cb)
    captured = args
    cb(nil, {})
  end
  cli.move('aa,ab', 'cd', function() end, { after = true })
  h.assert_eq('move aa,ab cd --after --json', table.concat(captured, ' '))
  cli.move('aa', 'feat', function() end)
  h.assert_eq('move aa feat --json', table.concat(captured, ' '))
  cli.move('aa', 'cd', function() end, { after = false })
  h.assert_eq('move aa cd --json', table.concat(captured, ' '))
  cli.run = orig_run
end)

h.test('modes: _commit_anchor maps above to after (lands above), else before', function()
  local a = modes._commit_anchor({ above = true }, 'cd')
  h.assert_eq('cd', a.after)
  h.assert_falsy(a.before)
  local b = modes._commit_anchor({ above = false }, 'cd')
  h.assert_eq('cd', b.before)
  h.assert_falsy(b.after)
end)

h.test('modes: _move_args joins commit sources and maps above to the after flag', function()
  local state =
    { mode = 'move', source = { kind = 'commit', ids = { 'aa', 'ab' }, rows = { 1, 2 } }, opts = { above = false } }
  local src, target, opts = modes._move_args(state, { selectable = true, type = 'commit', data = { cli_id = 'cd' } })
  h.assert_eq('aa,ab', src)
  h.assert_eq('cd', target)
  h.assert_falsy(opts and opts.after, "default (below) is but's --before default (no flag)")

  state.opts.above = true
  local _, _, opts2 = modes._move_args(state, { selectable = true, type = 'commit', data = { cli_id = 'cd' } })
  h.assert_truthy(opts2 and opts2.after, 'above lands above the target via --after')
end)

h.test('modes: _move_args handles branch targets and merge_base unstack', function()
  local commit_state = { mode = 'move', source = { kind = 'commit', ids = { 'aa' }, rows = { 1 } }, opts = {} }
  local src, target, opts =
    modes._move_args(commit_state, { selectable = true, type = 'branch', data = { cli_id = 'bb' } })
  h.assert_eq('aa', src)
  h.assert_eq('bb', target)
  h.assert_falsy(opts, 'branch target takes no --after')

  local branch_state = { mode = 'move', source = { kind = 'branch', ids = { 'bb' }, rows = { 1 } }, opts = {} }
  local src2, target2, opts2 = modes._move_args(branch_state, { selectable = true, type = 'merge_base', data = {} })
  h.assert_eq('bb', src2)
  h.assert_eq('zz', target2)
  h.assert_falsy(opts2)
end)

h.test('modes: above/below direction agrees between commit and move modes', function()
  -- above = the new/moved commit lands above the target in the display.
  h.assert_eq('cd', modes._commit_anchor({ above = true }, 'cd').after, 'commit above -> --after')
  h.assert_eq('cd', modes._commit_anchor({ above = false }, 'cd').before, 'commit below -> --before')

  local cli = require('gitbutler.cli')
  local captured
  local orig_run = cli.run
  cli.run = function(args, cb)
    captured = args
    cb(nil, {})
  end
  local state = { mode = 'move', source = { kind = 'commit', ids = { 'aa' }, rows = { 1 } }, opts = { above = true } }
  local line = { selectable = true, type = 'commit', data = { cli_id = 'cd' } }
  local src, target, opts = modes._move_args(state, line)
  cli.move(src, target, function() end, opts)
  h.assert_eq('move aa cd --after --json', table.concat(captured, ' '), 'move above -> --after')

  state.opts.above = false
  src, target, opts = modes._move_args(state, line)
  cli.move(src, target, function() end, opts)
  h.assert_eq('move aa cd --json', table.concat(captured, ' '), 'move below -> no flag (but defaults to before)')
  cli.run = orig_run
end)

local function mode_buffer(lines)
  local buf = h.mock_buffer()
  buf.buf = vim.api.nvim_create_buf(false, true)
  local text = {}
  for i = 1, #lines do
    text[i] = 'row' .. i
  end
  vim.api.nvim_buf_set_lines(buf.buf, 0, -1, false, text)
  buf.win = vim.api.nvim_open_win(buf.buf, true, { relative = 'editor', width = 20, height = 8, row = 0, col = 0 })
  buf.lines = lines
  return buf
end

local function close_buffer(buf)
  vim.api.nvim_win_close(buf.win, true)
  vim.api.nvim_buf_delete(buf.buf, { force = true })
end

h.test('modes: commit confirm on a branch row prompts for a message and commits', function()
  local cli = require('gitbutler.cli')
  local status = require('gitbutler.ui.status')
  local float = require('gitbutler.ui.float')
  local captured
  local refreshed = false
  local orig_commit, orig_refresh, orig_input = cli.commit, status.refresh, float.input
  cli.commit = function(branch, message, cb)
    h.assert_eq('normal', modes.current(), 'mode must exit before the CLI call')
    captured = { branch, message }
    cb(nil, {})
  end
  status.refresh = function()
    refreshed = true
  end
  float.input = function(opts)
    opts.on_submit('a message')
  end

  local buf = mode_buffer({
    { selectable = true, type = 'branch', data = { cli_id = 'bb', name = 'feat' } },
    { selectable = true, type = 'commit', data = { cli_id = 'cd', branch_name = 'feat' } },
  })
  modes.enter(buf, 'commit', nil, { above = false })
  h.assert_truthy(buf.mode_filter, 'mode_filter set on enter')
  vim.api.nvim_win_set_cursor(buf.win, { 1, 0 })
  modes._commit_confirm(buf)

  h.assert_eq('feat', captured[1])
  h.assert_eq('a message', captured[2])
  h.assert_truthy(refreshed, 'refresh after commit')
  h.assert_falsy(buf.mode_filter, 'mode_filter cleared on exit')

  cli.commit, status.refresh, float.input = orig_commit, orig_refresh, orig_input
  close_buffer(buf)
end)

h.test('modes: commit confirm on a commit row anchors via commit_at', function()
  local cli = require('gitbutler.cli')
  local status = require('gitbutler.ui.status')
  local float = require('gitbutler.ui.float')
  local captured
  local orig_commit_at, orig_refresh, orig_input = cli.commit_at, status.refresh, float.input
  cli.commit_at = function(branch, message, anchor, cb)
    captured = { branch = branch, message = message, anchor = anchor }
    cb(nil, {})
  end
  status.refresh = function() end
  float.input = function(opts)
    opts.on_submit('anchored')
  end

  local buf = mode_buffer({
    { selectable = true, type = 'branch', data = { cli_id = 'bb', name = 'feat' } },
    { selectable = true, type = 'commit', data = { cli_id = 'cd', branch_name = 'feat' } },
  })
  modes.enter(buf, 'commit', nil, { above = false })
  vim.api.nvim_win_set_cursor(buf.win, { 2, 0 })
  modes._commit_confirm(buf)

  h.assert_eq('feat', captured.branch)
  h.assert_eq('anchored', captured.message)
  h.assert_eq('cd', captured.anchor.before, 'default (below marker) anchors before the commit')
  h.assert_falsy(captured.anchor.after)

  cli.commit_at, status.refresh, float.input = orig_commit_at, orig_refresh, orig_input
  close_buffer(buf)
end)

h.test('modes: commit confirm with empty opt skips the input float', function()
  local cli = require('gitbutler.cli')
  local status = require('gitbutler.ui.status')
  local float = require('gitbutler.ui.float')
  local captured
  local orig_commit, orig_refresh, orig_input = cli.commit, status.refresh, float.input
  cli.commit = function(branch, message, cb)
    captured = { branch, message }
    cb(nil, {})
  end
  status.refresh = function() end
  float.input = function()
    error('input float must not open for an empty-message commit')
  end

  local buf = mode_buffer({
    { selectable = true, type = 'branch', data = { cli_id = 'bb', name = 'feat' } },
  })
  modes.enter(buf, 'commit', nil, { above = false, empty = true })
  vim.api.nvim_win_set_cursor(buf.win, { 1, 0 })
  modes._commit_confirm(buf)

  h.assert_eq('feat', captured[1])
  h.assert_eq(' ', captured[2], 'empty commits use a single-space message')

  cli.commit, status.refresh, float.input = orig_commit, orig_refresh, orig_input
  close_buffer(buf)
end)

h.test('modes: move confirm joins sources into one cli.move call and refreshes', function()
  local cli = require('gitbutler.cli')
  local status = require('gitbutler.ui.status')
  local captured
  local refreshed = false
  local orig_move, orig_refresh = cli.move, status.refresh
  cli.move = function(src, target, cb, opts)
    h.assert_eq('normal', modes.current(), 'mode must exit before the CLI call')
    captured = { src = src, target = target, opts = opts }
    cb(nil, {})
  end
  status.refresh = function()
    refreshed = true
  end

  local buf = mode_buffer({
    { selectable = true, type = 'commit', data = { cli_id = 'aa', branch_name = 'feat' } },
    { selectable = true, type = 'commit', data = { cli_id = 'ab', branch_name = 'feat' } },
    { selectable = true, type = 'commit', data = { cli_id = 'cd', branch_name = 'other' } },
  })
  modes.enter(buf, 'move', { kind = 'commit', ids = { 'aa', 'ab' }, rows = { 1, 2 }, label = 'x' }, { above = false })
  vim.api.nvim_win_set_cursor(buf.win, { 3, 0 })
  modes._move_confirm(buf)

  h.assert_eq('aa,ab', captured.src)
  h.assert_eq('cd', captured.target)
  h.assert_falsy(captured.opts and captured.opts.after, 'default (below) omits --after')
  h.assert_truthy(refreshed, 'refresh after move')
  h.assert_falsy(buf.mode_filter, 'mode_filter cleared on exit')

  cli.move, status.refresh = orig_move, orig_refresh
  close_buffer(buf)
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

h.test('modes: stack apply lists unapplied branches, exits, applies pick', function()
  local cli = require('gitbutler.cli')
  local status = require('gitbutler.ui.status')
  local float = require('gitbutler.ui.float')
  local fixtures = require('tests.gitbutler.fixtures')
  local applied, refreshed, picker_items
  local orig_bl, orig_apply, orig_refresh, orig_picker, orig_notify =
    cli.branch_list, cli.apply, status.refresh, float.fuzzy_picker, vim.notify
  cli.branch_list = function(cb)
    cb(nil, fixtures.branch_list)
  end
  cli.apply = function(name, cb)
    applied = name
    cb(nil, {})
  end
  status.refresh = function()
    refreshed = true
  end
  float.fuzzy_picker = function(opts)
    picker_items = opts.items
    opts.on_select(opts.items[1])
  end
  vim.notify = function() end

  local buf = mode_buffer({
    { selectable = true, type = 'branch', data = { cli_id = 'bb', name = 'feature-auth' } },
  })
  modes.enter(buf, 'stack')
  modes._mode_keys.stack['a'](buf)

  h.assert_eq('normal', modes.current(), 'stack mode exited before the picker selection runs')
  h.assert_eq(1, #picker_items, 'only unapplied branches offered')
  h.assert_eq('old-experiment', picker_items[1])
  h.assert_eq('old-experiment', applied)
  h.assert_truthy(refreshed)

  cli.branch_list, cli.apply, status.refresh, float.fuzzy_picker, vim.notify =
    orig_bl, orig_apply, orig_refresh, orig_picker, orig_notify
  close_buffer(buf)
end)

h.test('modes: stack apply with no unapplied branches notifies and stays put', function()
  local cli = require('gitbutler.cli')
  local fixtures = require('tests.gitbutler.fixtures')
  local warned
  local orig_bl, orig_notify = cli.branch_list, vim.notify
  cli.branch_list = function(cb)
    cb(nil, fixtures.branch_list_empty)
  end
  vim.notify = function(msg, level)
    if level == vim.log.levels.WARN then
      warned = msg
    end
  end

  local buf = mode_buffer({
    { selectable = true, type = 'branch', data = { cli_id = 'bb', name = 'feature-auth' } },
  })
  modes.enter(buf, 'stack')
  modes._mode_keys.stack['a'](buf)

  h.assert_truthy(warned and warned:match('no unapplied branches'))
  h.assert_eq('stack', modes.current(), 'mode kept when there is nothing to apply')
  modes.exit(buf)

  cli.branch_list, vim.notify = orig_bl, orig_notify
  close_buffer(buf)
end)

h.test('modes: stack unapply confirms when the stack has assigned changes', function()
  local cli = require('gitbutler.cli')
  local status = require('gitbutler.ui.status')
  local unapplied, refreshed, prompted
  local orig_unapply, orig_refresh, orig_select, orig_notify = cli.unapply, status.refresh, vim.ui.select, vim.notify
  cli.unapply = function(name, cb)
    h.assert_eq('normal', modes.current(), 'mode must exit before the CLI call')
    unapplied = name
    cb(nil, {})
  end
  status.refresh = function()
    refreshed = true
  end
  vim.ui.select = function(_, opts, cb)
    prompted = opts.prompt
    cb('Yes')
  end
  vim.notify = function() end

  local buf = mode_buffer({
    {
      selectable = true,
      type = 'branch',
      data = { cli_id = 'bb', name = 'feature-auth', stack = { assignedChanges = { { cliId = 'ac' } } } },
    },
  })
  modes.enter(buf, 'stack')
  vim.api.nvim_win_set_cursor(buf.win, { 1, 0 })
  modes._mode_keys.stack['u'](buf)

  h.assert_truthy(prompted, 'confirm prompt shown for assigned changes')
  h.assert_eq('feature-auth', unapplied)
  h.assert_truthy(refreshed)

  cli.unapply, status.refresh, vim.ui.select, vim.notify = orig_unapply, orig_refresh, orig_select, orig_notify
  close_buffer(buf)
end)

h.test('modes: stack unapply warns off non-branch rows, skips confirm when clean', function()
  local cli = require('gitbutler.cli')
  local status = require('gitbutler.ui.status')
  local unapplied, warned, selected
  local orig_unapply, orig_refresh, orig_select, orig_notify = cli.unapply, status.refresh, vim.ui.select, vim.notify
  cli.unapply = function(name, cb)
    unapplied = name
    cb(nil, {})
  end
  status.refresh = function() end
  vim.ui.select = function()
    selected = true
  end
  vim.notify = function(msg, level)
    if level == vim.log.levels.WARN then
      warned = msg
    end
  end

  local buf = mode_buffer({
    { selectable = true, type = 'file', data = { cli_id = 'aa' } },
    { selectable = true, type = 'branch', data = { cli_id = 'bb', name = 'feat', stack = { assignedChanges = {} } } },
  })
  modes.enter(buf, 'stack')
  vim.api.nvim_win_set_cursor(buf.win, { 1, 0 })
  modes._mode_keys.stack['u'](buf)
  h.assert_truthy(warned, 'non-branch row warns')
  h.assert_falsy(unapplied)

  vim.api.nvim_win_set_cursor(buf.win, { 2, 0 })
  modes._mode_keys.stack['u'](buf)
  h.assert_falsy(selected, 'no confirm prompt for a clean stack')
  h.assert_eq('feat', unapplied)

  cli.unapply, status.refresh, vim.ui.select, vim.notify = orig_unapply, orig_refresh, orig_select, orig_notify
  close_buffer(buf)
end)

h.test('modes: stack m switches to move mode with the cursor branch as source', function()
  local orig_notify = vim.notify
  vim.notify = function() end
  local buf = mode_buffer({
    { selectable = true, type = 'branch', data = { cli_id = 'bb', name = 'feature-auth' } },
    { selectable = true, type = 'branch', data = { cli_id = 'cc', name = 'other' } },
  })
  modes.enter(buf, 'stack')
  vim.api.nvim_win_set_cursor(buf.win, { 1, 0 })
  modes._mode_keys.stack['m'](buf)

  h.assert_eq('move', modes.current())
  h.assert_eq('branch', modes.state.source.kind)
  h.assert_eq('bb', modes.state.source.ids[1])
  h.assert_eq(1, modes.state.source.rows[1])

  modes.exit(buf)
  vim.notify = orig_notify
  close_buffer(buf)
end)

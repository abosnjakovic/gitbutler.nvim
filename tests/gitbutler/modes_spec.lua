local h = require('tests.gitbutler.helpers')
local modes = require('gitbutler.ui.modes')

h.test('modes: accepts_source gates which rows each verb takes as a source', function()
  h.assert_truthy(modes.accepts_source('amend', 'file'))
  h.assert_truthy(modes.accepts_source('amend', 'uncommitted_header'))
  h.assert_truthy(modes.accepts_source('squash', 'commit'))
  h.assert_truthy(modes.accepts_source('squash', 'branch'))
  h.assert_truthy(modes.accepts_source('squash', 'committed_file'))
  -- amend only ever takes uncommitted work; squash only ever takes committed work.
  h.assert_falsy(modes.accepts_source('amend', 'commit'))
  h.assert_falsy(modes.accepts_source('amend', 'branch'))
  h.assert_falsy(modes.accepts_source('amend', 'committed_file'))
  h.assert_falsy(modes.accepts_source('squash', 'file'))
  h.assert_falsy(modes.accepts_source('squash', 'uncommitted_header'))
  h.assert_falsy(modes.accepts_source('amend', 'merge_base'))
  h.assert_falsy(modes.accepts_source('squash', 'merge_base'))
  h.assert_falsy(modes.accepts_source('move', 'file'), 'only verb modes accept a source kind')
end)

h.test('modes: current() reflects state', function()
  h.assert_eq('normal', modes.current())
  modes.state = { mode = 'amend' }
  h.assert_eq('amend', modes.current())
  modes.state = nil
end)

h.test('modes: is_verb_target excludes source, non-selectable and non-commit rows', function()
  local state = { mode = 'amend', source = { kind = 'file', ids = { 'aa' }, rows = { 2 } } }
  h.assert_falsy(
    modes.is_verb_target(state, { selectable = true, type = 'commit', data = { cli_id = 'cd' } }, 2),
    'source row excluded'
  )
  h.assert_falsy(modes.is_verb_target(state, { selectable = false, type = 'blank' }, 3), 'non-selectable excluded')
  h.assert_falsy(modes.is_verb_target(state, { selectable = true, type = 'merge_base' }, 5), 'merge_base excluded')
  h.assert_falsy(
    modes.is_verb_target(state, { selectable = true, type = 'file', data = { cli_id = 'ab' } }, 6),
    'only commit and branch rows are targets'
  )
  h.assert_truthy(
    modes.is_verb_target(state, { selectable = true, type = 'branch', data = { cli_id = 'bb' } }, 4),
    'branch target accepted'
  )
  h.assert_truthy(
    modes.is_verb_target(state, { selectable = true, type = 'commit', data = { cli_id = 'ce' } }, 7),
    'commit target accepted'
  )
end)

h.test('cli.redo builds but redo --json', function()
  local cli = require('gitbutler.cli')
  local captured
  local orig_run = cli.run
  cli.run = function(args, cb)
    captured = args
    cb(nil, {})
  end
  cli.redo(function() end)
  cli.run = orig_run
  h.assert_eq('redo --json', table.concat(captured, ' '))
end)

h.test('modes: amend confirm exits mode, amends every source in one call, then refreshes', function()
  local cli = require('gitbutler.cli')
  local status = require('gitbutler.ui.status')
  local calls = {}
  local refreshed = false
  local orig_amend, orig_refresh = cli.amend, status.refresh
  cli.amend = function(target, sources, cb)
    h.assert_eq('normal', modes.current(), 'mode must exit before the CLI call runs')
    table.insert(calls, { target = target, sources = sources })
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

  modes.enter_verb(buf, 'amend', { kind = 'file', ids = { 'aa', 'ab' }, rows = { 1, 2 }, label = 'x' })
  h.assert_truthy(buf.mode_filter, 'mode_filter set on enter')
  h.assert_eq(3, vim.api.nvim_win_get_cursor(buf.win)[1], 'cursor moved to first valid target')

  modes._verb_confirm(buf)

  h.assert_eq(1, #calls, 'every source rides in a single amend call')
  h.assert_eq('bb', calls[1].target)
  h.assert_eq(2, #calls[1].sources)
  h.assert_eq('aa', calls[1].sources[1])
  h.assert_eq('ab', calls[1].sources[2])
  h.assert_truthy(refreshed, 'refresh after the call completes')
  h.assert_falsy(buf.mode_filter, 'mode_filter cleared on exit')

  cli.amend, status.refresh = orig_amend, orig_refresh
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

h.test('cli.commit builds but commit <target flag> -m <msg>', function()
  local cli = require('gitbutler.cli')
  local captured
  local orig_run = cli.run
  cli.run = function(args, cb)
    captured = args
    cb(nil, {})
  end
  cli.commit({ above = 'cd' }, 'msg', function() end)
  h.assert_eq('commit --above cd -m msg --json', table.concat(captured, ' '))
  cli.commit({ below = 'cd' }, 'msg', function() end)
  h.assert_eq('commit --below cd -m msg --json', table.concat(captured, ' '))
  cli.commit({ branch = 'feat' }, 'msg', function() end)
  h.assert_eq('commit --branch feat -m msg --json', table.concat(captured, ' '))
  cli.run = orig_run
end)

h.test('cli.commit_empty builds but commit --empty --no-message with anchor flags', function()
  local cli = require('gitbutler.cli')
  local captured
  local orig_run = cli.run
  cli.run = function(args, cb)
    captured = args
    cb(nil, {})
  end
  cli.commit_empty({ above = 'bb' }, function() end)
  h.assert_eq('commit --empty --no-message --above bb --json', table.concat(captured, ' '))
  cli.commit_empty({ below = 'cd' }, function() end)
  h.assert_eq('commit --empty --no-message --below cd --json', table.concat(captured, ' '))
  cli.run = orig_run
end)

h.test('cli.move lists every source then exactly one target flag', function()
  local cli = require('gitbutler.cli')
  local captured
  local orig_run = cli.run
  cli.run = function(args, cb)
    captured = args
    cb(nil, {})
  end
  cli.move({ 'aa', 'ab' }, { above = 'cd' }, function() end)
  h.assert_eq('move aa ab --above cd --json', table.concat(captured, ' '))
  cli.move({ 'aa' }, { below = 'cd' }, function() end)
  h.assert_eq('move aa --below cd --json', table.concat(captured, ' '))
  cli.move({ 'aa' }, { branch = 'feat' }, function() end)
  h.assert_eq('move aa --branch feat --json', table.concat(captured, ' '))
  cli.move({ 'bb' }, { unstack = true }, function() end)
  h.assert_eq('move bb --unstack --json', table.concat(captured, ' '))
  cli.run = orig_run
end)

h.test('modes: _commit_anchor maps above to --above (lands above), else --below', function()
  local a = modes._commit_anchor({ above = true }, 'cd')
  h.assert_eq('cd', a.above)
  h.assert_falsy(a.below)
  local b = modes._commit_anchor({ above = false }, 'cd')
  h.assert_eq('cd', b.below)
  h.assert_falsy(b.above)
end)

h.test('modes: _move_args returns every commit source and the above/below target', function()
  local state =
    { mode = 'move', source = { kind = 'commit', ids = { 'aa', 'ab' }, rows = { 1, 2 } }, opts = { above = false } }
  local sources, target = modes._move_args(state, { selectable = true, type = 'commit', data = { cli_id = 'cd' } })
  h.assert_eq(2, #sources, 'sources stay a list, one call carries them all')
  h.assert_eq('aa', sources[1])
  h.assert_eq('ab', sources[2])
  h.assert_eq('cd', target.below, 'default lands below the target')
  h.assert_falsy(target.above)

  state.opts.above = true
  local _, target2 = modes._move_args(state, { selectable = true, type = 'commit', data = { cli_id = 'cd' } })
  h.assert_eq('cd', target2.above, 'above lands above the target via --above')
  h.assert_falsy(target2.below)
end)

h.test('modes: _move_args handles branch targets and merge_base unstack', function()
  local commit_state = { mode = 'move', source = { kind = 'commit', ids = { 'aa' }, rows = { 1 } }, opts = {} }
  local sources, target =
    modes._move_args(commit_state, { selectable = true, type = 'branch', data = { cli_id = 'bb', name = 'feat' } })
  h.assert_eq('aa', sources[1])
  h.assert_eq('feat', target.branch, '--branch takes the name, not the row cli id, so it can create the branch')
  h.assert_falsy(target.above)
  h.assert_falsy(target.below)

  local branch_state = { mode = 'move', source = { kind = 'branch', ids = { 'bb' }, rows = { 1 } }, opts = {} }
  local sources2, target2 = modes._move_args(branch_state, { selectable = true, type = 'merge_base', data = {} })
  h.assert_eq('bb', sources2[1])
  h.assert_truthy(target2.unstack, 'the merge base unstacks')
  h.assert_falsy(target2.branch)
end)

h.test('modes: above/below direction agrees between commit and move modes', function()
  -- above = the new/moved commit lands above the target in the display.
  h.assert_eq('cd', modes._commit_anchor({ above = true }, 'cd').above, 'commit above -> --above')
  h.assert_eq('cd', modes._commit_anchor({ above = false }, 'cd').below, 'commit below -> --below')

  local cli = require('gitbutler.cli')
  local captured
  local orig_run = cli.run
  cli.run = function(args, cb)
    captured = args
    cb(nil, {})
  end
  local state = { mode = 'move', source = { kind = 'commit', ids = { 'aa' }, rows = { 1 } }, opts = { above = true } }
  local line = { selectable = true, type = 'commit', data = { cli_id = 'cd' } }
  local sources, target = modes._move_args(state, line)
  cli.move(sources, target, function() end)
  h.assert_eq('move aa --above cd --json', table.concat(captured, ' '), 'move above -> --above')

  state.opts.above = false
  sources, target = modes._move_args(state, line)
  cli.move(sources, target, function() end)
  h.assert_eq('move aa --below cd --json', table.concat(captured, ' '), 'move below -> --below')
  cli.run = orig_run
end)

h.test('actions._jump_target: exact cli_id match wins over any prefix match', function()
  local actions = require('gitbutler.actions')
  local lines = {
    { data = { cli_id = 'ab' } },
    { data = { cli_id = 'abc' } },
  }
  h.assert_eq(1, actions._jump_target(lines, 'ab'))
end)

h.test('actions._jump_target: unique prefix match resolves to that row', function()
  local actions = require('gitbutler.actions')
  local lines = {
    { data = { cli_id = 'aa' } },
    { data = { cli_id = 'bc' } },
  }
  h.assert_eq(2, actions._jump_target(lines, 'b'))
end)

h.test('actions._jump_target: ambiguous prefix returns nil', function()
  local actions = require('gitbutler.actions')
  local lines = {
    { data = { cli_id = 'ab' } },
    { data = { cli_id = 'ac' } },
  }
  h.assert_falsy(actions._jump_target(lines, 'a'))
end)

h.test('actions._jump_target: no match returns nil', function()
  local actions = require('gitbutler.actions')
  local lines = { { data = { cli_id = 'ab' } } }
  h.assert_falsy(actions._jump_target(lines, 'zz'))
end)

h.test('actions._jump_target: empty query returns nil', function()
  local actions = require('gitbutler.actions')
  local lines = { { data = { cli_id = 'ab' } } }
  h.assert_falsy(actions._jump_target(lines, ''))
end)

h.test('actions._copy_text: commit row copies the full sha', function()
  local actions = require('gitbutler.actions')
  h.assert_eq('deadbeefcafe', actions._copy_text({ type = 'commit', data = { sha = 'deadbeefcafe', cli_id = 'cd' } }))
end)

h.test('actions._copy_text: file row copies its path', function()
  local actions = require('gitbutler.actions')
  h.assert_eq('a.lua', actions._copy_text({ type = 'file', data = { path = 'a.lua' } }))
end)

h.test('actions._copy_text: committed_file row copies its path', function()
  local actions = require('gitbutler.actions')
  h.assert_eq('b.lua', actions._copy_text({ type = 'committed_file', data = { path = 'b.lua' } }))
end)

h.test('actions._copy_text: branch row copies its name', function()
  local actions = require('gitbutler.actions')
  h.assert_eq('feat', actions._copy_text({ type = 'branch', data = { name = 'feat' } }))
end)

h.test('actions._copy_text: uncommitted header always copies zz', function()
  local actions = require('gitbutler.actions')
  h.assert_eq('zz', actions._copy_text({ type = 'uncommitted_header', data = { cli_id = 'zz' } }))
end)

h.test('actions._copy_text: rows with nothing copyable return nil', function()
  local actions = require('gitbutler.actions')
  h.assert_falsy(actions._copy_text({ type = 'merge_base', data = {} }))
  h.assert_falsy(actions._copy_text(nil))
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
  cli.commit = function(target, message, cb)
    h.assert_eq('normal', modes.current(), 'mode must exit before the CLI call')
    captured = { target = target, message = message }
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

  h.assert_eq('feat', captured.target.branch, '--branch takes the name so a missing branch is created')
  h.assert_eq('a message', captured.message)
  h.assert_truthy(refreshed, 'refresh after commit')
  h.assert_falsy(buf.mode_filter, 'mode_filter cleared on exit')

  cli.commit, status.refresh, float.input = orig_commit, orig_refresh, orig_input
  close_buffer(buf)
end)

h.test('modes: commit confirm on a commit row anchors the commit target', function()
  local cli = require('gitbutler.cli')
  local status = require('gitbutler.ui.status')
  local float = require('gitbutler.ui.float')
  local captured
  local orig_commit, orig_refresh, orig_input = cli.commit, status.refresh, float.input
  cli.commit = function(target, message, cb)
    captured = { target = target, message = message }
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

  h.assert_eq('anchored', captured.message)
  h.assert_eq('cd', captured.target.below, 'default (below marker) anchors below the commit')
  h.assert_falsy(captured.target.above)
  h.assert_falsy(captured.target.branch, 'a commit row anchors, it does not name a branch')

  cli.commit, status.refresh, float.input = orig_commit, orig_refresh, orig_input
  close_buffer(buf)
end)

h.test('modes: commit confirm with empty opt skips the input float', function()
  local cli = require('gitbutler.cli')
  local status = require('gitbutler.ui.status')
  local float = require('gitbutler.ui.float')
  local captured
  local orig_commit_empty, orig_refresh, orig_input = cli.commit_empty, status.refresh, float.input
  cli.commit_empty = function(target, cb)
    captured = target
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

  h.assert_eq('feat', captured.branch, 'empty commits reach the same target through commit_empty')

  cli.commit_empty, status.refresh, float.input = orig_commit_empty, orig_refresh, orig_input
  close_buffer(buf)
end)

h.test('modes: move confirm sends every source in one cli.move call and refreshes', function()
  local cli = require('gitbutler.cli')
  local status = require('gitbutler.ui.status')
  local captured
  local refreshed = false
  local orig_move, orig_refresh = cli.move, status.refresh
  cli.move = function(sources, target, cb)
    h.assert_eq('normal', modes.current(), 'mode must exit before the CLI call')
    captured = { sources = sources, target = target }
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

  h.assert_eq(2, #captured.sources)
  h.assert_eq('aa', captured.sources[1])
  h.assert_eq('ab', captured.sources[2])
  h.assert_eq('cd', captured.target.below, 'default (below) anchors below the target')
  h.assert_falsy(captured.target.above)
  h.assert_truthy(refreshed, 'refresh after move')
  h.assert_falsy(buf.mode_filter, 'mode_filter cleared on exit')

  cli.move, status.refresh = orig_move, orig_refresh
  close_buffer(buf)
end)

h.test('modes: squash confirm issues one cli.squash call with every source', function()
  local cli = require('gitbutler.cli')
  local status = require('gitbutler.ui.status')
  local calls = {}
  local refreshed = false
  local orig_squash, orig_refresh = cli.squash, status.refresh
  cli.squash = function(sources, target, cb)
    h.assert_eq('normal', modes.current(), 'mode must exit before the CLI call runs')
    table.insert(calls, { sources = sources, target = target })
    cb(nil, {})
  end
  status.refresh = function()
    refreshed = true
  end

  local buf = mode_buffer({
    { selectable = true, type = 'commit', data = { cli_id = 'aa', branch_name = 'feat' } },
    { selectable = true, type = 'commit', data = { cli_id = 'ab', branch_name = 'feat' } },
    { selectable = true, type = 'commit', data = { cli_id = 'cd', branch_name = 'feat' } },
  })
  modes.enter_verb(buf, 'squash', { kind = 'commit', ids = { 'aa', 'ab' }, rows = { 1, 2 }, label = 'x' })
  vim.api.nvim_win_set_cursor(buf.win, { 3, 0 })
  modes._verb_confirm(buf)

  h.assert_eq(1, #calls, 'every source rides in a single squash call')
  h.assert_eq('cd', calls[1].target)
  h.assert_eq(2, #calls[1].sources)
  h.assert_eq('aa', calls[1].sources[1])
  h.assert_eq('ab', calls[1].sources[2])
  h.assert_truthy(refreshed, 'refresh after the call completes')
  h.assert_falsy(buf.mode_filter, 'mode_filter cleared on exit')

  cli.squash, status.refresh = orig_squash, orig_refresh
  close_buffer(buf)
end)

h.test('modes: verb confirm makes no call when the target row has no CLI id', function()
  local cli = require('gitbutler.cli')
  local called = false
  local warned
  local orig_amend, orig_notify = cli.amend, vim.notify
  cli.amend = function()
    called = true
  end
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.notify = function(msg, level)
    if level == vim.log.levels.WARN then
      warned = msg
    end
  end

  local buf = mode_buffer({
    { selectable = true, type = 'file', data = { cli_id = 'aa' } },
    { selectable = true, type = 'commit', data = {} },
  })
  modes.enter_verb(buf, 'amend', { kind = 'file', ids = { 'aa' }, rows = { 1 }, label = 'x' })
  vim.api.nvim_win_set_cursor(buf.win, { 2, 0 })
  modes._verb_confirm(buf)

  h.assert_falsy(called, 'no CLI call without a target id')
  h.assert_truthy(warned and warned:match('CLI id'), 'the missing id is reported')
  modes.exit(buf)

  cli.amend, vim.notify = orig_amend, orig_notify
  close_buffer(buf)
end)

h.test('modes: verb confirm reports a failed call and still refreshes once', function()
  local cli = require('gitbutler.cli')
  local status = require('gitbutler.ui.status')
  local calls = 0
  local refreshes = 0
  local errored
  local orig_amend, orig_refresh, orig_notify = cli.amend, status.refresh, vim.notify
  cli.amend = function(_, _, cb)
    calls = calls + 1
    cb('boom')
  end
  status.refresh = function()
    refreshes = refreshes + 1
  end
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.notify = function(msg, level)
    if level == vim.log.levels.ERROR then
      errored = msg
    end
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

  modes.enter_verb(buf, 'amend', { kind = 'file', ids = { 'aa', 'ab' }, rows = { 1, 2 }, label = 'x' })
  modes._verb_confirm(buf)

  h.assert_eq(1, calls, 'both sources ride in the one call, error or not')
  h.assert_eq(1, refreshes, 'refresh still called exactly once')
  h.assert_truthy(errored and errored:match('boom'), 'the failure is surfaced, not swallowed')
  h.assert_truthy(errored and errored:match('amend'), 'the failing verb is named')

  cli.amend, status.refresh, vim.notify = orig_amend, orig_refresh, orig_notify
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

h.test('modes: details pane keys stay bound while a mode is active', function()
  local buf = require('gitbutler.ui.buffer').Buffer.new()
  buf.buf = vim.api.nvim_create_buf(false, true)
  buf.lines = {}

  modes.apply_keymap(buf, 'amend')
  local bound = {}
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf.buf, 'n')) do
    bound[m.lhs] = true
  end
  -- Without these, `+`/`-` fall through to Vim's line motions and move the
  -- cursor outside the mode's selection bookkeeping.
  for _, key in ipairs({ 'l', '+', '-', 'd', 'D' }) do
    h.assert_truthy(bound[key], key .. ' is not bound inside amend mode')
  end

  modes.apply_keymap(buf, 'normal')
  pcall(vim.api.nvim_buf_delete, buf.buf, { force = true })
end)

h.test('modes: entering with zero valid targets warns and does not enter', function()
  local warned
  local orig_notify = vim.notify
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.notify = function(msg, level)
    if level == vim.log.levels.WARN then
      warned = msg
    end
  end

  local buf = h.mock_buffer()
  buf.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf.buf, 0, -1, false, { 'a' })
  buf.win = vim.api.nvim_open_win(buf.buf, true, { relative = 'editor', width = 20, height = 5, row = 0, col = 0 })
  -- Only the source row exists, so there is no commit or branch to amend onto.
  buf.lines = { { selectable = true, type = 'file', data = { cli_id = 'aa' } } }

  local entered = modes.enter_verb(buf, 'amend', { kind = 'file', ids = { 'aa' }, rows = { 1 }, label = 'x' })

  vim.notify = orig_notify
  h.assert_falsy(entered, 'enter reports the abort')
  h.assert_truthy(warned, 'WARN notify fired')
  h.assert_eq('normal', modes.current(), 'mode not entered')
  h.assert_falsy(buf.mode_filter, 'mode_filter cleared')
  h.assert_eq(0, #vim.api.nvim_buf_get_extmarks(buf.buf, modes.ns, 0, -1, {}), 'no overlays left behind')

  vim.api.nvim_win_close(buf.win, true)
  vim.api.nvim_buf_delete(buf.buf, { force = true })
end)

h.test('modes: enter_verb refuses a source kind the verb cannot take', function()
  local warned
  local orig_notify = vim.notify
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.notify = function(msg, level)
    if level == vim.log.levels.WARN then
      warned = msg
    end
  end

  local buf = h.mock_buffer()
  buf.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf.buf, 0, -1, false, { 'a', 'b' })
  buf.win = vim.api.nvim_open_win(buf.buf, true, { relative = 'editor', width = 20, height = 5, row = 0, col = 0 })
  buf.lines = {
    { selectable = true, type = 'commit', data = { cli_id = 'aa' } },
    { selectable = true, type = 'commit', data = { cli_id = 'cd' } },
  }

  -- A commit can be squashed but never amended: `amend -t <commit> <commit>`
  -- is not an operation, so the mode must not open at all.
  local entered = modes.enter_verb(buf, 'amend', { kind = 'commit', ids = { 'aa' }, rows = { 1 }, label = 'x' })

  vim.notify = orig_notify
  h.assert_falsy(entered, 'enter_verb reports the refusal')
  h.assert_truthy(warned and warned:match('amend'), 'the refused verb is named')
  h.assert_eq('normal', modes.current(), 'mode not entered')
  h.assert_falsy(buf.mode_filter, 'no target filter installed')

  vim.api.nvim_win_close(buf.win, true)
  vim.api.nvim_buf_delete(buf.buf, { force = true })
end)

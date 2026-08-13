local cli = require('gitbutler.cli')
local config = require('gitbutler.config')
local h = require('tests.gitbutler.helpers')
local test, assert_eq, assert_truthy, assert_falsy = h.test, h.assert_eq, h.assert_truthy, h.assert_falsy

print('\n=== cli argument-construction tests ===')

-- The convenience wrappers are the churny surface: a wrong flag, a dropped
-- positional, or a mis-built target flag silently issues the wrong `but`
-- command. These stub M.run and assert the exact arg list each wrapper builds,
-- which is also exactly what reaches the process.

---Capture the args a wrapper passes to M.run. Restores M.run after.
---@param invoke fun() calls the wrapper under test
---@return string[] args
local function capture(invoke)
  local captured
  local orig = cli.run
  cli.run = function(args)
    captured = args
  end
  invoke()
  cli.run = orig
  return captured or {}
end

local function contains_seq(args, seq)
  for i = 1, #args - #seq + 1 do
    local match = true
    for j = 1, #seq do
      if args[i + j - 1] ~= seq[j] then
        match = false
        break
      end
    end
    if match then
      return true
    end
  end
  return false
end

local noop = function() end

test('status: status --json -f -v', function()
  assert_eq(
    table.concat({ 'status', '--json', '-f', '-v' }, ' '),
    table.concat(
      capture(function()
        cli.status(noop)
      end),
      ' '
    )
  )
end)

test('commit: --branch target + message + per-file ids in order, --json last', function()
  local args = capture(function()
    cli.commit({ branch = 'feat' }, 'msg', noop, { 'aa', 'bb' })
  end)
  assert_eq('commit --branch feat -m msg aa bb --json', table.concat(args, ' '))
end)

test('commit: omits the target flag and change ids when not given', function()
  local args = capture(function()
    cli.commit(nil, 'just a message', noop)
  end)
  assert_eq('commit -m just a message --json', table.concat(args, ' '))
  assert_falsy(contains_seq(args, { '--branch' }), 'no --branch without a target')
  assert_falsy(contains_seq(args, { '--unstack' }), 'no --unstack without a target')
end)

-- Load-bearing: without -m, but opens $EDITOR — inside the async job that is a
-- hung process with no terminal to type into.
test('commit: a nil message becomes --no-message, never left to the CLI', function()
  local args = capture(function()
    cli.commit({ branch = 'feat' }, nil, noop)
  end)
  assert_eq('commit --branch feat --no-message --json', table.concat(args, ' '))
  assert_falsy(contains_seq(args, { '-m' }), 'no -m without a message')
end)

test('commit: --above anchor (above = newer in display)', function()
  local args = capture(function()
    cli.commit({ above = 'c3' }, 'msg', noop)
  end)
  assert_eq('commit --above c3 -m msg --json', table.concat(args, ' '))
end)

test('commit: --below anchor (below = older in display)', function()
  local args = capture(function()
    cli.commit({ below = 'c3' }, 'msg', noop)
  end)
  assert_eq('commit --below c3 -m msg --json', table.concat(args, ' '))
end)

test('commit_empty: anchors on --above', function()
  assert_eq(
    'commit --empty --no-message --above br --json',
    table.concat(
      capture(function()
        cli.commit_empty({ above = 'br' }, noop)
      end),
      ' '
    )
  )
end)

test('move: --above places the source newer than the anchor', function()
  local args = capture(function()
    cli.move({ 'c1' }, { above = 'c2' }, noop)
  end)
  assert_eq('move c1 --above c2 --json', table.concat(args, ' '))
end)

test('move: --below places the source older than the anchor', function()
  local args = capture(function()
    cli.move({ 'c1' }, { below = 'c2' }, noop)
  end)
  assert_eq('move c1 --below c2 --json', table.concat(args, ' '))
end)

test('move: --branch targets a branch by name', function()
  local args = capture(function()
    cli.move({ 'c1' }, { branch = 'feat' }, noop)
  end)
  assert_eq('move c1 --branch feat --json', table.concat(args, ' '))
end)

test('move: --unstack takes no value', function()
  local args = capture(function()
    cli.move({ 'c1' }, { unstack = true }, noop)
  end)
  assert_eq('move c1 --unstack --json', table.concat(args, ' '))
end)

test('move: multiple sources are separate argv items, not comma-joined', function()
  local args = capture(function()
    cli.move({ 'c1', 'c2' }, { branch = 'br' }, noop)
  end)
  assert_eq('move c1 c2 --branch br --json', table.concat(args, ' '))
  assert_falsy(contains_seq(args, { 'c1,c2' }), 'sources must not be comma-joined')
end)

test('amend: -t target then the source ids', function()
  local args = capture(function()
    cli.amend('c1', { 'aa', 'bb' }, noop)
  end)
  assert_eq('amend -t c1 aa bb --json', table.concat(args, ' '))
end)

test('amend: no sources means all of zz', function()
  local args = capture(function()
    cli.amend('c1', nil, noop)
  end)
  assert_eq('amend -t c1 --json', table.concat(args, ' '))
end)

test('uncommit: every source in one call', function()
  assert_eq(
    'uncommit c1 c2 --json',
    table.concat(
      capture(function()
        cli.uncommit({ 'c1', 'c2' }, noop)
      end),
      ' '
    )
  )
end)

-- One call for the whole selection, so one undoable oplog entry.
test('discard: every id in one call', function()
  assert_eq(
    'discard xw:1 xw:2 --json',
    table.concat(
      capture(function()
        cli.discard({ 'xw:1', 'xw:2' }, noop)
      end),
      ' '
    )
  )
end)

test('diff_json: includes the id when given', function()
  assert_eq(
    'diff xw:1 --json',
    table.concat(
      capture(function()
        cli.diff_json('xw:1', noop)
      end),
      ' '
    )
  )
end)

test('diff_json: omits the id for the whole worktree', function()
  assert_eq(
    'diff --json',
    table.concat(
      capture(function()
        cli.diff_json(nil, noop)
      end),
      ' '
    )
  )
end)

test('push: omits branch when nil (pushes all)', function()
  assert_eq(
    'push --json',
    table.concat(
      capture(function()
        cli.push(nil, noop)
      end),
      ' '
    )
  )
end)

test('push: includes the branch when given', function()
  assert_eq(
    'push --json feat',
    table.concat(
      capture(function()
        cli.push('feat', noop)
      end),
      ' '
    )
  )
end)

-- `-u` is mandatory, not cosmetic: without a message flag but opens an editor,
-- which inside the async job hangs with nothing to type into.
test('squash: a single source into -t target, keeping the target message', function()
  local args = capture(function()
    cli.squash({ 'c1' }, 'c2', noop)
  end)
  assert_eq('squash -t c2 -u c1 --json', table.concat(args, ' '))
end)

test('squash: a list of sources into -t target', function()
  local args = capture(function()
    cli.squash({ 'c1', 'c2', 'c3' }, 'br', noop)
  end)
  assert_eq('squash -t br -u c1 c2 c3 --json', table.concat(args, ' '))
  assert_truthy(contains_seq(args, { '-u' }), 'never leaves the message to an editor')
end)

test('unapply: no -f (the flag is gone in 0.22)', function()
  local args = capture(function()
    cli.unapply('br', noop)
  end)
  assert_eq('unapply br --json', table.concat(args, ' '))
  assert_falsy(contains_seq(args, { '-f' }), '-f is not a but 0.22 unapply flag')
end)

test('land: passes --yes so it never blocks on a prompt', function()
  assert_eq(
    'land br --yes --json',
    table.concat(
      capture(function()
        cli.land('br', noop)
      end),
      ' '
    )
  )
end)

test('pr_new: -m carries the message', function()
  assert_eq(
    'pr new br -m title body --json',
    table.concat(
      capture(function()
        cli.pr_new('br', 'title body', noop)
      end),
      ' '
    )
  )
end)

test('reword: target then -m message', function()
  assert_eq(
    'reword c1 -m new msg --json',
    table.concat(
      capture(function()
        cli.reword('c1', 'new msg', noop)
      end),
      ' '
    )
  )
end)

test('oplog_snapshot: -m only when a message is given', function()
  assert_eq(
    'oplog snapshot --json',
    table.concat(
      capture(function()
        cli.oplog_snapshot(nil, noop)
      end),
      ' '
    )
  )
  assert_eq(
    'oplog snapshot --json -m wip',
    table.concat(
      capture(function()
        cli.oplog_snapshot('wip', noop)
      end),
      ' '
    )
  )
end)

-- The 0.22 cutover is load-bearing: a CLI still advertising `--format` predates
-- the surface this plugin speaks, so cli.lua probes `status --help` once and
-- refuses outright rather than issuing retired syntax. Exercise both verdicts
-- through run_sync by stubbing vim.system and inspecting what reaches it.

---Stub vim.system for a synchronous run. Returns the last captured non-probe
---cmd (nil when nothing was spawned); the `status --help` capability probe is
---answered from `help`.
local function with_system(exit, invoke, help)
  local captured_cmd
  local orig = vim.system
  vim.system = function(cmd, _opts)
    local is_probe = cmd[#cmd] == '--help'
    if not is_probe then
      captured_cmd = cmd
    end
    return {
      wait = function()
        return is_probe and { code = 0, stdout = help or '' } or exit
      end,
    }
  end
  cli.supported = nil
  local err, res = invoke()
  vim.system = orig
  cli.supported = nil
  return captured_cmd, err, res
end

test('run_sync: passes --json through on 0.22 CLIs and prepends the cmd', function()
  local cmd = with_system({ code = 0, stdout = '{}' }, function()
    return cli.run_sync({ 'status', '--json' })
  end, '      --json\n          Output detailed information as JSON')
  assert_eq(config.values.cmd, cmd[1])
  assert_truthy(contains_seq(cmd, { '--json' }), 'boolean json flag kept')
  assert_falsy(contains_seq(cmd, { '--format=json' }), 'args must reach but verbatim')
end)

test('run_sync: refuses a pre-0.22 CLI without spawning the command', function()
  local cmd, err = with_system({ code = 0, stdout = '{}' }, function()
    return cli.run_sync({ 'status', '--json' })
  end, '      --format <FORMAT>  Output format')
  assert_eq(nil, cmd)
  assert_truthy(err and err:find(cli.MIN_VERSION, 1, true), 'error names the minimum version')
end)

test('run_sync: decodes JSON stdout on success', function()
  local _, err, res = with_system({ code = 0, stdout = '{"behind":3}' }, function()
    return cli.run_sync({ 'status' })
  end)
  assert_eq(nil, err)
  assert_eq(3, res.behind)
end)

test('run_sync: returns raw stdout when it is not JSON', function()
  local _, err, res = with_system({ code = 0, stdout = 'not json at all' }, function()
    return cli.run_sync({ 'diff' })
  end)
  assert_eq(nil, err)
  assert_eq('not json at all', res)
end)

test('run_sync: surfaces stderr as the error on a non-zero exit', function()
  local _, err = with_system({ code = 1, stderr = 'branch is protected' }, function()
    return cli.run_sync({ 'push', 'br' })
  end)
  assert_eq('branch is protected', err)
end)

test('run_sync: synthesises a message when a failure has no stderr', function()
  local _, err = with_system({ code = 2, stderr = '' }, function()
    return cli.run_sync({ 'push' })
  end)
  assert_eq('but exited with code 2', err)
end)

-- M.run is the async production path. Simulate vim.system's streaming stdout +
-- on_exit contract, then drain the vim.schedule the callback runs inside.
local function run_async(exit, chunks, args)
  cli.supported = true -- pre-seed so no synchronous capability probe runs
  local orig = vim.system
  vim.system = function(_cmd, opts, on_exit)
    for _, c in ipairs(chunks or {}) do
      opts.stdout(nil, c)
    end
    on_exit(exit)
    return { wait = function() end }
  end
  local done, got_err, got_res = false, nil, nil
  cli.run(args, function(err, res)
    done, got_err, got_res = true, err, res
  end)
  vim.wait(1000, function()
    return done
  end, 10)
  vim.system = orig
  return done, got_err, got_res
end

test('run: async success decodes the streamed JSON chunks', function()
  local done, err, res = run_async({ code = 0 }, { '{"a":', '42}' }, { 'status', '--json' })
  assert_truthy(done, 'callback fired')
  assert_eq(nil, err)
  assert_eq(42, res.a)
end)

test('run: async failure surfaces streamed stderr', function()
  cli.supported = true -- pre-seed so no synchronous capability probe runs
  local orig = vim.system
  vim.system = function(_cmd, opts, on_exit)
    opts.stderr(nil, 'boom')
    on_exit({ code = 1 })
    return { wait = function() end }
  end
  local done, err
  cli.run({ 'push', 'br', '--json' }, function(e)
    done, err = true, e
  end)
  vim.wait(1000, function()
    return done
  end, 10)
  vim.system = orig
  assert_truthy(done)
  assert_eq('boom', err)
end)

test('missing binary routes error through the callback, not a throw', function()
  local old_cmd = config.values.cmd
  config.values.cmd = 'definitely-not-but-9000'
  cli.supported = nil
  local got_err
  local ok = pcall(cli.status, function(err)
    got_err = err
  end)
  assert_truthy(ok, 'cli.status must not throw on a missing binary')
  assert_truthy(got_err and got_err:find('cannot run', 1, true), 'callback got the cannot-run error')

  cli.supported = nil
  local sync_err = cli.run_sync({ 'status', '--json' })
  assert_truthy(sync_err and sync_err:find('cannot run', 1, true), 'run_sync returned the cannot-run error')

  config.values.cmd = old_cmd
  cli.supported = nil
  cli.unusable = nil
end)

test('run: spawn failure after a cached probe reaches the callback', function()
  local old_cmd = config.values.cmd
  cli.supported = true -- pretend the probe passed, then the binary vanished
  config.values.cmd = 'definitely-not-but-9000'
  local got_err
  local ok = pcall(cli.run, { 'status', '--json' }, function(err)
    got_err = err
  end)
  assert_truthy(ok, 'cli.run must not throw when the spawn fails')
  assert_truthy(got_err and got_err:find('cannot run', 1, true), 'callback got the spawn error')
  config.values.cmd = old_cmd
  cli.supported = nil
end)

test('run: refuses a pre-0.22 CLI without spawning the command', function()
  cli.supported = false
  local orig = vim.system
  local spawned = false
  vim.system = function()
    spawned = true
    return { wait = function() end }
  end
  local done, err
  cli.run({ 'status', '--json' }, function(e)
    done, err = true, e
  end)
  vim.system = orig
  cli.supported = nil
  assert_falsy(spawned, 'nothing spawned on an unsupported CLI')
  assert_truthy(done, 'callback fired')
  assert_truthy(err and err:find(cli.MIN_VERSION, 1, true), 'callback got the unsupported error')
end)

local cli = require('gitbutler.cli')
local config = require('gitbutler.config')
local h = require('tests.gitbutler.helpers')
local test, assert_eq, assert_truthy, assert_falsy = h.test, h.assert_eq, h.assert_truthy, h.assert_falsy

print('\n=== cli argument-construction tests ===')

-- The convenience wrappers are the churny surface: a wrong flag, a dropped
-- positional, or a mis-ordered `-p` loop silently issues the wrong `but`
-- command. These stub M.run and assert the exact arg list each wrapper builds
-- (the literal `--json` token, before normalise_args rewrites it).

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

test('commit: branch + create + message + per-file ids in order, --json last', function()
  local args = capture(function()
    cli.commit('feat', 'msg', noop, { 'aa', 'bb' }, true)
  end)
  assert_eq('commit feat -c -m msg -p aa -p bb --json', table.concat(args, ' '))
end)

test('commit: omits branch, -c, and -p when not given', function()
  local args = capture(function()
    cli.commit(nil, 'just a message', noop)
  end)
  assert_eq('commit -m just a message --json', table.concat(args, ' '))
  assert_falsy(contains_seq(args, { '-c' }), 'no -c without create')
  assert_falsy(contains_seq(args, { '-p' }), 'no -p without file ids')
end)

test('commit_at: --after anchor (above = newer in display)', function()
  local args = capture(function()
    cli.commit_at('feat', 'msg', { after = 'c3' }, noop)
  end)
  assert_eq('commit feat -m msg --after c3 --json', table.concat(args, ' '))
end)

test('commit_at: --before anchor (below)', function()
  local args = capture(function()
    cli.commit_at('feat', 'msg', { before = 'c3' }, noop)
  end)
  assert_eq('commit feat -m msg --before c3 --json', table.concat(args, ' '))
end)

test('commit_empty: anchors on --after', function()
  assert_eq(
    'commit empty --after br --json',
    table.concat(
      capture(function()
        cli.commit_empty({ after = 'br' }, noop)
      end),
      ' '
    )
  )
end)

test('move: bare (no --after) is the default before/below placement', function()
  assert_eq(
    'move c1 c2 --json',
    table.concat(
      capture(function()
        cli.move('c1', 'c2', noop)
      end),
      ' '
    )
  )
end)

test('move: opts.after appends --after before --json', function()
  assert_eq(
    'move c1 c2 --after --json',
    table.concat(
      capture(function()
        cli.move('c1', 'c2', noop, { after = true })
      end),
      ' '
    )
  )
end)

test('move: comma-joined multi-source is passed through verbatim', function()
  assert_eq(
    'move c1,c2 br --json',
    table.concat(
      capture(function()
        cli.move('c1,c2', 'br', noop)
      end),
      ' '
    )
  )
end)

test('rub: source then target', function()
  assert_eq(
    'rub up br --json',
    table.concat(
      capture(function()
        cli.rub('up', 'br', noop)
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

test('squash: a single commit id', function()
  assert_eq(
    'squash --json c1',
    table.concat(
      capture(function()
        cli.squash('c1', noop)
      end),
      ' '
    )
  )
end)

test('squash: a list of commit ids', function()
  assert_eq(
    'squash --json c1 c2 c3',
    table.concat(
      capture(function()
        cli.squash({ 'c1', 'c2', 'c3' }, noop)
      end),
      ' '
    )
  )
end)

test('unapply: forces with -f', function()
  assert_eq(
    'unapply br -f --json',
    table.concat(
      capture(function()
        cli.unapply('br', noop)
      end),
      ' '
    )
  )
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

-- The --json → --format=json translation is load-bearing (the module comment
-- calls it "the only line to update" if the CLI flag changes again). It's a
-- local function, so exercise it through run_sync by stubbing vim.system and
-- inspecting the command that actually reaches the process.

---Stub vim.system for a synchronous run. Returns the captured cmd.
local function with_system(exit, invoke)
  local captured_cmd
  local orig = vim.system
  vim.system = function(cmd, _opts)
    captured_cmd = cmd
    return {
      wait = function()
        return exit
      end,
    }
  end
  local err, res = invoke()
  vim.system = orig
  return captured_cmd, err, res
end

test('run_sync: normalises --json to --format=json and prepends the cmd', function()
  local cmd = with_system({ code = 0, stdout = '{}' }, function()
    return cli.run_sync({ 'status', '--json' })
  end)
  assert_eq(config.values.cmd, cmd[1])
  assert_truthy(contains_seq(cmd, { '--format=json' }), 'json flag translated')
  assert_falsy(contains_seq(cmd, { '--json' }), 'literal --json must not survive')
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

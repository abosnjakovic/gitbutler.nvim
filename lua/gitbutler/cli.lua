local config = require('gitbutler.config')

local M = {}

---Cached support verdict; set nil to force a re-probe (tests, cmd change).
---@type boolean?
M.supported = nil

---Minimum `but` this plugin speaks, and the error shown when it is older.
M.MIN_VERSION = '0.22.0'
local UNSUPPORTED = 'gitbutler.nvim requires but ' .. M.MIN_VERSION .. ' or newer (this one is older)'

---Why the CLI is unusable, when the reason is not the version (missing binary,
---probe timeout). Maintained by the probe; nil means the version message.
---@type string?
M.unusable = nil

---Blocking-call ceilings: a hung probe or sync command must not freeze the
---editor forever. wait(timeout) SIGKILLs the process and returns code 124.
local PROBE_TIMEOUT_MS = 5000
local SYNC_TIMEOUT_MS = 30000

---Whether the CLI speaks the 0.22 surface. 0.22 replaced `--format=json` with a
---boolean `--json` in the same release that retired `but rub` and re-cut
---commit/squash/move, so a CLI still advertising `--format` cannot run any of
---our mutations. Probe the help text once — cheaper and steadier than parsing
---version numbers — and say so plainly instead of letting every action fail on
---retired syntax.
---@return boolean
local function supported()
  if M.supported == nil then
    -- vim.system throws on a missing/non-executable cmd instead of returning a
    -- code; catch it so :Butler* commands report via vim.notify, not a stacktrace.
    local ok, res = pcall(function()
      return vim.system({ config.values.cmd, 'status', '--help' }, { text = true }):wait(PROBE_TIMEOUT_MS)
    end)
    if not ok then
      M.unusable = ("gitbutler.nvim cannot run '%s' (%s) — install but or point config cmd at it"):format(
        config.values.cmd,
        res
      )
      M.supported = false
    elseif res.code == 124 and res.signal == 9 then
      M.unusable = ("gitbutler.nvim: '%s status --help' timed out after %dms"):format(
        config.values.cmd,
        PROBE_TIMEOUT_MS
      )
      M.supported = false
    else
      local help = (res.stdout or '') .. (res.stderr or '')
      M.supported = not help:find('--format', 1, true)
      M.unusable = nil
    end
  end
  return M.supported
end

---Append the single targeting flag for `target`. but accepts exactly one per
---invocation, so the first field present wins.
---@param args string[]
---@param target { branch?: string, above?: string, below?: string, unstack?: boolean }
local function append_target(args, target)
  if target.unstack then
    table.insert(args, '--unstack')
  elseif target.branch then
    vim.list_extend(args, { '--branch', target.branch })
  elseif target.above then
    vim.list_extend(args, { '--above', target.above })
  elseif target.below then
    vim.list_extend(args, { '--below', target.below })
  end
end

---Run a but CLI command asynchronously.
---@param args string[] Command arguments (e.g. {"status", "--json", "-f", "-v"})
---@param opts? {cwd?: string, on_stdout?: fun(data: string), raw?: boolean}
---@param callback fun(err?: string, result?: any) Called with decoded JSON or raw stdout
---@overload fun(args: string[], callback: fun(err?: string, result?: any))
function M.run(args, opts, callback)
  if type(opts) == 'function' then
    callback = opts
    opts = {}
  end
  opts = opts or {}

  if not supported() then
    callback(M.unusable or UNSUPPORTED)
    return
  end

  local cmd = vim.list_extend({ config.values.cmd }, args)
  local stdout_chunks = {}
  local stderr_chunks = {}

  -- Spawn can still throw (binary removed after the cached probe, bad cwd) —
  -- route it into the callback like every other failure.
  local spawn_ok, spawn_err = pcall(vim.system, cmd, {
    cwd = opts.cwd,
    stdout = function(_, data)
      if data then
        table.insert(stdout_chunks, data)
        if opts.on_stdout then
          opts.on_stdout(data)
        end
      end
    end,
    stderr = function(_, data)
      if data then
        table.insert(stderr_chunks, data)
      end
    end,
  }, function(result)
    vim.schedule(function()
      local stdout = table.concat(stdout_chunks)
      local stderr = table.concat(stderr_chunks)

      if result.code ~= 0 then
        local msg = stderr ~= '' and stderr or ('but exited with code ' .. result.code)
        callback(vim.trim(msg))
        return
      end

      if opts.raw then
        callback(nil, stdout)
        return
      end

      -- Try JSON decode
      local ok, decoded = pcall(vim.json.decode, stdout)
      if ok then
        callback(nil, decoded)
      else
        -- Not JSON — return raw string (some commands don't output JSON)
        callback(nil, stdout)
      end
    end)
  end)
  if not spawn_ok then
    callback(("cannot run '%s' (%s)"):format(config.values.cmd, spawn_err))
  end
end

---Run a but CLI command synchronously (blocking). Use sparingly.
---@param args string[]
---@param opts? {cwd?: string}
---@return string? err
---@return any result
function M.run_sync(args, opts)
  opts = opts or {}
  if not supported() then
    return M.unusable or UNSUPPORTED, nil
  end
  local cmd = vim.list_extend({ config.values.cmd }, args)
  local spawned, result = pcall(function()
    return vim.system(cmd, { cwd = opts.cwd, text = true }):wait(SYNC_TIMEOUT_MS)
  end)
  if not spawned then
    return ("cannot run '%s' (%s)"):format(config.values.cmd, result), nil
  end
  if result.code == 124 and result.signal == 9 then
    return ('but timed out after %dms'):format(SYNC_TIMEOUT_MS), nil
  end

  if result.code ~= 0 then
    local msg = (result.stderr and result.stderr ~= '') and result.stderr or ('but exited with code ' .. result.code)
    return vim.trim(msg), nil
  end

  local stdout = result.stdout or ''
  local ok, decoded = pcall(vim.json.decode, stdout)
  if ok then
    return nil, decoded
  end
  return nil, stdout
end

---Convenience: but status --json -f -v
function M.status(callback)
  M.run({ 'status', '--json', '-f', '-v' }, callback)
end

---Convenience: but commit <target flag> [-m <message>] [<changes>...]
---@param target { branch?: string, above?: string, below?: string } Where the
---commit lands. A named branch is created if it does not exist; an empty table
---lets but place the commit on the only applied stack.
---@param message? string Commit message. Omitted means `--no-message`: never
---leave it to the CLI, which would spawn $EDITOR inside the async job and hang.
---@param callback fun(err?: string, result?: any)
---@param change_ids? string[] Uncommitted file/hunk CLI IDs (omit for all changes)
function M.commit(target, message, callback, change_ids)
  local args = { 'commit' }
  append_target(args, target or {})
  if message then
    vim.list_extend(args, { '-m', message })
  else
    table.insert(args, '--no-message')
  end
  vim.list_extend(args, change_ids or {})
  table.insert(args, '--json')
  M.run(args, callback)
end

---Convenience: but absorb
function M.absorb(callback)
  M.run({ 'absorb', '--json' }, callback)
end

---Convenience: but push
function M.push(branch, callback)
  local args = { 'push', '--json' }
  if branch then
    table.insert(args, branch)
  end
  M.run(args, callback)
end

---Convenience: but branch new
function M.branch_new(name, callback)
  M.run({ 'branch', 'new', name, '--json' }, callback)
end

---Convenience: but branch (list)
function M.branch_list(callback)
  M.run({ 'branch', '--json' }, callback)
end

---Convenience: but undo
function M.undo(callback)
  M.run({ 'undo', '--json' }, callback)
end

---Convenience: but redo
function M.redo(callback)
  M.run({ 'redo', '--json' }, callback)
end

---Convenience: but reword
function M.reword(target, message, callback)
  M.run({ 'reword', target, '-m', message, '--json' }, callback)
end

---Convenience: but squash -t <target> -u <sources>...
---`-u` (--use-target-message) is not optional for us: squashing commits or
---branches without a message flag makes but open an editor, which cannot work
---inside an async job. Keeping the target's message is also what the old
---`but rub` did implicitly.
---@param sources string[] Commit, branch or committed-file CLI IDs
---@param target string Commit or branch to squash into
---@param callback fun(err?: string, result?: any)
function M.squash(sources, target, callback)
  local args = { 'squash', '-t', target, '-u' }
  vim.list_extend(args, sources)
  table.insert(args, '--json')
  M.run(args, callback)
end

---Convenience: but pull
function M.pull(callback)
  M.run({ 'pull', '--json' }, callback)
end

---Convenience: but move <sources>... --above/--below/--branch/--unstack
---@param sources string[] Commit, committed-file or single-branch CLI IDs
---@param target { above?: string, below?: string, branch?: string, unstack?: boolean }
---@param callback fun(err?: string, result?: any)
function M.move(sources, target, callback)
  local args = { 'move' }
  vim.list_extend(args, sources)
  append_target(args, target)
  table.insert(args, '--json')
  M.run(args, callback)
end

---Convenience: but commit --empty --no-message <target flag>
---@param target { branch?: string, above?: string, below?: string } Where the commit lands
---@param callback fun(err?: string, result?: any)
function M.commit_empty(target, callback)
  local args = { 'commit', '--empty', '--no-message' }
  append_target(args, target)
  table.insert(args, '--json')
  M.run(args, callback)
end

---Convenience: but amend -t <target> [<sources>...]
---@param target string Commit or branch to amend into (branch = its tip)
---@param sources? string[] Uncommitted file/hunk CLI IDs; omit to amend all of zz
---@param callback fun(err?: string, result?: any)
function M.amend(target, sources, callback)
  local args = { 'amend', '-t', target }
  vim.list_extend(args, sources or {})
  table.insert(args, '--json')
  M.run(args, callback)
end

---Convenience: but uncommit <sources>...
---@param sources string[] Commit or committed-file CLI IDs
---@param callback fun(err?: string, result?: any)
function M.uncommit(sources, callback)
  local args = { 'uncommit' }
  vim.list_extend(args, sources)
  table.insert(args, '--json')
  M.run(args, callback)
end

---Convenience: but diff [<cli_id>] --json. Omit the id for the whole worktree.
---@param cli_id? string
---@param callback fun(err?: string, result?: any)
function M.diff_json(cli_id, callback)
  local args = { 'diff' }
  if cli_id then
    table.insert(args, cli_id)
  end
  table.insert(args, '--json')
  M.run(args, callback)
end

---Convenience: but discard <changes>... — one call, so one undoable oplog
---entry for the whole selection.
---@param ids string[] Branch/commit/file/hunk CLI IDs, all of the same kind
---@param callback fun(err?: string, result?: any)
function M.discard(ids, callback)
  local args = { 'discard' }
  vim.list_extend(args, ids)
  table.insert(args, '--json')
  M.run(args, callback)
end

---Convenience: but apply
function M.apply(branch_name, callback)
  M.run({ 'apply', branch_name, '--json' }, callback)
end

---Convenience: but unapply
function M.unapply(identifier, callback)
  M.run({ 'unapply', identifier, '--json' }, callback)
end

---Convenience: but branch delete
function M.branch_delete(branch_name, callback)
  M.run({ 'branch', 'delete', branch_name, '--json' }, callback)
end

---Convenience: but branch show
function M.branch_show(branch_name, callback)
  M.run({ 'branch', 'show', branch_name, '--json' }, callback)
end

---Convenience: but show <branch> (commit log for a branch)
function M.show(branch_name, callback)
  M.run({ 'show', branch_name, '--json' }, callback)
end

---Convenience: but oplog list
function M.oplog_list(callback)
  M.run({ 'oplog', 'list', '--json' }, callback)
end

---Convenience: but oplog restore
function M.oplog_restore(snapshot_id, callback)
  M.run({ 'oplog', 'restore', snapshot_id, '--json' }, callback)
end

---Convenience: but oplog snapshot
function M.oplog_snapshot(message, callback)
  local args = { 'oplog', 'snapshot', '--json' }
  if message then
    vim.list_extend(args, { '-m', message })
  end
  M.run(args, callback)
end

---Convenience: but pr new <branch> -m <message>
---@param branch string Branch name or CLI ID
---@param message string PR title + body (first line = title)
---@param callback fun(err?: string, result?: any)
function M.pr_new(branch, message, callback)
  M.run({ 'pr', 'new', branch, '-m', message, '--json' }, callback)
end

---Convenience: but pr set-draft <branch>
function M.pr_set_draft(branch, callback)
  M.run({ 'pr', 'set-draft', branch, '--json' }, callback)
end

---Convenience: but pr set-ready <branch>
function M.pr_set_ready(branch, callback)
  M.run({ 'pr', 'set-ready', branch, '--json' }, callback)
end

---Convenience: but pr auto-merge <branch>
function M.pr_auto_merge(branch, callback)
  M.run({ 'pr', 'auto-merge', branch, '--json' }, callback)
end

---Convenience: but land (land a branch directly onto the target branch).
---Fast-forwards the target to the branch tip when possible (else a merge
---commit), pushes to the remote, and reconciles remaining applied branches —
---the whole "just push to the target" workflow in one call. Silent on success.
---@param branch string Branch name or CLI ID to land
---@param callback fun(err?: string, result?: any)
function M.land(branch, callback)
  M.run({ 'land', branch, '--yes', '--json' }, callback)
end

---Convenience: but clean (remove empty branches from workspace)
function M.clean(callback)
  M.run({ 'clean', '--json' }, callback)
end

return M

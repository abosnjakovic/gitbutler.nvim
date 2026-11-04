local config = require('gitbutler.config')

local M = {}

---Cached support verdict; set nil to force a re-probe (tests, cmd change).
---@type boolean?
M.supported = nil

---Minimum `but` this plugin speaks, and the error shown when it is older.
M.MIN_VERSION = '0.23.0'
local UNSUPPORTED = 'gitbutler.nvim requires but ' .. M.MIN_VERSION .. ' or newer (this one is older)'

---Why the CLI is unusable, when the reason is not the version (missing binary,
---probe timeout). Maintained by the probe; nil means the version message.
---@type string?
M.unusable = nil

---Blocking-call ceilings: a hung probe or sync command must not freeze the
---editor forever. wait(timeout) SIGKILLs the process and returns code 124.
local PROBE_TIMEOUT_MS = 5000
local SYNC_TIMEOUT_MS = 30000

---Whether the CLI speaks the 0.23 surface. 0.23 added worktrees — a section of
---the status payload this plugin renders — and renamed `land` to `merge`, so a
---CLI without `but worktree` cannot be driven from here. Probe that subcommand
---once (it answers outside a repository too) rather than parsing version
---numbers, and say so plainly instead of letting every action fail on retired
---syntax.
---@return boolean
local function supported()
  if M.supported == nil then
    -- vim.system throws on a missing/non-executable cmd instead of returning a
    -- code; catch it so :Butler* commands report via vim.notify, not a stacktrace.
    local ok, res = pcall(function()
      return vim.system({ config.values.cmd, 'worktree', '--help' }, { text = true }):wait(PROBE_TIMEOUT_MS)
    end)
    if not ok then
      M.unusable = ("gitbutler.nvim cannot run '%s' (%s) — install but or point config cmd at it"):format(
        config.values.cmd,
        res
      )
      M.supported = false
    elseif res.code == 124 and res.signal == 9 then
      M.unusable = ("gitbutler.nvim: '%s worktree --help' timed out after %dms"):format(
        config.values.cmd,
        PROBE_TIMEOUT_MS
      )
      M.supported = false
    else
      M.supported = res.code == 0
      M.unusable = nil
    end
  end
  return M.supported
end

---Append the single targeting flag for `target`, checked in the order unstack,
---branch, above, below; the first present wins. `but` accepts one flag per
---invocation. Newer but also lets `--branch` name the branch that
---`--above`/`--below` creates; this still sends one flag.
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

---Convenience: but worktree list — `{ active = [...], archived = [...] }`,
---each entry `{ id, name, refName, path, updatedAtMs }`.
function M.worktree_list(callback)
  M.run({ 'worktree', 'list', '--json' }, callback)
end

---Convenience: but worktree new [name] — a linked checkout on `name`, created
---at the workspace base when that branch does not exist yet. `but` picks the
---directory (under `~/.gitbutler-worktrees/<repo>/`) and copies anything
---listed in `.worktreeinclude`.
---@param name? string branch to check out; omit for a generated one
---@param callback fun(err?: string, result?: any)
function M.worktree_new(name, callback)
  local args = { 'worktree', 'new' }
  if name and name ~= '' then
    table.insert(args, name)
  end
  table.insert(args, '--json')
  M.run(args, callback)
end

---Convenience: but worktree archive <worktree> — hide it from the workspace,
---leaving the directory and its branch alone.
function M.worktree_archive(name, callback)
  M.run({ 'worktree', 'archive', name, '--json' }, callback)
end

---Convenience: but worktree unarchive <worktree>
function M.worktree_unarchive(name, callback)
  M.run({ 'worktree', 'unarchive', name, '--json' }, callback)
end

---Convenience: but worktree remove <worktree> [--force] — delete the
---directory, keeping the branch it had checked out. Without `--force` but
---refuses a worktree with uncommitted changes.
---@param name string
---@param force boolean discard the worktree's uncommitted changes
---@param callback fun(err?: string, result?: any)
function M.worktree_remove(name, force, callback)
  local args = { 'worktree', 'remove', name }
  if force then
    table.insert(args, '--force')
  end
  table.insert(args, '--json')
  M.run(args, callback)
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

---Convenience: but move <sources>... --above/--below/--branch/--unstack [-m <message>]
---@param sources string[] Commit, committed-file or single-branch CLI IDs
---@param target { above?: string, below?: string, branch?: string, unstack?: boolean }
---@param callback fun(err?: string, result?: any)
---@param message? string Committed-file sources only: the new commit's message;
---nil or '' sends none
function M.move(sources, target, callback, message)
  local args = { 'move' }
  vim.list_extend(args, sources)
  append_target(args, target)
  if message and message ~= '' then
    vim.list_extend(args, { '-m', message })
  end
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
---@param sources? string[] Uncommitted file/hunk CLI IDs; omit to amend the whole uncommitted area
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

---Convenience: but split <sources>... [-m <message>] — move committed files into
---a new commit directly above their source commit.
---@param sources string[] Committed-file CLI IDs; but takes them from one commit
---@param message string Message for the new commit; '' leaves it empty
---@param callback fun(err?: string, result?: any)
function M.split(sources, message, callback)
  local args = { 'split' }
  vim.list_extend(args, sources)
  if message ~= '' then
    vim.list_extend(args, { '-m', message })
  end
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

---Hunk CLI IDs in one commit's diff, in the order `but diff` prints them.
---
---`but diff <commit> --json` (checked on 0.23.2) carries no per-hunk id, while
---`but diff <uncommitted>` does — yet the ids exist, and every mutation takes
---them: `but discard oqko:rlnq:5604` and `but squash -t … oqko:nkns:940e` both
---work. The human output is where they are published, one per file-and-hunk
---header box: ` oqko:nkns:940e M a.txt │`.
---
---ponytail: parsing output this plugin otherwise never reads. Delete it, and
---its caller in details.lua, once `--json` carries the ids.
---@param text string `but diff <commit>` output
---@return { id: string, path: string }[]
function M._parse_hunk_ids(text)
  local out = {}
  for line in tostring(text):gmatch('[^\n]+') do
    -- commit:file:hunk — three segments, so an uncommitted `klvn:a3b4` header
    -- (two) never matches.
    local id, path = line:match('^%s*(%S+:%S+:%S+)%s+%a%s+(.-)%s*│%s*$')
    if id and path ~= '' then
      table.insert(out, { id = id, path = path })
    end
  end
  return out
end

---Convenience: but diff <cli_id>, read for its hunk ids (see `_parse_hunk_ids`).
---@param cli_id string commit or committed-file CLI id
---@param callback fun(err?: string, ids?: { id: string, path: string }[])
function M.diff_hunk_ids(cli_id, callback)
  M.run({ 'diff', cli_id }, { raw = true }, function(err, text)
    if err then
      callback(err)
      return
    end
    callback(nil, M._parse_hunk_ids(text or ''))
  end)
end

---Convenience: but discard <changes>... — one call, so one undoable oplog
---entry for the whole selection. An empty list calls back with an error and
---runs nothing.
---@param ids string[] Branch/commit/file/hunk CLI IDs, all of the same kind
---@param callback fun(err?: string, result?: any)
function M.discard(ids, callback)
  -- A bare `but discard` discards every uncommitted change (0.22.1+).
  if #ids == 0 then
    callback('nothing to discard: no ids given')
    return
  end
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

---Convenience: but merge (merge a branch directly onto the target branch).
---Fast-forwards the target to the branch tip when possible (else a merge
---commit), pushes to the remote when the target has one, and reconciles
---remaining applied branches — the whole "just push to the target" workflow in
---one call. Silent on success. It also deletes the branch's remote copy, only
---when the target contains the branch tip; a failed delete only warns.
---@param branch string Branch name or CLI ID to merge
---@param callback fun(err?: string, result?: any)
function M.merge(branch, callback)
  M.run({ 'merge', branch, '--yes', '--json' }, callback)
end

---Convenience: but clean (remove empty branches from workspace)
function M.clean(callback)
  M.run({ 'clean', '--json' }, callback)
end

return M

local config = require('gitbutler.config')

local M = {}

---Run a but CLI command asynchronously.
---@param args string[] Command arguments (e.g. {"status", "--json", "-f", "-v"})
---@param opts? {cwd?: string, on_stdout?: fun(data: string), raw?: boolean}
---@param callback fun(err?: string, result?: any) Called with decoded JSON or raw stdout
function M.run(args, opts, callback)
  if type(opts) == 'function' then
    callback = opts
    opts = {}
  end
  opts = opts or {}

  local cmd = vim.list_extend({ config.values.cmd }, args)
  local stdout_chunks = {}
  local stderr_chunks = {}

  vim.system(cmd, {
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
end

---Run a but CLI command synchronously (blocking). Use sparingly.
---@param args string[]
---@param opts? {cwd?: string}
---@return string? err
---@return any result
function M.run_sync(args, opts)
  opts = opts or {}
  local cmd = vim.list_extend({ config.values.cmd }, args)
  local result = vim.system(cmd, { cwd = opts.cwd, text = true }):wait()

  if result.code ~= 0 then
    local msg = (result.stderr and result.stderr ~= '') and result.stderr
      or ('but exited with code ' .. result.code)
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

---Convenience: but commit
function M.commit(branch, message, callback)
  local args = { 'commit' }
  if branch then
    table.insert(args, branch)
  end
  if message then
    vim.list_extend(args, { '-m', message })
  end
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

---Convenience: but reword
function M.reword(target, message, callback)
  M.run({ 'reword', target, '-m', message, '--json' }, callback)
end

---Convenience: but squash (accepts single commit string or list of commit strings)
function M.squash(commits, callback)
  local args = { 'squash', '--json' }
  if type(commits) == 'table' then
    for _, c in ipairs(commits) do
      table.insert(args, c)
    end
  elseif commits then
    table.insert(args, commits)
  end
  M.run(args, callback)
end

---Convenience: but stage
function M.stage(file, branch, callback)
  M.run({ 'stage', file, branch, '--json' }, callback)
end

---Convenience: but pull
function M.pull(callback)
  M.run({ 'pull', '--json' }, callback)
end

---Convenience: but pr
function M.pr(callback)
  M.run({ 'pr', '--json' }, callback)
end

---Convenience: but move
function M.move(commit, target_branch, callback)
  M.run({ 'move', commit, target_branch, '--json' }, callback)
end

---Convenience: but uncommit
function M.uncommit(commit, callback)
  local args = { 'uncommit', '--json' }
  if commit then
    table.insert(args, commit)
  end
  M.run(args, callback)
end

---Convenience: but discard
function M.discard(id, callback)
  M.run({ 'discard', id, '--json' }, callback)
end

---Convenience: but apply
function M.apply(branch_name, callback)
  M.run({ 'apply', branch_name, '--json' }, callback)
end

---Convenience: but unapply
function M.unapply(identifier, callback)
  M.run({ 'unapply', identifier, '-f', '--json' }, callback)
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

return M

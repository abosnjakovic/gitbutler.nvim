-- Headless git-log helpers for the landed-history section rendered inline in
-- the status view (below the common base). This module used to drive a
-- standalone `T` timeline window; that view was folded into the main graph, so
-- only the pure parse/fetch helpers remain.
local M = {}

---Parse the structured output of git log --format='%H|%h|%an|%ad|%D|%s'.
---The message field may itself contain pipe characters, so we split on the first 5 pipes only.
---@param raw string Raw git log output
---@return table[] commits Array of {sha, short_sha, author, date, refs, message}
function M.parse_git_log(raw)
  local commits = {}
  for line in raw:gmatch('[^\n]+') do
    local parts = {}
    local rest = line
    for _ = 1, 5 do
      local pos = rest:find('|', 1, true)
      if not pos then
        break
      end
      table.insert(parts, rest:sub(1, pos - 1))
      rest = rest:sub(pos + 1)
    end
    if #parts == 5 then
      table.insert(commits, {
        sha = parts[1],
        short_sha = parts[2],
        author = parts[3],
        date = parts[4],
        refs = parts[5],
        message = rest,
      })
    end
  end
  return commits
end

---Parse the output of git diff-tree --name-status.
---Each line looks like: "M\tsrc/auth.lua"
---@param raw string Raw diff-tree --name-status output
---@return table[] files Array of {path, status}
function M.parse_diff_tree(raw)
  local files = {}
  for line in raw:gmatch('[^\n]+') do
    local status, path = line:match('^(%a)%s+(.+)')
    if status and path then
      table.insert(files, { path = path, status = status })
    end
  end
  return files
end

---Fetch the linear landed history below `base_sha` (its ancestors, newest
---first), excluding the base commit itself. Async.
---@param base_sha string Common-base commit SHA
---@param limit integer Max commits to return
---@param callback fun(commits: table[])
function M.fetch_base(base_sha, limit, callback)
  vim.system({
    'git',
    'log',
    '--skip=1', -- the base commit itself is already shown as the (common base) row
    '--date=short',
    '--format=%H|%h|%an|%ad|%D|%s',
    '-n',
    tostring(limit),
    base_sha,
  }, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        callback({})
        return
      end
      callback(M.parse_git_log(result.stdout or ''))
    end)
  end)
end

---Fetch file changes for a commit (sync, fast for a single commit).
---@param sha string Full commit SHA
---@return table[] files Array of {path, status}
function M.fetch_files(sha)
  local result = vim
    .system({ 'git', 'diff-tree', '--no-commit-id', '-r', '--name-status', sha }, { text = true })
    :wait()
  if result.code ~= 0 or not result.stdout then
    return {}
  end
  return M.parse_diff_tree(result.stdout)
end

---Fetch the full commit message body for a commit (sync).
---Returns body lines (subject stripped, leading/trailing blanks trimmed).
---@param sha string Full commit SHA
---@return string[] body_lines
function M.fetch_body(sha)
  local result = vim.system({ 'git', 'log', '-1', '--format=%B', sha }, { text = true }):wait()
  if result.code ~= 0 or not result.stdout then
    return {}
  end
  local parts = vim.split(result.stdout, '\n', { plain = true })
  table.remove(parts, 1)
  while #parts > 0 and parts[#parts]:match('^%s*$') do
    table.remove(parts)
  end
  while #parts > 0 and parts[1]:match('^%s*$') do
    table.remove(parts, 1)
  end
  return parts
end

return M

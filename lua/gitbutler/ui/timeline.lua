local config = require('gitbutler.config')
local buffer_mod = require('gitbutler.ui.buffer')

local M = {}

---@type GitButlerBuffer?
M.instance = nil

---Parse the structured output of git log --all --format='%H|%h|%an|%ad|%D|%s'.
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
      if not pos then break end
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

---Parse the output of git diff-tree --stat.
---Each file line looks like: " src/auth.lua | 15 +++---"
---The summary line ("N files changed, ...") is skipped.
---@param raw string Raw diff-tree --stat output
---@return table[] files Array of {path}
function M.parse_diff_tree(raw)
  local files = {}
  for line in raw:gmatch('[^\n]+') do
    -- Skip summary line
    if line:find('files? changed') then goto continue end
    local path = line:match('^%s*(.-)%s*|')
    if path then
      table.insert(files, { path = path })
    end
    ::continue::
  end
  return files
end

return M

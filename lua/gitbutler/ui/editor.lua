-- Jump-to-code: open a worktree file in a reusable editor window with the
-- cursor on a target line, keeping the TUI (status view + optional details
-- pane) visible. This is the capability that makes the plugin worth running
-- inside Neovim rather than shelling out to `but tui`.

local M = {}

---Tracked editor window, reused across jumps so repeated opens don't stack new
---splits. A new session (or a closed window) recreates it on the next jump.
---@type integer?
M.win = nil

---First changed hunk's new-file line from a decoded `but diff` payload, or nil.
---Pure: walks changes in order, returns the first hunk's `newStart`.
---@param data any decoded `but diff <id> --json`
---@return integer? line
function M.first_hunk_line(data)
  if type(data) ~= 'table' or type(data.changes) ~= 'table' then
    return nil
  end
  for _, change in ipairs(data.changes) do
    local diff = type(change.diff) == 'table' and change.diff or nil
    local hunks = diff and type(diff.hunks) == 'table' and diff.hunks or nil
    if hunks and hunks[1] then
      return tonumber(hunks[1].newStart)
    end
  end
  return nil
end

local function window_valid(win)
  return win ~= nil and vim.api.nvim_win_is_valid(win)
end

---Return the reusable editor window, creating a bottom split on first use so
---the TUI stays visible above it.
---@return integer win
local function ensure_win()
  if window_valid(M.win) then
    return M.win
  end
  vim.cmd('botright split')
  M.win = vim.api.nvim_get_current_win()
  vim.wo[M.win].winfixheight = false
  pcall(vim.api.nvim_win_set_height, M.win, math.max(10, math.floor(vim.o.lines * 0.4)))
  return M.win
end

---Open `path` in the editor window with the cursor on `line` (1-based),
---centred. Focuses the editor window. No-op on an empty path.
---@param path string worktree-relative or absolute path
---@param line? integer 1-based line to land on (defaults to 1)
function M.open(path, line)
  if type(path) ~= 'string' or path == '' then
    return
  end
  local win = ensure_win()
  vim.api.nvim_set_current_win(win)
  vim.cmd('edit ' .. vim.fn.fnameescape(path))
  local count = vim.api.nvim_buf_line_count(0)
  local target = math.max(1, math.min(line or 1, count))
  pcall(vim.api.nvim_win_set_cursor, win, { target, 0 })
  vim.cmd('normal! zz')
end

return M

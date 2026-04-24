local M = {}

local HELP = { '?', 'Help' }

local hints = {
  status = {
    default = { HELP, { 'r', 'Refresh' }, { 'q', 'Close' } },
    branch = { HELP, { '<Tab>', 'Fold' }, { 'l', 'Log' }, { 'p', 'Push' }, { '<Space>', 'Select' } },
    commit = { HELP, { 'd', 'Reword' }, { 'S', 'Squash' }, { 'U', 'Uncommit' }, { 'm', 'Move' }, { '<Space>', 'Select' } },
    committed_file = { HELP, { '<CR>', 'Open' }, { '<Tab>', 'Diff' }, { 'x', 'Discard' }, { '<Space>', 'Select' } },
    file = { HELP, { '<CR>', 'Open' }, { 's', 'Assign' }, { 'a', 'Absorb' }, { 'c', 'Commit' }, { 'x', 'Discard' }, { '<Space>', 'Select' } },
    recent_commit = { HELP, { '<CR>', 'Show' } },
  },
  log = {
    default = { HELP, { 'r', 'Refresh' }, { 'q', 'Close' } },
    commit = { HELP, { 'd', 'Reword' }, { 'S', 'Squash' }, { '<Tab>', 'Expand' } },
    log_file = { HELP, { '<Tab>', 'Diff' }, { '<CR>', 'Open' } },
  },
  timeline = {
    default = { HELP, { 'r', 'Refresh' }, { 'q', 'Close' } },
    timeline_commit = { HELP, { 'y', 'Yank SHA' }, { 'l', 'Log' }, { '<Tab>', 'Expand' } },
    timeline_file = { HELP, { '<CR>', 'Open' } },
  },
}

local function format(items)
  local parts = {}
  local key_ranges = {}
  local col = 0
  for i, item in ipairs(items) do
    if i > 1 then
      table.insert(parts, '  ')
      col = col + 2
    end
    local key = item[1]
    table.insert(key_ranges, { col, col + #key })
    table.insert(parts, key)
    col = col + #key
    table.insert(parts, ' ' .. item[2])
    col = col + 1 + #item[2]
  end
  return table.concat(parts, ''), key_ranges
end

---Resolve hint text for a view + line type.
---@param view string|nil
---@param line_type string|nil
---@param selectable boolean|nil whether <Space> Select should be included
---@return string text, table key_ranges 0-indexed byte ranges {col_start, col_end}
function M.for_context(view, line_type, selectable)
  local view_hints = view and hints[view] or hints.status
  local items = view_hints[line_type] or view_hints.default
  if not selectable then
    local filtered = {}
    for _, item in ipairs(items) do
      if item[1] ~= '<Space>' then table.insert(filtered, item) end
    end
    items = filtered
  end
  return format(items)
end

return M

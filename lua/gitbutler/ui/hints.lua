local M = {}

local HELP = { '?', 'Help' }

local hints = {
  status = {
    default = { HELP, { '<C-r>', 'Refresh' }, { 'q', 'Close' } },
    commit = { HELP, { '<Tab>', 'Files' }, { 'd', 'Details' }, { 'a', 'Amend' }, { 'y', 'Yank SHA' } },
    merge_base = { HELP, { '<Tab>', 'Expand' }, { 'd', 'Details' } },
    base_commit = { HELP, { '<Tab>', 'Expand' }, { 'd', 'Details' }, { 'o', 'Diff' }, { 'y', 'Yank SHA' } },
    base_more = { HELP, { '<Tab>', 'Load more' } },
  },
  log = {
    default = { HELP, { 'r', 'Refresh' }, { 'q', 'Close' } },
    commit = { HELP, { 'd', 'Reword' }, { 'S', 'Squash' }, { '<Tab>', 'Expand' } },
    log_file = { HELP, { '<Tab>', 'Diff' }, { '<CR>', 'Open' } },
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

---Whether a view/row-type has a curated per-row-type entry (as opposed to
---needing the registry fallback). `buffer.lua` uses this to decide which
---renderer to use — the width-aware hotbar is the right one for a
---registry-derived line, since those can run long.
---@param view string|nil
---@param line_type string|nil
---@return boolean
function M.has_entry(view, line_type)
  local view_hints = view and hints[view]
  return view_hints ~= nil and (view_hints[line_type] or view_hints.default) ~= nil
end

---Resolve hint text for a view + line type.
---
---A per-row-type entry wins: it can say what `<Tab>` means on this particular
---row, which a per-context list cannot. Absent one, the view's own registry
---entries are used. Falling back to the status view's hints, as this used to,
---is what made the CI view and the details pane advertise keys they do not bind.
---@param view string|nil
---@param line_type string|nil
---@param selectable boolean|nil whether <Space> Select should be included
---@return string text, table key_ranges 0-indexed byte ranges {col_start, col_end}
function M.for_context(view, line_type, selectable)
  local items
  if M.has_entry(view, line_type) then
    local view_hints = hints[view]
    items = view_hints[line_type] or view_hints.default
  else
    items = {}
    for _, spec in ipairs(require('gitbutler.keys').resolved(view or 'status')) do
      table.insert(items, { spec.key, spec.desc })
    end
  end
  if not selectable then
    local filtered = {}
    for _, item in ipairs(items) do
      if item[1] ~= '<Space>' then
        table.insert(filtered, item)
      end
    end
    items = filtered
  end
  return format(items)
end

return M

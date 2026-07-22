local M = {}

---Hotbar items for normal mode: {key, description, keep?}.
---`keep = true` items survive width truncation (dropped last).
M.normal_items = {
  { 'j', 'down' },
  { 'k', 'up' },
  { 'space', 'mark' },
  { 'r', 'rub' },
  { 'c', 'commit' },
  { 'm', 'move' },
  { 's', 'stack' },
  { 't', 'branch' },
  { '/', 'jump' },
  { 'x', 'discard' },
  { 'u', 'undo' },
  { 'p', 'push' },
  { 'v', 'pr' },
  { 'i', 'pull' },
  { 'L', 'land' },
  { 'O', 'oplog' },
  { '?', 'help', keep = true },
  { 'q', 'quit', keep = true },
}

---Hotbar items for the operation modes.
local MODE_ITEMS = {
  rub = {
    { 'j', 'target' },
    { 'k', 'target' },
    { '<cr>', 'confirm' },
    { 'esc', 'cancel' },
  },
  commit = {
    { '<cr>', 'confirm' },
    { 'a', 'above/below' },
    { 'e', 'empty' },
    { 'esc', 'cancel' },
  },
  move = {
    { '<cr>', 'confirm' },
    { 'a', 'above/below' },
    { 'esc', 'cancel' },
  },
  stack = {
    { 'a', 'apply' },
    { 'u', 'unapply' },
    { 'm', 'move' },
    { 'esc', 'cancel' },
  },
}

---Hotbar items for a mode ('normal', 'rub', 'commit', 'move', 'stack').
---@param mode string
---@return {[1]:string,[2]:string,keep?:boolean}[]
function M.items_for(mode)
  return MODE_ITEMS[mode] or M.normal_items
end

local PILL_HL = {
  rub = 'GitButlerModeRub',
  commit = 'GitButlerModeCommit',
  move = 'GitButlerModeMove',
  stack = 'GitButlerModeStack',
}

---Pill highlight group for a mode.
---@param mode string
---@return string
function M.pill_hl(mode)
  return PILL_HL[mode] or 'GitButlerModeNormal'
end

local SEP = ' • '

---Build the hotbar line for a window width.
---@param mode string mode pill label ('normal', 'rub', …)
---@param items {[1]:string,[2]:string,keep?:boolean}[]
---@param width integer window display width
---@param pill_hl? string highlight group for the mode pill (default GitButlerModeNormal)
---@return { text: string, spans: {[1]:integer,[2]:integer,[3]:string}[] }
function M.build(mode, items, width, pill_hl)
  local pill = ' ' .. mode .. ' '
  local text = pill .. ' '
  local spans = { { 0, #pill, pill_hl or 'GitButlerModeNormal' } }

  local normal, kept = {}, {}
  for _, it in ipairs(items) do
    table.insert(it.keep and kept or normal, it)
  end

  local function append(it, first)
    local sep = first and '' or SEP
    local key_start = #text + #sep
    table.insert(spans, { key_start, key_start + #it[1], 'GitButlerHelpKey' })
    text = text .. sep .. it[1] .. ' ' .. it[2]
  end

  local sep_width = vim.fn.strdisplaywidth(SEP)
  local tail_width = 0
  for i, it in ipairs(kept) do
    tail_width = tail_width + (i > 1 and sep_width or 0) + vim.fn.strdisplaywidth(it[1] .. ' ' .. it[2])
  end

  local first = true
  for _, it in ipairs(normal) do
    local piece = (first and '' or SEP) .. it[1] .. ' ' .. it[2]
    local needed = vim.fn.strdisplaywidth(text .. piece) + sep_width + tail_width
    if needed > width then
      break
    end
    append(it, first)
    first = false
  end
  for _, it in ipairs(kept) do
    append(it, first)
    first = false
  end

  return { text = text, spans = spans }
end

return M

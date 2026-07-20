local M = {}

---Hotbar items for normal mode: {key, description, keep?}.
---`keep = true` items survive width truncation (dropped last).
M.normal_items = {
  { 'j', 'down' },
  { 'k', 'up' },
  { 'space', 'mark' },
  { 'c', 'commit' },
  { 'b', 'branch' },
  { 'x', 'discard' },
  { 'u', 'undo' },
  { 'p', 'push' },
  { 'v', 'pr' },
  { 'i', 'pull' },
  { 'L', 'land' },
  { 'T', 'timeline' },
  { 'O', 'oplog' },
  { '?', 'help', keep = true },
  { 'q', 'quit', keep = true },
}

local SEP = ' • '

---Build the hotbar line for a window width.
---@param mode string mode pill label ('normal')
---@param items {[1]:string,[2]:string,keep?:boolean}[]
---@param width integer window display width
---@return { text: string, spans: {[1]:integer,[2]:integer,[3]:string}[] }
function M.build(mode, items, width)
  local pill = ' ' .. mode .. ' '
  local text = pill .. ' '
  local spans = { { 0, #pill, 'GitButlerModeNormal' } }

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

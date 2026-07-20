local M = {}

local HL = {
  file = 'GitButlerDetailFile',
  hunk = 'GitButlerDetailHunk',
  gutter = 'GitButlerDetailGutter',
  selected = 'GitButlerDetailSelected',
  mark = 'GitButlerMark',
  add = 'DiffAdd',
  del = 'DiffDelete',
  dim = 'GitButlerHelp',
}

---Width the file header rule is padded to.
local HEADER_WIDTH = 44

---`vim.json.decode` maps JSON null to `vim.NIL`, which is truthy, so a bare
---`x or {}` guard doesn't catch it. Use this at every list-iteration site.
local function list(v)
  return type(v) == 'table' and v or {}
end

---Same problem for scalars: `vim.NIL` is truthy userdata, so `x or default`
---lets it through and concatenation then throws.
local function scalar(v, default)
  if v == nil or v == vim.NIL or type(v) == 'userdata' then
    return default
  end
  return v
end

---@class DetailsRow: GitButlerLine

local function row(kind, entity, selectable)
  return { text = '', spans = {}, type = kind, data = entity, selectable = selectable == true, graph = true }
end

local function add(r, txt, hl)
  if hl then
    table.insert(r.spans, { #r.text, #r.text + #txt, hl })
  end
  r.text = r.text .. txt
end

---Leading glyph so every hunk row lines up: ✔︎ when marked, ▌ when selected,
---two spaces otherwise.
local function lead(r, marked, selected)
  if marked then
    add(r, '✔︎', HL.mark)
  elseif selected then
    -- Bar + space: `▌` is one display column, so the trailing space keeps the
    -- selected hunk aligned with the two-space lead of every other row.
    add(r, '▌', HL.selected)
    add(r, ' ')
  else
    add(r, '  ')
  end
end

local function split_lines(s)
  local out = {}
  for line in tostring(scalar(s, '')):gmatch('([^\n]*)\n?') do
    table.insert(out, line)
  end
  -- gmatch's trailing empty match after the final newline is not content.
  while #out > 0 and out[#out] == '' do
    table.remove(out)
  end
  return out
end

local function gutter(old, new)
  return string.format(
    '%s %s │ ',
    old and string.format('%4d', old) or '    ',
    new and string.format('%4d', new) or '    '
  )
end

function M._file_header(path, status)
  local text = '── ' .. scalar(path, '(unknown)') .. ' ' .. scalar(status, '') .. ' '
  local pad = math.max(1, HEADER_WIDTH - vim.fn.strdisplaywidth(text) - 1)
  return text .. string.rep('─', pad) .. '╮'
end

---Build detail rows from decoded `but diff <id> --format=json`.
---@param data table
---@param state? { selected_hunk?: integer, marked?: table<string,boolean> }
---@return DetailsRow[] rows, { id: string, path: string, row: integer, end_row: integer }[] hunks
function M.build(data, state)
  state = state or {}
  local marked = state.marked or {}
  local rows, hunks = {}, {}
  local function push(r)
    table.insert(rows, r)
    return #rows
  end

  -- Group by path, preserving first-seen order.
  -- ponytail: relies on the CLI invariant that each `changes[]` entry is exactly
  -- one hunk, so a multi-hunk file arrives as several entries sharing a path.
  local order, by_path = {}, {}
  for _, change in ipairs(list(type(data) == 'table' and data.changes)) do
    local path = scalar(change.path, '(unknown)')
    if not by_path[path] then
      by_path[path] = { status = change.status, changes = {} }
      table.insert(order, path)
    end
    table.insert(by_path[path].changes, change)
  end

  if #order == 0 then
    local r = row('detail_info', nil, false)
    add(r, '  (no changes)', HL.dim)
    push(r)
    return rows, hunks
  end

  for _, path in ipairs(order) do
    local file = by_path[path]
    local hr = row('detail_file', { path = path }, false)
    add(hr, M._file_header(path, file.status), HL.file)
    push(hr)

    for _, change in ipairs(file.changes) do
      local diff = type(change.diff) == 'table' and change.diff or {}
      local diff_hunks = list(diff.hunks)
      if diff.type ~= 'patch' or #diff_hunks == 0 then
        local r = row('detail_info', { path = path }, false)
        add(r, '  (no text diff: ' .. tostring(diff.type or 'unknown') .. ')', HL.dim)
        push(r)
      else
        for _, hunk in ipairs(diff_hunks) do
          local entity = { cli_id = change.id, path = path }
          local index = #hunks + 1
          local is_selected = state.selected_hunk == index
          local body = split_lines(hunk.diff)

          local head = row('detail_hunk', entity, true)
          lead(head, marked[change.id], is_selected)
          add(head, table.remove(body, 1) or '@@', HL.hunk)
          local head_row = push(head)

          local old, new = tonumber(hunk.oldStart) or 0, tonumber(hunk.newStart) or 0
          local end_row = head_row
          for _, line in ipairs(body) do
            local marker = line:sub(1, 1)
            local r = row('detail_line', entity, false)
            lead(r, false, is_selected)
            if marker == '+' then
              add(r, gutter(nil, new), HL.gutter)
              add(r, line, HL.add)
              new = new + 1
            elseif marker == '-' then
              add(r, gutter(old, nil), HL.gutter)
              add(r, line, HL.del)
              old = old + 1
            else
              add(r, gutter(old, new), HL.gutter)
              add(r, line)
              old, new = old + 1, new + 1
            end
            end_row = push(r)
          end

          table.insert(hunks, { id = change.id, path = path, row = head_row, end_row = end_row })
        end
      end
    end

    local close = row('detail_file', { path = path }, false)
    add(close, string.rep(' ', HEADER_WIDTH - 1) .. '╯', HL.file)
    push(close)
  end

  return rows, hunks
end

return M

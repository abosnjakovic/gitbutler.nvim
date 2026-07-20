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
    -- Two columns like every other lead, or a marked header sits one column
    -- left of its neighbours.
    add(r, '✔︎', HL.mark)
    add(r, ' ')
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
---@return DetailsRow[] rows, { id?: string, path: string, row: integer, end_row: integer }[] hunks
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
          -- Committed diffs carry no `id` — the hunk is still registered so
          -- navigation works; the ops key off `id` and stay unavailable.
          local id = scalar(change.id, nil)
          local entity = { cli_id = id, path = path }
          local index = #hunks + 1
          local is_selected = state.selected_hunk == index
          local body = split_lines(hunk.diff)

          local head = row('detail_hunk', entity, true)
          lead(head, id ~= nil and marked[id], is_selected)
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

          table.insert(hunks, { id = id, path = path, row = head_row, end_row = end_row })
        end
      end
    end

    local close = row('detail_file', { path = path }, false)
    add(close, string.rep(' ', HEADER_WIDTH - 1) .. '╯', HL.file)
    push(close)
  end

  return rows, hunks
end

--- Window controller -------------------------------------------------------

local NS = vim.api.nvim_create_namespace('gitbutler')

---@class DetailsWin
---@field buf? integer scratch buffer
---@field win? integer split window
---@field status_buf? GitButlerBuffer the status view this pane hangs off
---@field full boolean fullscreen (status window hidden)
---@field width_pct integer 30..90
---@field entity? { cli_id: string, kind?: string }
---@field data? table last decoded diff payload
---@field rows? DetailsRow[] last rendered rows
---@field hunks { id?: string, path: string, row: integer, end_row: integer }[]
---@field selected integer 1-based hunk index
---@field marked table<string, boolean>
---@field gen integer diff-request generation; stale responses are dropped
---@field follow? integer follow-the-cursor debounce generation
---@field closing? boolean guards close() against re-entry from its own WinClosed
M.win_state = { full = false, width_pct = 50, selected = 1, marked = {}, hunks = {}, gen = 0 }

---Reset the controller to its just-closed state. `width_pct` is the user's
---setting and survives; `gen` and `follow` must survive too, or a close/reopen
---would rewind them and let a still-in-flight callback pass the staleness
---guard and render its diff under whatever entity is showing by then.
function M._reset_state()
  local prev = M.win_state
  M.win_state = {
    full = false,
    width_pct = prev.width_pct or 50,
    selected = 1,
    marked = {},
    hunks = {},
    gen = prev.gen or 0,
    follow = prev.follow,
  }
end

---@return boolean
function M.is_open()
  local st = M.win_state
  return st.win ~= nil
    and vim.api.nvim_win_is_valid(st.win)
    -- The window may have been reused for some other buffer, in which case it
    -- is the user's window now and not ours to render into or close.
    and st.buf ~= nil
    and vim.api.nvim_win_get_buf(st.win) == st.buf
end

---Write rows (text + spans) into the details buffer. Same contract as
---`Buffer:render` for graph rows, minus the fold/selection decoration the
---details pane has no use for.
---@param rows DetailsRow[]
function M._render(rows)
  local st = M.win_state
  st.rows = rows
  local buf = st.buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)

  local text = {}
  for _, r in ipairs(rows) do
    table.insert(text, r.text)
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, text)

  for i, r in ipairs(rows) do
    for _, s in ipairs(r.spans or {}) do
      vim.api.nvim_buf_add_highlight(buf, NS, s[3], i - 1, s[1], s[2])
    end
  end

  vim.bo[buf].modifiable = false
end

local function info_rows(text, hl)
  return { { text = text, spans = { { 0, #text, hl } }, type = 'detail_info', graph = true, selectable = false } }
end

---ponytail: width is a share of the whole editor rather than of the status
---window's column group — correct for the common one-window-plus-pane layout,
---and the user has `+`/`-` when it isn't.
function M._apply_width()
  local st = M.win_state
  if not M.is_open() or st.full then
    return
  end
  pcall(vim.api.nvim_win_set_width, st.win, math.max(10, math.floor(vim.o.columns * st.width_pct / 100)))
end

--- Hunk cursor ---------------------------------------------------------------

---Neighbouring hunk index in direction `dir`, clamped at both ends.
---@param hunks table[]
---@param current integer
---@param dir integer
---@return integer
function M._next_hunk(hunks, current, dir)
  return math.max(1, math.min(#hunks, (current or 1) + dir))
end

---Buffer row of hunk `index`'s header, or nil when there is no such hunk.
---@return integer?
function M._hunk_row(hunks, index)
  local hunk = hunks[index]
  return hunk and hunk.row or nil
end

---Index of the hunk owning buffer row `row`; nil for file headers, closers and
---any other row outside every hunk's range.
---@return integer?
function M._hunk_at(hunks, at)
  for i, hunk in ipairs(hunks) do
    if at >= hunk.row and at <= hunk.end_row then
      return i
    end
  end
  return nil
end

---Re-render from the diff payload already in hand — selection and marks are
---render-time state, so changing them never needs another CLI call.
function M._rebuild()
  local st = M.win_state
  if not st.data then
    return
  end
  local rows, hunks = M.build(st.data, { selected_hunk = st.selected, marked = st.marked })
  st.hunks = hunks
  M._render(rows)
end

---Select hunk `index` (clamped), redraw the `▌` bar and park the cursor on the
---hunk header, which scrolls it into view.
---@param index integer
function M._select_hunk(index)
  local st = M.win_state
  if #st.hunks == 0 then
    return
  end
  st.selected = math.max(1, math.min(#st.hunks, index))
  M._rebuild()
  local head = M._hunk_row(st.hunks, st.selected)
  if head and M.is_open() then
    pcall(vim.api.nvim_win_set_cursor, st.win, { head, 0 })
  end
end

---CursorMoved hook: snap the selection to the hunk under the cursor.
---
---Loop-safe without a guard flag: it compares the owning hunk against the
---current selection and returns when they match. Our own `_rebuild` +
---`nvim_win_set_cursor` leave the cursor inside the hunk that is already
---selected, so the CursorMoved they fire finds nothing to change.
function M._sync_cursor()
  local st = M.win_state
  if not M.is_open() then
    return
  end
  local index = M._hunk_at(st.hunks, vim.api.nvim_win_get_cursor(st.win)[1])
  if not index or index == st.selected then
    return
  end
  st.selected = index
  M._rebuild()
end

---Focus the status window, if it is still there.
function M._focus_status()
  local sb = M.win_state.status_buf
  if sb and sb.win and vim.api.nvim_win_is_valid(sb.win) then
    pcall(vim.api.nvim_set_current_win, sb.win)
  end
end

--- Hunk operations ----------------------------------------------------------

---Hunks the next operation applies to: every marked hunk, else the selected
---one. Driven off `st.hunks` rather than the `marked` table so ids left over
---from a previous entity can never leak into a command.
---@return string[] ids, string[] paths
function M._targets()
  local st = M.win_state
  local ids, paths = {}, {}
  for _, hunk in ipairs(st.hunks) do
    if hunk.id and st.marked[hunk.id] then
      table.insert(ids, hunk.id)
      table.insert(paths, hunk.path)
    end
  end
  if #ids == 0 then
    local hunk = st.hunks[st.selected]
    if hunk and hunk.id then
      ids, paths = { hunk.id }, { hunk.path }
    end
  end
  return ids, paths
end

---Committed diffs have no hunk ids, so no hunk op can address them.
local function warn_no_ids()
  vim.notify('gitbutler: this diff has no hunk ids (committed diffs are read-only here)', vim.log.levels.WARN)
end

---Toggle the mark on the selected hunk. A hunk with no id (committed diff)
---cannot be marked — and must not be used as a table key.
function M._toggle_mark()
  local st = M.win_state
  local hunk = st.hunks[st.selected]
  if not hunk or not hunk.id then
    return
  end
  st.marked[hunk.id] = (not st.marked[hunk.id]) and true or nil
  M._rebuild()
end

---Distinct paths, first-seen order.
local function uniq(paths)
  local seen, out = {}, {}
  for _, p in ipairs(paths) do
    if not seen[p] then
      seen[p], out[#out + 1] = true, p
    end
  end
  return out
end

---`x` — discard the marked hunks (or the selected one) after a confirmation.
function M._hunk_discard()
  local st = M.win_state
  local ids, paths = M._targets()
  if #ids == 0 then
    warn_no_ids()
    return
  end
  local prompt = string.format('Discard %d hunk(s) in %s?', #ids, table.concat(uniq(paths), ', '))

  vim.ui.select({ 'Yes', 'No' }, { prompt = prompt }, function(choice)
    if choice ~= 'Yes' then
      return
    end
    local entity = st.entity
    ---@param ok boolean whole chain succeeded
    local function finish(ok)
      require('gitbutler.ui.status').refresh()
      -- A partial failure keeps the marks so the user can retry the rest; the
      -- undiscarded hunks keep their ids in the reloaded diff.
      local keep = ok and {} or M.win_state.marked
      -- The diff we are showing just changed, so `show`'s same-entity no-op
      -- has to be defeated before asking for it again.
      M.win_state.entity = nil
      if entity then
        M.show(entity) -- clears marks itself: they are per-diff
      end
      M.win_state.marked = keep
    end

    local cli = require('gitbutler.cli')
    local i = 0
    local function discard_next()
      i = i + 1
      if i > #ids then
        vim.notify('gitbutler: discarded ' .. #ids .. ' hunk(s)', vim.log.levels.INFO)
        finish(true)
        return
      end
      cli.discard(ids[i], function(err)
        if err then
          vim.notify('gitbutler discard: ' .. err, vim.log.levels.ERROR)
          finish(false)
          return
        end
        discard_next()
      end)
    end
    discard_next()
  end)
end

---Hunk body text with the lead and gutter stripped, keeping the `+`/`-`/space
---diff marker so the result pastes as a patch body.
---@param rows DetailsRow[]
---@param hunk? { row: integer, end_row: integer }
---@return string?
function M._hunk_copy_text(rows, hunk)
  if not hunk then
    return nil
  end
  local out = {}
  for i = hunk.row + 1, hunk.end_row do
    local text = rows[i] and rows[i].text
    if text then
      -- Non-greedy: the gutter's `│ ` is the first one on the row, any later
      -- one belongs to the file's own content.
      table.insert(out, text:match('^.-│ (.*)$') or text)
    end
  end
  if #out == 0 then
    return nil
  end
  return table.concat(out, '\n')
end

---`y` — copy the selected hunk's body to the `+` and unnamed registers.
function M._hunk_copy()
  local st = M.win_state
  local text = M._hunk_copy_text(st.rows or {}, st.hunks[st.selected])
  if not text then
    vim.notify('gitbutler: nothing to copy on this hunk', vim.log.levels.WARN)
    return
  end
  vim.fn.setreg('+', text)
  vim.fn.setreg('"', text)
  vim.notify('gitbutler: copied ' .. #text .. ' bytes of hunk', vim.log.levels.INFO)
end

---`r` — enter rub mode on the status buffer with the hunks as source. `kind`
---is 'file': the rub verb matrix treats a hunk exactly like an uncommitted
---file, and the source rows live in the other window so `rows` stays empty.
function M._hunk_rub()
  local st = M.win_state
  local ids, paths = M._targets()
  if #ids == 0 then
    warn_no_ids()
    return
  end
  local sb = st.status_buf
  if not sb or not (sb.win and vim.api.nvim_win_is_valid(sb.win)) then
    vim.notify('gitbutler: no status window to rub onto', vim.log.levels.WARN)
    return
  end
  M._focus_status()
  require('gitbutler.ui.modes').enter_rub(sb, {
    kind = 'file',
    ids = ids,
    rows = {},
    label = paths[1] .. (#ids > 1 and (' +' .. (#ids - 1)) or ''),
  })
end

---Scroll the pane by `count` lines without moving the cursor relative to the
---text: <C-e> (0x05) down, <C-y> (0x19) up.
local function scroll(count, key)
  local st = M.win_state
  if M.is_open() then
    vim.api.nvim_win_call(st.win, function()
      vim.cmd('normal! ' .. count .. key)
    end)
  end
end

---Buffer-local keymap for the details pane. `q` closes the pane only — unlike
---the status window's `q`, which closes the whole view. Matches upstream.
---@param buf integer
local function set_keymap(buf)
  local function step(dir)
    return function()
      M._select_hunk(M._next_hunk(M.win_state.hunks, M.win_state.selected, dir))
    end
  end
  local keys = {
    ['j'] = step(1),
    ['k'] = step(-1),
    ['<Down>'] = step(1),
    ['<Up>'] = step(-1),
    ['g'] = function()
      M._select_hunk(1)
    end,
    ['G'] = function()
      M._select_hunk(#M.win_state.hunks)
    end,
    ['J'] = function()
      scroll(1, '\5')
    end,
    ['K'] = function()
      scroll(1, '\25')
    end,
    ['<C-d>'] = function()
      scroll(10, '\5')
    end,
    ['<C-u>'] = function()
      scroll(10, '\25')
    end,
    ['<Space>'] = M._toggle_mark,
    ['x'] = M._hunk_discard,
    ['y'] = M._hunk_copy,
    ['r'] = M._hunk_rub,
    ['h'] = M._focus_status,
    ['<Left>'] = M._focus_status,
    ['<Esc>'] = M._focus_status,
    ['d'] = M.close,
    ['q'] = M.close,
    ['D'] = function()
      M.toggle_full(M.win_state.status_buf)
    end,
    ['+'] = function()
      M.resize(5)
    end,
    ['-'] = function()
      M.resize(-5)
    end,
    ['?'] = function()
      require('gitbutler.actions').help(M.win_state.status_buf)
    end,
  }
  for key, fn in pairs(keys) do
    vim.keymap.set('n', key, fn, { buffer = buf, nowait = true, silent = true })
  end
end

---@param status_buf GitButlerBuffer
function M.open(status_buf)
  local st = M.win_state
  st.status_buf = status_buf or st.status_buf
  if M.is_open() then
    return
  end

  local src = status_buf and status_buf.win
  if not src or not vim.api.nvim_win_is_valid(src) then
    return
  end

  vim.api.nvim_set_current_win(src)
  vim.cmd('rightbelow vsplit')
  local win = vim.api.nvim_get_current_win()

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'gitbutler-details'
  vim.api.nvim_win_set_buf(win, buf)

  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = 'no'
  vim.wo[win].foldcolumn = '0'
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true

  st.buf, st.win = buf, win
  M._render(info_rows('  (no selection)', HL.dim))
  M._apply_width()
  set_keymap(buf)

  vim.api.nvim_create_autocmd('CursorMoved', {
    buffer = buf,
    callback = function()
      M._sync_cursor()
    end,
  })

  -- The window going away by any route (`:q`, `<C-w>c`, a layout change) runs
  -- the full teardown, so a hidden status window always comes back and no
  -- stale `full`/`win` survives into the next open. Deferred: creating the
  -- restore split from inside WinClosed is not allowed.
  vim.api.nvim_create_autocmd('WinClosed', {
    pattern = tostring(win),
    once = true,
    callback = function()
      vim.schedule(function()
        -- Only if this is still the live pane: a programmatic close (or a
        -- close-then-reopen) has already moved on, and tearing down the
        -- current pane on a dead window's event would be wrong.
        if M.win_state.win == win then
          M.close()
        end
      end)
    end,
  })

  vim.api.nvim_set_current_win(src)
  M.show_for_line(status_buf:get_cursor_line())
end

---Close the status window without wiping its buffer, so fullscreen can put it
---back. `:only` would take unrelated user windows with it — never use it.
---@return boolean hidden
function M._hide_status()
  local sb = M.win_state.status_buf
  if not sb or not sb.win or not vim.api.nvim_win_is_valid(sb.win) then
    return false
  end
  local hidden = sb.buf and vim.api.nvim_buf_is_valid(sb.buf)
  if hidden then
    vim.bo[sb.buf].bufhidden = 'hide'
  end
  local ok = pcall(vim.api.nvim_win_close, sb.win, false)
  if ok then
    sb.win = nil
  elseif hidden then
    -- The close failed, so nothing is hiding: put the buffer's own teardown
    -- back rather than stranding it at 'hide' forever.
    vim.bo[sb.buf].bufhidden = 'wipe'
  end
  return ok
end

---Put the hidden status window back to the left of the details pane.
function M._restore_status()
  local sb = M.win_state.status_buf
  if not sb or not sb.buf or not vim.api.nvim_buf_is_valid(sb.buf) then
    return
  end
  -- Anchor the restored split on the details window when it is still there; if
  -- it was closed out from under us, split whatever window is current instead.
  -- Bailing out here would strand the status buffer at bufhidden = 'hide'.
  if M.is_open() then
    vim.api.nvim_set_current_win(M.win_state.win)
  end
  vim.cmd('leftabove vsplit')
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, sb.buf)
  vim.bo[sb.buf].bufhidden = 'wipe'
  sb.win = win
  M._apply_width()
end

function M.close()
  local st = M.win_state
  -- The window close below fires our own WinClosed handler; `closing` keeps
  -- that from re-running the teardown mid-flight.
  if st.closing then
    return
  end
  st.closing = true
  if st.full then
    st.full = false
    M._restore_status()
  end
  local focus = st.status_buf and st.status_buf.win
  if st.win and vim.api.nvim_win_is_valid(st.win) then
    pcall(vim.api.nvim_win_close, st.win, true)
  end
  if st.buf and vim.api.nvim_buf_is_valid(st.buf) then
    pcall(vim.api.nvim_buf_delete, st.buf, { force = true })
  end
  M._reset_state()
  if focus and vim.api.nvim_win_is_valid(focus) then
    pcall(vim.api.nvim_set_current_win, focus)
  end
end

---@param status_buf GitButlerBuffer
function M.toggle(status_buf)
  if M.is_open() then
    M.close()
  else
    M.open(status_buf)
  end
end

---@param status_buf GitButlerBuffer
function M.toggle_full(status_buf)
  if not M.is_open() then
    M.open(status_buf)
    if not M.is_open() then
      return
    end
  end
  local st = M.win_state
  if st.full then
    st.full = false
    M._restore_status()
    if st.status_buf and st.status_buf.win and vim.api.nvim_win_is_valid(st.status_buf.win) then
      pcall(vim.api.nvim_set_current_win, st.status_buf.win)
    end
  elseif M._hide_status() then
    st.full = true
  end
end

---@param delta integer percentage points
function M.resize(delta)
  local st = M.win_state
  st.width_pct = math.min(90, math.max(30, st.width_pct + delta))
  M._apply_width()
end

---Load and display the diff for `entity`. No-op when it is already showing.
---@param entity { cli_id: string, kind?: string }
function M.show(entity)
  local st = M.win_state
  if not entity or not entity.cli_id then
    return
  end
  if st.entity and st.entity.cli_id == entity.cli_id then
    return
  end

  st.entity = entity
  st.hunks = {}
  -- Marks are per-diff: carrying them across entities would let a stale id
  -- match a reassigned hunk in the new one.
  st.marked = {}
  st.data = nil
  st.selected = 1
  st.gen = st.gen + 1
  local gen = st.gen
  M._render(info_rows('  loading diff…', HL.dim))

  require('gitbutler.cli').diff_json(entity.cli_id, function(err, data)
    -- A newer show() has since fired; this payload is for the wrong entity.
    if gen ~= M.win_state.gen then
      return
    end
    if err then
      M._render(info_rows('  ' .. tostring(err), HL.dim))
      return
    end
    -- Kept so selection/mark changes can re-render without another CLI call.
    M.win_state.data = data
    M._rebuild()
    -- Park the cursor on hunk 1 too, or cursorline and the `▌` bar disagree and
    -- the first `j` skips to hunk 2. No-ops when the diff has no hunks.
    M._select_hunk(1)
  end)
end

---Row types that name something `but diff` can be asked about.
local ENTITY_TYPES = {
  file = true,
  committed_file = true,
  commit = true,
  branch = true,
  uncommitted_header = true,
}

---Show the diff for a status row; rows that name no entity leave the pane alone.
---@param line? GitButlerLine
function M.show_for_line(line)
  if not line or not ENTITY_TYPES[line.type] then
    return
  end
  local id = line.data and line.data.cli_id
  if not id then
    return
  end
  M.show({ cli_id = id, kind = line.type })
end

---Debounced follow-the-cursor entry point, called from the status buffer's
---CursorMoved autocmd. Fast j/k must not spawn a CLI call per row.
---@param status_buf GitButlerBuffer
function M.follow_cursor(status_buf)
  if not M.is_open() then
    return
  end
  local st = M.win_state
  st.follow = (st.follow or 0) + 1
  local seq = st.follow
  vim.defer_fn(function()
    if seq ~= M.win_state.follow or not M.is_open() then
      return
    end
    M.show_for_line(status_buf:get_cursor_line())
  end, 60)
end

return M

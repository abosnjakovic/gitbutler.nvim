local M = {}

local config = require('gitbutler.config')

local HL = {
  file = 'GitButlerDetailFile',
  hunk = 'GitButlerDetailHunk',
  gutter = 'GitButlerDetailGutter',
  selected = 'GitButlerDetailSelected',
  mark = 'GitButlerMark',
  add = 'DiffAdd',
  del = 'DiffDelete',
  dim = 'GitButlerHelp',
  comment = 'GitButlerDetailComment',
  stale = 'GitButlerDetailStale',
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

---Leading glyphs so every hunk row lines up. Column one is hunk state: ✔︎ when
---marked, ▌ when the hunk is selected. Column two has always been a pad space —
---`▌` is one display column and every other row needs two — so the comment
---marker goes there without moving anything else on the row.
local function lead(r, marked, selected, commented)
  if marked then
    add(r, '✔︎', HL.mark)
  elseif selected then
    add(r, '▌', HL.selected)
  else
    add(r, ' ')
  end
  if commented then
    add(r, '●', HL.comment)
  else
    add(r, ' ')
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

---Columns a comment row spends on indent: two for the lead, twelve for the
---gutter (`%4d %4d │ `), two for the `╰ ` elbow.
local COMMENT_INDENT = 14
local COMMENT_BODY_INDENT = 16

---Appended to a stale comment's first row. Named so its width can be reserved
---from the wrap budget rather than hardcoded in two places.
local STALE_SUFFIX = '  · stale'

---Greedy word wrap. `width` is the display columns available to the text
---itself. Existing line breaks are kept, so a reviewer's paragraphs survive.
---@param text string
---@param width integer
---@return string[]
local function wrap(text, width)
  local out = {}
  for _, para in ipairs(vim.split(tostring(scalar(text, '')), '\n', { plain = true })) do
    local line = ''
    for word in para:gmatch('%S+') do
      if line == '' then
        line = word
      elseif vim.fn.strdisplaywidth(line .. ' ' .. word) <= width then
        line = line .. ' ' .. word
      else
        table.insert(out, line)
        line = word
      end
    end
    table.insert(out, line)
  end
  return out
end

function M._file_header(path, status)
  local text = '── ' .. scalar(path, '(unknown)') .. ' ' .. scalar(status, '') .. ' '
  local pad = math.max(1, HEADER_WIDTH - vim.fn.strdisplaywidth(text) - 1)
  return text .. string.rep('─', pad) .. '╮'
end

---Header rows (commit / Author / Date / message) prepended to a commit's diff,
---so the details pane matches the landed-history `git show` view. Pure.
---@param meta? { sha?: string, author?: string, email?: string, date?: string, message?: string }
---@return DetailsRow[]
function M._commit_meta_rows(meta)
  if not meta then
    return {}
  end
  local rows = {}
  local function line(text, hl)
    local r = { text = text, spans = {}, type = 'detail_meta', graph = true, selectable = false }
    if hl and #text > 0 then
      table.insert(r.spans, { 0, #text, hl })
    end
    table.insert(rows, r)
  end

  local sha = scalar(meta.sha, '')
  if sha ~= '' then
    line('commit ' .. sha, HL.dim)
  end
  local author = scalar(meta.author, '')
  if author ~= '' then
    local email = scalar(meta.email, '')
    line('Author: ' .. author .. (email ~= '' and (' <' .. email .. '>') or ''), HL.dim)
  end
  local date = scalar(meta.date, '')
  if date ~= '' then
    -- ISO `2026-03-24T02:31:23+00:00` -> git-show-like `2026-03-24 02:31:23+00:00`.
    line('Date:   ' .. (date:gsub('T', ' ')), HL.dim)
  end
  line('', nil)
  for _, ml in ipairs(split_lines(scalar(meta.message, ''))) do
    line('    ' .. ml, nil)
  end
  line('', nil)
  return rows
end

---Build detail rows from decoded `but diff <id> --format=json`.
---
---Not quite pure: it writes `.stale` onto each comment record in
---`state.comments`, because whether a note still points at its code is only
---knowable while rendering the diff it belongs to. The store learns about
---drift from renders and nowhere else.
---@param data table
---@param state? { selected_hunk?: integer, marked?: table<string,boolean>, meta?: table, comments?: table<string, ReviewComment>, width?: integer }
---@return DetailsRow[] rows, { id?: string, path: string, row: integer, end_row: integer }[] hunks
function M.build(data, state)
  state = state or {}
  local marked = state.marked or {}
  local comments = state.comments or {}
  local comment_width = math.max(20, (state.width or 80) - COMMENT_BODY_INDENT)
  -- Lazy require, like `_rebuild` and `_comment_line`: `build` stays ignorant
  -- of the store at module load time, only reaching for it to build the same
  -- key `for_entity` used to fill `comments`.
  local review = require('gitbutler.review')
  local rows, hunks = {}, {}
  local function push(r)
    table.insert(rows, r)
    return #rows
  end

  -- Commit meta first (when showing a whole commit) so hunk row indices, which
  -- are recorded from push() below, already account for the header height.
  for _, r in ipairs(M._commit_meta_rows(state.meta)) do
    push(r)
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
            -- Looked up before `lead`, which needs to know whether to draw the
            -- marker, and before the branches below have assigned `row_data.side`.
            local key = review.row_key(path, marker == '-' and 'old' or 'new', marker == '-' and old or new)
            local comment = comments[key]
            -- A fresh table per row: `side` and `line` differ line by line, so
            -- the hunk-wide `entity` can no longer be shared down here.
            local row_data = { cli_id = id, path = path, raw = line }
            local r = row('detail_line', row_data, false)
            lead(r, false, is_selected, comment ~= nil)
            if marker == '+' then
              row_data.side, row_data.line = 'new', new
              add(r, gutter(nil, new), HL.gutter)
              add(r, line, HL.add)
              new = new + 1
            elseif marker == '-' then
              row_data.side, row_data.line = 'old', old
              add(r, gutter(old, nil), HL.gutter)
              add(r, line, HL.del)
              old = old + 1
            else
              -- A context line exists on both sides; it anchors to the new one,
              -- which is the file as it stands after the change.
              row_data.side, row_data.line = 'new', new
              add(r, gutter(old, new), HL.gutter)
              add(r, line)
              old, new = old + 1, new + 1
            end
            end_row = push(r)

            if comment then
              -- One string compare is the whole staleness mechanism.
              comment.stale = comment.captured ~= line
              local hl = comment.stale and HL.stale or HL.comment
              -- The suffix lands on the first row after wrapping, so the body
              -- has to be wrapped narrower or that row runs off the pane.
              -- ponytail: the floor of 8 never binds — `comment_width` already
              -- floors at 20 and the suffix is 9 columns wide. That floor is
              -- also where this stops fitting: a stale row is exactly `width`
              -- columns until the pane drops under 36, below which it stays 36
              -- and overflows. Drop the suffix to its own row if that matters.
              local body_width = comment.stale and math.max(8, comment_width - vim.fn.strdisplaywidth(STALE_SUFFIX))
                or comment_width
              for i, body_line in ipairs(wrap(comment.text, body_width)) do
                local cr = row('detail_comment', {
                  path = path,
                  side = row_data.side,
                  line = row_data.line,
                }, false)
                if i == 1 then
                  add(cr, string.rep(' ', COMMENT_INDENT))
                  add(cr, '╰ ' .. body_line, hl)
                  if comment.stale then
                    add(cr, STALE_SUFFIX, HL.stale)
                  end
                else
                  add(cr, string.rep(' ', COMMENT_BODY_INDENT))
                  add(cr, body_line, hl)
                end
                end_row = push(cr)
              end
            end
          end

          table.insert(hunks, {
            id = id,
            path = path,
            row = head_row,
            end_row = end_row,
            line = tonumber(hunk.newStart) or 1,
          })
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

---@class DetailsWin
---@field buffer? GitButlerBuffer the pane's own Buffer; nil when closed
---@field buf? integer scratch buffer (mirrors buffer.buf)
---@field win? integer split window (mirrors buffer.win)
---@field status_buf? GitButlerBuffer the status view this pane hangs off
---@field full boolean fullscreen (status window hidden)
---@field horizontal? boolean true when the pane is below the status window, not beside it
---@field width_pct integer 30..90
---@field entity? { cli_id?: string, kind?: string, sha?: string, meta?: table, scope?: string, ref?: string, subject?: string }
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
---`buffer` (and `buf`/`win`) are dropped like the rest of the closed state.
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

---Write rows (text + spans) into the details buffer, via the pane's own
---`Buffer:render` — every row is `graph = true`, so it writes `text` and
---applies `spans` verbatim, the same thing this used to do by hand, plus the
---hint update and the cursor-key restore.
---
---`st.rows` is assigned unconditionally, before the buffer-existence check:
---several tests inspect it with no window open, and `_comment_line` reads it.
---@param rows DetailsRow[]
function M._render(rows)
  local st = M.win_state
  st.rows = rows
  if st.buffer then
    st.buffer:render(rows)
  end
end

local function info_rows(text, hl)
  return { { text = text, spans = { { 0, #text, hl } }, type = 'detail_info', graph = true, selectable = false } }
end

---Classify a `git show` output line into a highlight group, or nil for plain
---message / context text. Order matters: `--- `/`+++ ` file markers must be
---tested before the bare `-`/`+` diff lines. Pure.
---@param l string
---@return string?
function M._show_line_hl(l)
  if
    l:match('^commit ')
    or l:match('^Author:')
    or l:match('^Date:')
    or l:match('^Merge:')
    or l:match('^AuthorDate:')
  then
    return HL.dim
  elseif
    l:match('^diff %-%-git')
    or l:match('^index ')
    or l:match('^%-%-%- ')
    or l:match('^%+%+%+ ')
    or l:match('^new file')
    or l:match('^deleted file')
    or l:match('^similarity ')
    or l:match('^rename ')
  then
    return HL.file
  elseif l:match('^@@') then
    return HL.hunk
  elseif l:match('^%+') then
    return HL.add
  elseif l:match('^%-') then
    return HL.del
  end
  return nil
end

---Build read-only detail rows from raw `git show` output (full message + patch).
---Used for landed-history commits, which `but diff` cannot address. Pure.
---@param raw string
---@return DetailsRow[]
function M._commit_rows(raw)
  local rows = {}
  for _, l in ipairs(vim.split(raw, '\n', { plain = true })) do
    local hl = M._show_line_hl(l)
    local r = { text = l, spans = {}, type = 'commit_show', graph = true, selectable = false }
    if hl then
      table.insert(r.spans, { 0, #l, hl })
    end
    table.insert(rows, r)
  end
  return rows
end

---Narrowest pane worth putting beside the status window.
---@param avail integer columns the status window's column group has
---@param pct integer the pane's share of that group, 30–90
---@param min_width integer
---@return boolean
function M._wants_horizontal(avail, pct, min_width)
  return avail * pct / 100 < min_width
end

---Columns the status window's column group has to share. While a vertical
---pane is open its width is part of that group and must be added back:
---measuring the status window alone reports half the room a moment after the
---pane opened, which would flip the pane to the bottom on the next resize.
---
---ponytail: the boundary is one column wide, because the separator exists in
---only one of the two orientations, so a layout parked exactly on it can flip
---on every resize event. Give `_wants_horizontal` a hysteresis band of about
---five columns if that ever shows up.
---
---Fullscreen needs no guard of its own: `_hide_status` nils `sb.win` before
---setting `st.full`, so the check below has already returned by then.
---@return integer
function M._avail_width()
  local st = M.win_state
  local sb = st.status_buf
  if not (sb and sb.win and vim.api.nvim_win_is_valid(sb.win)) then
    return vim.o.columns
  end
  -- A floating status view (`kind = 'float'`) is not in the split grid at all
  -- — `vsplit` from it lands the pane in the main grid — so its own width
  -- says nothing about the room the pane will have.
  if vim.api.nvim_win_get_config(sb.win).relative ~= '' then
    return vim.o.columns
  end
  local w = vim.api.nvim_win_get_width(sb.win)
  if M.is_open() and not st.horizontal then
    w = w + vim.api.nvim_win_get_width(st.win) + 1
  end
  return w
end

---@return boolean
function M._horizontal()
  local c = config.values.details or {}
  return M._wants_horizontal(M._avail_width(), M.win_state.width_pct, c.min_width or 60)
end

---Size the pane to `width_pct` of the status window's column group, on
---whichever axis it occupies.
---
---ponytail: the height is a share of the whole editor rather than of the
---status window's row group — right for the common layout, and `+`/`-` cover
---the rest.
function M._apply_size()
  local st = M.win_state
  if not M.is_open() or st.full then
    return
  end
  if st.horizontal then
    pcall(vim.api.nvim_win_set_height, st.win, math.max(5, math.floor(vim.o.lines * st.width_pct / 100)))
  else
    pcall(vim.api.nvim_win_set_width, st.win, math.max(10, math.floor(M._avail_width() * st.width_pct / 100)))
  end
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

---The pane's cursor row, or nil when the pane is closed. A named seam so the
---row-dispatch logic can be tested without a real window.
---@return integer?
function M._cursor_row()
  if not M.is_open() then
    return nil
  end
  return vim.api.nvim_win_get_cursor(M.win_state.win)[1]
end

---Re-render from the diff payload already in hand — selection and marks are
---render-time state, so changing them never needs another CLI call.
function M._rebuild()
  local st = M.win_state
  if not st.data then
    return
  end
  local entity = st.entity or {}
  local comments = entity.scope and require('gitbutler.review').for_entity(entity.scope, entity.ref) or {}
  local rows, hunks = M.build(st.data, {
    selected_hunk = st.selected,
    marked = st.marked,
    meta = entity.meta,
    comments = comments,
    width = M.is_open() and vim.api.nvim_win_get_width(st.win) or 80,
  })
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

---`<CR>`/`o` — open the selected hunk's file in the editor window at the
---hunk's line, keeping the pane open beside it.
function M._open_hunk()
  local hunk = M.win_state.hunks[M.win_state.selected]
  if not hunk or not hunk.path then
    vim.notify('gitbutler: no file for this row', vim.log.levels.WARN)
    return
  end
  require('gitbutler.ui.editor').open(hunk.path, hunk.line)
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
    cli.discard(ids, function(err)
      if err then
        vim.notify('gitbutler discard: ' .. err, vim.log.levels.ERROR)
        finish(false)
        return
      end
      vim.notify('gitbutler: discarded ' .. #ids .. ' hunk(s)', vim.log.levels.INFO)
      finish(true)
    end)
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
    local r = rows[i]
    -- The reviewer's own notes live inside the hunk's row range now; `y` copies
    -- the patch, not the review.
    if r and r.type ~= 'detail_comment' and r.text then
      -- Non-greedy: the gutter's `│ ` is the first one on the row, any later
      -- one belongs to the file's own content.
      table.insert(out, r.text:match('^.-│ (.*)$') or r.text)
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

---`C` — comment the diff line under the cursor. Opens the popup pre-filled when
---the line already has a comment; submitting it empty deletes it, which is the
---only way a comment is removed.
function M._comment_line()
  local st = M.win_state
  local at = M._cursor_row()
  local line = at and st.rows and st.rows[at]
  local entity = st.entity or {}
  if not line or line.type ~= 'detail_line' or not line.data or not entity.scope then
    vim.notify('gitbutler: put the cursor on a diff line', vim.log.levels.WARN)
    return
  end

  local review = require('gitbutler.review')
  local anchor = {
    scope = entity.scope,
    ref = entity.ref,
    subject = entity.subject,
    path = line.data.path,
    side = line.data.side,
    line = line.data.line,
    captured = line.data.raw,
  }
  local existing = review.get(anchor)

  require('gitbutler.ui.float').input({
    title = existing and 'Edit comment' or 'Comment',
    content = existing and vim.split(existing.text, '\n', { plain = true }) or nil,
    allow_empty = true,
    on_submit = function(text)
      if text == '' then
        review.remove(anchor)
      else
        review.set(anchor, text)
      end
      M._rebuild()
    end,
  })
end

---`Y` — copy every comment collected this session to the `+` and `"` registers
---and empty the store. The branch is a label on the review rather than a
---property of any comment, so it comes from wherever the status cursor happens
---to be and is simply omitted when there is no lane there.
function M._yank_comments()
  local review = require('gitbutler.review')
  local total, stale = review.counts()
  if total == 0 then
    vim.notify('gitbutler: no comments to yank', vim.log.levels.WARN)
    return
  end

  local sb = M.win_state.status_buf
  local branch = sb and sb.get_cursor_branch and sb:get_cursor_branch()
  local text = review.format(branch and branch.name or nil)

  vim.fn.setreg('+', text)
  vim.fn.setreg('"', text)
  review.clear()
  M._rebuild()

  vim.notify(
    string.format(
      'gitbutler: yanked %d comment%s%s',
      total,
      total == 1 and '' or 's',
      stale > 0 and (' (' .. stale .. ' stale)') or ''
    ),
    vim.log.levels.INFO
  )
end

---`a` — enter amend mode on the status buffer with the hunks as source. `kind`
---is 'file': amend treats a hunk exactly like an uncommitted file, and the
---source rows live in the other window so `rows` stays empty.
function M._hunk_amend()
  local st = M.win_state
  local ids, paths = M._targets()
  if #ids == 0 then
    warn_no_ids()
    return
  end
  local sb = st.status_buf
  if not sb or not (sb.win and vim.api.nvim_win_is_valid(sb.win)) then
    vim.notify('gitbutler: no status window to amend into', vim.log.levels.WARN)
    return
  end
  M._focus_status()
  require('gitbutler.ui.modes').enter_verb(sb, 'amend', {
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

---The pane's Buffer, or nil when it is closed. A named accessor so tests can
---reach it without depending on where in `win_state` it lives.
---@return GitButlerBuffer?
function M._buffer()
  return M.win_state.buffer
end

---Bind the pane's handlers under the action names `keys.contexts.details`
---uses. A name that does not match there is a key the hint line advertises
---and the pane does not answer. j/k/g/G carry no `action` in the registry —
---see `set_keymap` — so no handler is registered for them: mapping them would
---break the pane's native line-by-line scroll.
---@param buf GitButlerBuffer
function M._register_handlers(buf)
  buf:on('hunk_next', function()
    M._select_hunk(M._next_hunk(M.win_state.hunks, M.win_state.selected, 1))
  end)
  buf:on('hunk_prev', function()
    M._select_hunk(M._next_hunk(M.win_state.hunks, M.win_state.selected, -1))
  end)
  buf:on('scroll_down', function()
    scroll(1, '\5')
  end)
  buf:on('scroll_up', function()
    scroll(1, '\25')
  end)
  buf:on('scroll_page_down', function()
    scroll(10, '\5')
  end)
  buf:on('scroll_page_up', function()
    scroll(10, '\25')
  end)
  buf:on('open_hunk', M._open_hunk)
  buf:on('toggle_mark', M._toggle_mark)
  buf:on('hunk_discard', M._hunk_discard)
  buf:on('hunk_copy', M._hunk_copy)
  buf:on('comment_line', M._comment_line)
  buf:on('yank_comments', M._yank_comments)
  buf:on('hunk_amend', M._hunk_amend)
  buf:on('focus_status', M._focus_status)
  buf:on('close_pane', M.close)
  buf:on('toggle_full', function()
    M.toggle_full(M.win_state.status_buf)
  end)
  buf:on('grow', function()
    M.resize(5)
  end)
  buf:on('shrink', function()
    M.resize(-5)
  end)
  buf:on('help', function()
    require('gitbutler.actions').help(M.win_state.buffer)
  end)
end

---Buffer-local keymap for the details pane, bound from the registry so the
---keys the pane answers and the keys it advertises cannot drift apart. `q`
---closes the pane only — unlike the status window's `q`, which closes the
---whole view. Matches upstream.
---
---j/k/g/G carry no `action` (`native = true`) and so bind to nothing, which is
---what keeps every pane scrolling line by line whether it holds a structured
---`but diff` or a plain `git show`. Hunk selection is not lost: the
---CursorMoved hook snaps it to whichever hunk the cursor lands in, so
---<Space>/x/a still act on the right one. ]c/[c jump hunk to hunk.
---@param buf GitButlerBuffer
local function set_keymap(buf)
  for _, spec in ipairs(require('gitbutler.keys').resolved('details')) do
    local handler = spec.action and buf.keymaps[spec.action]
    if handler then
      vim.keymap.set('n', spec.key, function()
        handler(buf)
      end, { buffer = buf.buf, nowait = true, silent = true })
    end
  end
end

---Open the pane window against the status window and put `st.buf` in it.
---A split, not `wincmd J` / `wincmd L`: those pull the pane out of the status
---window's column group to span the whole editor, rearranging unrelated user
---windows — the same reason `_hide_status` refuses `:only`.
---@param horizontal boolean
---@return boolean placed
function M._place(horizontal)
  local st = M.win_state
  local src = st.status_buf and st.status_buf.win
  if not (src and vim.api.nvim_win_is_valid(src)) then
    return false
  end

  vim.api.nvim_set_current_win(src)
  vim.cmd(horizontal and 'belowright split' or 'rightbelow vsplit')
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, st.buf)
  st.win, st.horizontal = win, horizontal
  st.buffer:attach(win)
  M._watch_layout()
  M._apply_size()

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
  return true
end

---Re-place a live pane whose orientation no longer fits the layout. The
---buffer is never recreated, so rows, marks and hunk selection survive; only
---the window changes.
function M._reorient()
  local st = M.win_state
  if not M.is_open() or st.full then
    return
  end
  local want = M._horizontal()
  if want == (st.horizontal or false) then
    return
  end

  local old = st.win
  local focused_pane = vim.api.nvim_get_current_win() == old
  local cursor = vim.api.nvim_win_get_cursor(old)
  -- `st.buf` is `bufhidden = 'wipe'`: closing its only window destroys it the
  -- instant it goes windowless. Suspend that for the moment between this
  -- close and `_place` giving the buffer a new window, or the re-place would
  -- recreate the buffer instead of moving it.
  local prev_bufhidden = vim.bo[st.buf].bufhidden
  vim.bo[st.buf].bufhidden = 'hide'
  -- `_place` reassigns `st.win` before the deferred WinClosed teardown for
  -- `old` runs, so that handler's `win_state.win == win` guard drops the
  -- event instead of tearing down the pane we just reopened.
  pcall(vim.api.nvim_win_close, old, true)
  -- The status window's column group may have no room for the new
  -- orientation: `vim.cmd('belowright split' | 'rightbelow vsplit')` raises
  -- `E36: Not enough room` rather than returning false, and this runs from a
  -- WinResized/VimResized autocmd, so an unwrapped throw would escape as a
  -- visible error with the pane already gone. pcall it, and on any failure
  -- fall back to the orientation the pane already had — `_place` leaves
  -- `st.horizontal` untouched when the split throws, so `not want` is
  -- exactly that. Guarded with its own pcall so the fallback cannot itself
  -- throw and re-open the same hole.
  local ok, placed = pcall(M._place, want)
  vim.bo[st.buf].bufhidden = prev_bufhidden
  if not ok or not placed then
    local fb_ok, fb_placed = pcall(M._place, not want)
    if not fb_ok or not fb_placed then
      -- Both orientations failed, which only happens if the status window
      -- itself is gone — `open()`'s own guard already treats that as
      -- unrecoverable. Nothing leaks: `st.win` still names the window closed
      -- above, so that window's deferred `WinClosed` teardown finds its
      -- `win_state.win == win` guard true and runs the full `close()`. The
      -- stale `st.win` is what makes this self-healing, so do not "tidy" it
      -- to nil here — that would strand the buffer and the hidden status
      -- window instead.
      return
    end
  end
  -- Belt and braces: `_place` puts the same buffer back, and Neovim's own
  -- per-buffer cursor memory usually reproduces this row on its own — which
  -- is why the covering test cannot fail on this line being deleted, only on
  -- it restoring the wrong row. Kept because the promise is ours, not
  -- Neovim's, and the memory does not survive every path into `_place`.
  pcall(vim.api.nvim_win_set_cursor, st.win, cursor)
  local back = focused_pane and st.win or (st.status_buf and st.status_buf.win)
  if back and vim.api.nvim_win_is_valid(back) then
    pcall(vim.api.nvim_set_current_win, back)
  end
end

---Re-place the pane when the layout changes under it: `WinResized` catches a
---Neovim split, `VimResized` the terminal. It goes in the Buffer's own hint
---augroup, which `Buffer:attach` clears on every attach — so re-placing the
---window cannot leak a second handler, and closing the pane needs no teardown
---code of its own.
---
---The re-place itself fires `WinResized`; that pass finds the orientation
---already fitting and returns, so this does not recurse.
function M._watch_layout()
  vim.api.nvim_create_autocmd({ 'WinResized', 'VimResized' }, {
    group = M.win_state.buffer.hint_augroup,
    callback = function()
      vim.schedule(function()
        M._reorient()
      end)
    end,
  })
end

---@param status_buf GitButlerBuffer
function M.open(status_buf)
  local st = M.win_state
  st.status_buf = status_buf or st.status_buf
  if M.is_open() then
    return
  end

  local src = st.status_buf and st.status_buf.win
  if not src or not vim.api.nvim_win_is_valid(src) then
    return
  end

  local buf = require('gitbutler.ui.buffer').Buffer.new()
  buf.view = 'details'
  buf.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf.buf].buftype = 'nofile'
  vim.bo[buf.buf].bufhidden = 'wipe'
  vim.bo[buf.buf].swapfile = false
  vim.bo[buf.buf].filetype = 'gitbutler-details'

  M._register_handlers(buf)
  st.buffer, st.buf = buf, buf.buf

  -- Same throw hazard as `_reorient`: the status window's column group may
  -- have no room, and `vim.cmd(...split)` raises rather than returning
  -- false. pcall it so a throw takes the same delete-and-reset path as an
  -- ordinary `false` return, instead of propagating out of `open()`.
  local ok, placed = pcall(M._place, M._horizontal())
  if not ok or not placed then
    pcall(vim.api.nvim_buf_delete, buf.buf, { force = true })
    M._reset_state()
    return
  end

  M._render(info_rows('  (no selection)', HL.dim))
  set_keymap(buf)

  vim.api.nvim_create_autocmd('CursorMoved', {
    buffer = buf.buf,
    callback = function()
      M._sync_cursor()
    end,
  })

  vim.api.nvim_set_current_win(src)
  M.show_for_line(st.status_buf:get_cursor_line())
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

---Put the hidden status window back beside (or above) the details pane.
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
  vim.cmd(M.win_state.horizontal and 'aboveleft split' or 'leftabove vsplit')
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, sb.buf)
  vim.bo[sb.buf].bufhidden = 'wipe'
  -- Not a bare `sb.win = win`: `_hide_status`'s close fired `BufWinLeave` on
  -- the status buffer, which deleted `hint_augroup` — the augroup owning the
  -- CursorMoved -> `follow_cursor` handler. `attach` re-registers it (and the
  -- hint float) the same way a fresh `Buffer:open()` would.
  sb:attach(win)
  M._apply_size()
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
  -- Hand-rolled teardown, not `Buffer:close()` — but the hint float is still
  -- the Buffer's to close. Today `BufWinLeave` closes it anyway when the
  -- window goes down below, so this is only reachable under `eventignore` or
  -- a `noautocmd` close, but leaving it to chance leaks an orphan float.
  if st.buffer then
    st.buffer:_close_hint_window()
  end
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
  M._apply_size()
end

---Load and display the diff for `entity`. No-op when it is already showing.
---@param entity { cli_id: string, kind?: string, meta?: table }
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

---Load and display a landed commit's full message + patch via `git show`.
---Landed history sits below the workspace base, so `but diff` can't address it;
---this renders read-only text (no hunk marks) keyed on the sha.
---@param sha string
function M.show_commit(sha)
  local st = M.win_state
  if not sha or sha == '' then
    return
  end
  if st.entity and st.entity.sha == sha then
    return
  end
  st.entity = { sha = sha }
  st.hunks = {}
  st.marked = {}
  st.data = nil
  st.selected = 1
  st.gen = st.gen + 1
  local gen = st.gen
  M._render(info_rows('  loading commit…', HL.dim))

  vim.system({ 'git', 'show', '--no-color', sha }, { text = true }, function(res)
    vim.schedule(function()
      if gen ~= M.win_state.gen then
        return
      end
      if res.code ~= 0 then
        M._render(info_rows('  git show failed', HL.dim))
        return
      end
      M._render(M._commit_rows(res.stdout or ''))
    end)
  end)
end

---Which kind of thing a status row's diff belongs to. A comment on a line has
---to say what it is anchored to, and only the status row knows. Also the set
---of row types that name something `but diff` can be asked about — kept as
---one table so the two can't drift apart and reject a real diff line.
local ROW_SCOPE = {
  commit = 'commit',
  committed_file = 'commit',
  branch = 'branch',
  file = 'uncommitted',
  uncommitted_header = 'uncommitted',
}

---The identity within that scope: a sha for a commit, a name for a branch,
---nothing for uncommitted changes. A branch diff spans several commits, so no
---single sha describes a line in it and the name is what is genuinely known.
---
---Read the name off the raw payload rather than `d.name`, which the graph has
---already defaulted to the display string `(unnamed)`. Two nameless lanes
---share that string, and comments anchored to it would surface on the wrong
---branch; the cli id is what still distinguishes them.
---@param line GitButlerLine
---@return string?
local function row_ref(line)
  local d = line.data or {}
  if line.type == 'commit' then
    return d.sha
  elseif line.type == 'committed_file' then
    return d.commit_id
  elseif line.type == 'branch' then
    return scalar(d.branch and d.branch.name, nil) or d.cli_id
  end
  return nil
end

---Show the diff for a status row; rows that name no entity leave the pane alone.
---@param line? GitButlerLine
function M.show_for_line(line)
  if not line then
    return
  end
  -- Landed-history commits carry a sha but no cli_id; show them via `git show`.
  -- The common base is one of them, so `d` works there too.
  if line.type == 'base_commit' or line.type == 'merge_base' then
    M.show_commit(line.data and line.data.sha or '')
    return
  end
  if not ROW_SCOPE[line.type] then
    return
  end
  local id = line.data and line.data.cli_id
  if not id then
    return
  end
  -- A whole-commit row gets the same commit/Author/Date/message header the
  -- landed-history view shows, prepended to its structured diff.
  local meta
  if line.type == 'commit' then
    local c = line.data.commit or {}
    meta = {
      sha = line.data.sha,
      author = c.authorName,
      email = c.authorEmail,
      date = c.createdAt,
      message = c.message,
    }
  end
  M.show({
    cli_id = id,
    kind = line.type,
    meta = meta,
    scope = ROW_SCOPE[line.type],
    ref = row_ref(line),
    subject = meta and scalar(meta.message, nil) and vim.split(scalar(meta.message, nil), '\n', { plain = true })[1]
      or nil,
  })
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

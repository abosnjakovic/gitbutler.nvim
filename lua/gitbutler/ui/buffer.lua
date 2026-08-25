local config = require('gitbutler.config')

-- Mark-key category prefixes used by graph rows; legacy cli_ids (e.g. 'c4:xw')
-- also match the `word:` shape but aren't real categories, so only these count.
local MARK_CATS = { change = true, commit = true, cfile = true }

---@class GitButlerLine
---@field text string Display text for the line
---@field hl? string Highlight group name
---@field type string Line type: 'branch', 'commit', 'file', 'committed_file', 'section_header', 'blank', 'help', 'info', 'recent_commit', 'uncommitted_header', 'connector', 'upstream', 'merge_base'
---@field data? table Arbitrary data associated with the line (branch info, commit sha, file path, etc.)
---@field foldable? boolean Whether this line is a fold header
---@field folded? boolean Current fold state
---@field indent? number Indentation level
---@field graph? boolean Graph row: text rendered verbatim, spans applied
---@field spans? {[1]:integer,[2]:integer,[3]:string}[] 0-indexed byte-range highlights
---@field selectable? boolean Cursor may rest on this row

---@class GitButlerBuffer
---@field buf number Buffer handle
---@field win? number Window handle
---@field lines GitButlerLine[] Structured line data
---@field ns number Namespace for extmarks
---@field keymaps table<string, fun(buf: GitButlerBuffer)> Action keymaps
---@field mode_filter? fun(line: GitButlerLine, row: integer): boolean Active mode's target filter
---@field _cursor_row? integer Test seam: overrides the window cursor row
---@field fold_state table<string, boolean> Persisted fold states keyed by section id
---@field selected table<string, boolean> Selected items keyed by stable identifier
---@field view? string View name driving the keymap and hint content ('status', 'log', …)
---@field file_lists table<string, boolean> Per-commit file list expansion state
---@field show_all_files boolean Expand every commit's file list
---@field hint_buf? number Pinned hint/hotbar buffer
---@field hint_win? number Pinned hint/hotbar float
---@field hint_augroup? number Augroup owning the hint autocmds
---@field branch_name? string Log view: the branch it was opened for
---@field branch? string CI view: the branch it was opened for
---@field adapter? table CI view: the forge adapter it was opened with
local Buffer = {}
Buffer.__index = Buffer

function Buffer.new()
  local self = setmetatable({}, Buffer)
  self.buf = nil
  self.win = nil
  self.lines = {}
  self.ns = vim.api.nvim_create_namespace('gitbutler')
  self.keymaps = {}
  self.fold_state = {}
  self.selected = {}
  self.file_lists = {}
  self.show_all_files = false
  self.view = nil
  self.hint_buf = nil
  self.hint_win = nil
  self.hint_augroup = nil
  return self
end

---Compute geometry for the hint floating window.
---@return number width, number row
function Buffer:_hint_geometry()
  local width = vim.api.nvim_win_get_width(self.win)
  local height = vim.api.nvim_win_get_height(self.win)
  return width, math.max(0, height - 2)
end

---Create the floating hint window pinned to the bottom of self.win, if absent.
function Buffer:_ensure_hint_window()
  if not self.win or not vim.api.nvim_win_is_valid(self.win) then
    return
  end

  if
    self.hint_win
    and vim.api.nvim_win_is_valid(self.hint_win)
    and self.hint_buf
    and vim.api.nvim_buf_is_valid(self.hint_buf)
  then
    self:_position_hint_window()
    return
  end

  self.hint_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[self.hint_buf].buftype = 'nofile'
  vim.bo[self.hint_buf].bufhidden = 'wipe'
  vim.bo[self.hint_buf].swapfile = false
  vim.bo[self.hint_buf].filetype = 'gitbutler-hint'

  local width, row = self:_hint_geometry()
  self.hint_win = vim.api.nvim_open_win(self.hint_buf, false, {
    relative = 'win',
    win = self.win,
    anchor = 'NW',
    row = row,
    col = 0,
    width = width,
    height = 1,
    style = 'minimal',
    border = { '', '─', '', '', '', '', '', '' },
    focusable = false,
    noautocmd = true,
    zindex = 50,
  })
  vim.wo[self.hint_win].winhighlight = 'NormalFloat:Normal,FloatBorder:GitButlerHelp'
  vim.wo[self.hint_win].cursorline = false
  vim.wo[self.hint_win].number = false
  vim.wo[self.hint_win].relativenumber = false
  vim.wo[self.hint_win].signcolumn = 'no'
end

---Reposition the hint window after window resize.
function Buffer:_position_hint_window()
  if not self.hint_win or not vim.api.nvim_win_is_valid(self.hint_win) then
    return
  end
  if not self.win or not vim.api.nvim_win_is_valid(self.win) then
    return
  end
  local width, row = self:_hint_geometry()
  vim.api.nvim_win_set_config(self.hint_win, {
    relative = 'win',
    win = self.win,
    anchor = 'NW',
    row = row,
    col = 0,
    width = width,
    height = 1,
  })
end

---Tear down the hint window.
function Buffer:_close_hint_window()
  if self.hint_augroup then
    pcall(vim.api.nvim_del_augroup_by_id, self.hint_augroup)
    self.hint_augroup = nil
  end
  if self.hint_win and vim.api.nvim_win_is_valid(self.hint_win) then
    pcall(vim.api.nvim_win_close, self.hint_win, true)
  end
  if self.hint_buf and vim.api.nvim_buf_is_valid(self.hint_buf) then
    pcall(vim.api.nvim_buf_delete, self.hint_buf, { force = true })
  end
  self.hint_win = nil
  self.hint_buf = nil
end

---Get or create the buffer, then open it in a window.
function Buffer:open()
  if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then
    self.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[self.buf].buftype = 'nofile'
    vim.bo[self.buf].bufhidden = 'wipe'
    vim.bo[self.buf].swapfile = false
    vim.bo[self.buf].filetype = 'gitbutler'
    self:_set_keymaps()
  end

  local kind = config.values.kind
  if kind == 'tab' then
    vim.cmd('tabnew')
    self.win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(self.win, self.buf)
  elseif kind == 'split' then
    vim.cmd('split')
    self.win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(self.win, self.buf)
  elseif kind == 'vsplit' then
    vim.cmd('vsplit')
    self.win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(self.win, self.buf)
  elseif kind == 'float' then
    local float = require('gitbutler.ui.float')
    local _, win = float.open({ buf = self.buf })
    self.win = win
  else
    self.win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(self.win, self.buf)
  end

  self:attach(self.win)
end

---Take ownership of a window the caller already created: window options, the
---pinned hint window, and the cursor and resize autocmds. Not the keymaps —
---`_set_keymaps` runs inside `open()`, gated on new-buffer creation, so a
---caller that reaches a window through `attach` alone (the details pane)
---has to bind its own keys through a second path.
---
---Split out of `open` so the details pane can reuse all of it. That pane makes
---its own window — a vsplit beside the status view, with a width percentage and
---a fullscreen toggle — which `open`'s `config.values.kind` switch cannot do.
---@param win integer
function Buffer:attach(win)
  self.win = win

  vim.wo[self.win].number = false
  vim.wo[self.win].relativenumber = false
  vim.wo[self.win].signcolumn = 'no'
  vim.wo[self.win].foldcolumn = '0'
  vim.wo[self.win].wrap = false
  vim.wo[self.win].cursorline = true

  self:_ensure_hint_window()

  self.hint_augroup = vim.api.nvim_create_augroup('GitButlerHint' .. self.buf, { clear = true })
  vim.api.nvim_create_autocmd('CursorMoved', {
    group = self.hint_augroup,
    buffer = self.buf,
    callback = function()
      self:update_hint()
      if self.view == 'status' then
        require('gitbutler.ui.details').follow_cursor(self)
      end
    end,
  })
  vim.api.nvim_create_autocmd({ 'WinResized', 'VimResized' }, {
    group = self.hint_augroup,
    callback = function()
      self:_position_hint_window()
      -- Hotbar truncation is width-dependent, so it must be rebuilt too.
      self:update_hint()
    end,
  })
  vim.api.nvim_create_autocmd('BufWinEnter', {
    group = self.hint_augroup,
    buffer = self.buf,
    callback = function()
      self.win = vim.api.nvim_get_current_win()
      self:_ensure_hint_window()
      self:update_hint()
    end,
  })
  vim.api.nvim_create_autocmd('BufWinLeave', {
    group = self.hint_augroup,
    buffer = self.buf,
    callback = function()
      self:_close_hint_window()
    end,
  })

  require('gitbutler.watch').sync()
end

---Close the buffer and window.
function Buffer:close()
  self:_close_hint_window()
  if self.win and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_win_close(self.win, true)
  end
  if self.buf and vim.api.nvim_buf_is_valid(self.buf) then
    vim.api.nvim_buf_delete(self.buf, { force = true })
  end
  self.buf = nil
  self.win = nil
  require('gitbutler.watch').sync()
end

---Move the cursor to `row`, clamped to the buffer. The single window-mutating
---call in the restore path, so tests can override it without a real window.
---@param row integer
function Buffer:_move_cursor(row)
  if not self.win or not vim.api.nvim_win_is_valid(self.win) then
    return
  end
  if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then
    return
  end
  local last = vim.api.nvim_buf_line_count(self.buf)
  vim.api.nvim_win_set_cursor(self.win, { math.min(row, last), 0 })
end

---Stable identity of the row under the cursor, or nil when that row has none
---(blanks, headers, connectors). Reuses the multi-select key so a row is
---identified the same way everywhere.
---@return string?
function Buffer:_cursor_key()
  local row = self._cursor_row
  if not row then
    if not self.win or not vim.api.nvim_win_is_valid(self.win) then
      return nil
    end
    row = vim.api.nvim_win_get_cursor(self.win)[1]
  end
  return self:select_key(self.lines[row])
end

---Park the cursor back on `key` after a re-render. Silent no-op when the key
---is nil or the row it named no longer exists — a squashed commit must not
---throw or send the cursor somewhere arbitrary.
---@param key string?
function Buffer:_seek_key(key)
  if not key then
    return
  end
  for i, line in ipairs(self.lines) do
    if self:select_key(line) == key then
      self:_move_cursor(i)
      return
    end
  end
end

---Render lines into the buffer. Clears existing content, writes text, applies highlights.
---@param lines GitButlerLine[]
function Buffer:render(lines)
  -- Captured BEFORE the assignment: after it, the row number under the cursor
  -- names whichever entity slid into that position, not the one the user was on.
  local prev_key = self:_cursor_key()
  self.lines = lines
  if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then
    self:_seek_key(prev_key)
    return
  end

  vim.bo[self.buf].modifiable = true
  vim.api.nvim_buf_clear_namespace(self.buf, self.ns, 0, -1)

  local text_lines = {}
  for _, line in ipairs(lines) do
    if line.graph then
      table.insert(text_lines, line.text)
    else
      local indent = string.rep('  ', line.indent or 0)
      local prefix = ''
      if line.foldable then
        prefix = line.folded and '▸ ' or '▾ '
      end
      local select_marker = ''
      if self:is_selected(line) then
        select_marker = '● '
      end
      table.insert(text_lines, indent .. select_marker .. prefix .. line.text)
    end
  end

  vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, text_lines)

  -- Apply highlights
  for i, line in ipairs(lines) do
    if line.graph then
      for _, s in ipairs(line.spans or {}) do
        vim.api.nvim_buf_add_highlight(self.buf, self.ns, s[3], i - 1, s[1], s[2])
      end
    elseif self:is_selected(line) then
      vim.api.nvim_buf_add_highlight(self.buf, self.ns, 'GitButlerSelected', i - 1, 0, -1)
    elseif line.hl then
      vim.api.nvim_buf_add_highlight(self.buf, self.ns, line.hl, i - 1, 0, -1)
    end
  end

  vim.bo[self.buf].modifiable = false

  self:_seek_key(prev_key)
  self:update_hint()
end

---Paint a hotbar-built line (mode pill + width-truncated items) into the hint window.
local function render_hotbar(self, built)
  vim.bo[self.hint_buf].modifiable = true
  vim.api.nvim_buf_clear_namespace(self.hint_buf, self.ns, 0, -1)
  vim.api.nvim_buf_set_lines(self.hint_buf, 0, -1, false, { built.text })
  for _, s in ipairs(built.spans) do
    vim.api.nvim_buf_add_highlight(self.hint_buf, self.ns, s[3], 0, s[1], s[2])
  end
  vim.bo[self.hint_buf].modifiable = false
end

---Hotbar items for a view whose hint line is registry-derived rather than a
---curated per-row-type table (`hints.has_entry` is false).
---
---`hotbar.build`'s `keep` tail is appended with no width check, so it must
---stay small or it overflows the window itself: `help` and one `close`-like
---action, deduped by action so an aliased close key (`details` binds both
---`d` and `q` to `close_pane`) isn't kept twice and doesn't spend the tail's
---budget twice for the same thing.
---
---Everything else competes for the width-budgeted portion, in priority
---order: an entry curated with `hotbar = true` first — the same curation
---the status hotbar already uses to pick its core verbs, so the pane's core
---verbs (`mark`, `discard`, `copy hunk`, `amend`, … in the details pane)
---survive a clipped line instead of losing to whichever entry happens to
---carry a `help` string — then other bound actions, then native entries (no
---`action`, e.g. details' `j`/`k`/`g`/`G`) last, since vim-standard motions
---are the least surprising thing to lose to truncation.
---@param view string
---@return table[]
local function registry_hotbar_items(view)
  local kept_actions, kept, curated, rest, native = {}, {}, {}, {}, {}
  for _, spec in ipairs(require('gitbutler.keys').resolved(view)) do
    local is_close = spec.action ~= nil and spec.action:find('close', 1, true) ~= nil
    local keep = (spec.action == 'help' or is_close) and not kept_actions[spec.action]
    local it = { spec.key, spec.desc, keep = keep or nil }
    if keep then
      kept_actions[spec.action] = true
      table.insert(kept, it)
    elseif spec.hotbar then
      table.insert(curated, it)
    elseif spec.action then
      table.insert(rest, it)
    else
      table.insert(native, it)
    end
  end
  local items = {}
  vim.list_extend(items, kept)
  vim.list_extend(items, curated)
  vim.list_extend(items, rest)
  vim.list_extend(items, native)
  return items
end

---Refresh the pinned hint window contents based on current cursor context.
function Buffer:update_hint()
  if not self.view then
    return
  end
  if not self.hint_buf or not vim.api.nvim_buf_is_valid(self.hint_buf) then
    return
  end

  local hotbar = require('gitbutler.ui.hotbar')
  local width = (self.win and vim.api.nvim_win_is_valid(self.win)) and vim.api.nvim_win_get_width(self.win) or 80

  if self.view == 'status' then
    local mode = require('gitbutler.ui.modes').current()
    render_hotbar(self, hotbar.build(mode, hotbar.items_for(mode), width, hotbar.pill_hl(mode)))
    return
  end

  local line = self:get_cursor_line()
  local line_type = line and line.type or nil
  local hints = require('gitbutler.ui.hints')

  -- A registry-derived line has no fixed length (`details` alone has 27
  -- entries) and the hint window is one line, so it needs the same
  -- width-aware truncation the status hotbar already has — not the plain,
  -- unclipped text `hints.for_context` returns for a curated per-row-type
  -- entry, which is already the right length by design.
  if not hints.has_entry(self.view, line_type) then
    render_hotbar(self, hotbar.build(self.view, registry_hotbar_items(self.view), width, hotbar.pill_hl(self.view)))
    return
  end

  local selectable = line ~= nil and (line.type == 'commit' or line.type == 'file' or line.type == 'committed_file')
  local text, key_ranges = hints.for_context(self.view, line_type, selectable)

  vim.bo[self.hint_buf].modifiable = true
  vim.api.nvim_buf_clear_namespace(self.hint_buf, self.ns, 0, -1)
  vim.api.nvim_buf_set_lines(self.hint_buf, 0, -1, false, { ' ' .. text })
  vim.api.nvim_buf_add_highlight(self.hint_buf, self.ns, 'GitButlerHelp', 0, 0, -1)
  for _, range in ipairs(key_ranges) do
    -- shift by 1 to account for leading space
    vim.api.nvim_buf_add_highlight(self.hint_buf, self.ns, 'GitButlerHelpKey', 0, range[1] + 1, range[2] + 1)
  end
  vim.bo[self.hint_buf].modifiable = false
end

---Get the structured line data for the line under the cursor.
---@return GitButlerLine?
function Buffer:get_cursor_line()
  if not self.win or not vim.api.nvim_win_is_valid(self.win) then
    return nil
  end
  local row = vim.api.nvim_win_get_cursor(self.win)[1]
  return self.lines[row]
end

---Get the branch context for the line under the cursor.
---Walk up from cursor to find the nearest branch header.
---@return table? branch data
function Buffer:get_cursor_branch()
  if not self.win or not vim.api.nvim_win_is_valid(self.win) then
    return nil
  end
  local row = vim.api.nvim_win_get_cursor(self.win)[1]
  for i = row, 1, -1 do
    local line = self.lines[i]
    if line and line.type == 'branch' and line.data then
      return line.data
    end
  end
  return nil
end

---Toggle fold state for the nearest foldable section.
---Walks up from cursor to find the closest foldable header.
---@return string?
function Buffer:toggle_fold()
  if not self.win or not vim.api.nvim_win_is_valid(self.win) then
    return nil
  end
  local row = vim.api.nvim_win_get_cursor(self.win)[1]

  -- Walk up from cursor to find nearest foldable line
  for i = row, 1, -1 do
    local line = self.lines[i]
    if line and line.foldable and line.data and line.data.fold_id then
      local id = line.data.fold_id
      self.fold_state[id] = not self.fold_state[id]
      return id
    end
  end
  return nil
end

---Check if a section is folded.
---@param fold_id string
---@return boolean
function Buffer:is_folded(fold_id)
  if self.fold_state[fold_id] ~= nil then
    return self.fold_state[fold_id]
  end
  return false
end

---Extract a stable selection key from a line, or nil if not selectable.
---@param line GitButlerLine
---@return string?
function Buffer:select_key(line)
  if not line or not line.data then
    return nil
  end
  if line.data.mark_key then
    return line.data.mark_key
  end
  if line.type == 'file' or line.type == 'committed_file' then
    return line.data.cli_id
  elseif line.type == 'commit' then
    return line.data.sha
  end
  return nil
end

---Toggle selection for the line under cursor.
function Buffer:toggle_select()
  local row = self._cursor_row
  if not row then
    if not self.win or not vim.api.nvim_win_is_valid(self.win) then
      return
    end
    row = vim.api.nvim_win_get_cursor(self.win)[1]
  end
  local line = self.lines[row]
  local key = self:select_key(line)
  if not key then
    return false
  end
  if not self.selected[key] then
    local cat = key:match('^(%w+):')
    cat = MARK_CATS[cat] and cat or nil
    if cat then
      for existing in pairs(self.selected) do
        local ecat = existing:match('^(%w+):')
        ecat = MARK_CATS[ecat] and ecat or nil
        if ecat and ecat ~= cat then
          return false
        end
      end
    end
  end
  if self.selected[key] then
    self.selected[key] = nil
  else
    self.selected[key] = true
  end
  return true
end

---Check if a line is currently selected.
---@param line GitButlerLine
---@return boolean
function Buffer:is_selected(line)
  local key = self:select_key(line)
  return key ~= nil and self.selected[key] == true
end

---Return all selected lines from self.lines, in display order.
---@param types? string[] Optional filter: only return lines of these types
---@return GitButlerLine[]
function Buffer:get_selected_lines(types)
  local result = {}
  for _, line in ipairs(self.lines) do
    if self:is_selected(line) then
      if not types then
        table.insert(result, line)
      else
        for _, t in ipairs(types) do
          if line.type == t then
            table.insert(result, line)
            break
          end
        end
      end
    end
  end
  return result
end

---Clear all selections.
function Buffer:clear_selection()
  self.selected = {}
end

---Register an action handler.
---@param name string Action name (matches config keymap values)
---@param handler fun(buf: GitButlerBuffer)
function Buffer:on(name, handler)
  self.keymaps[name] = handler
end

function Buffer:_set_keymaps()
  local mappings = (config.values.keymaps and config.values.keymaps[self.view or 'status']) or {}
  for key, action in pairs(mappings) do
    if action then
      vim.keymap.set('n', key, function()
        local handler = self.keymaps[action]
        if handler then
          handler(self)
        end
      end, { buffer = self.buf, nowait = true })
    end
  end
end

return {
  Buffer = Buffer,
}

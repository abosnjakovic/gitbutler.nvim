local config = require('gitbutler.config')

local M = {}

---@class GitButlerLine
---@field text string Display text for the line
---@field hl? string Highlight group name
---@field type string Line type: 'branch', 'commit', 'file', 'committed_file', 'section_header', 'blank', 'help', 'info', 'recent_commit'
---@field data? table Arbitrary data associated with the line (branch info, commit sha, file path, etc.)
---@field foldable? boolean Whether this line is a fold header
---@field folded? boolean Current fold state
---@field indent? number Indentation level

---@class GitButlerBuffer
---@field buf number Buffer handle
---@field win? number Window handle
---@field lines GitButlerLine[] Structured line data
---@field ns number Namespace for extmarks
---@field keymaps table<string, fun()> Action keymaps
---@field fold_state table<string, boolean> Persisted fold states keyed by section id
---@field selected table<string, boolean> Selected items keyed by stable identifier

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
  if not self.win or not vim.api.nvim_win_is_valid(self.win) then return end

  if self.hint_win and vim.api.nvim_win_is_valid(self.hint_win)
     and self.hint_buf and vim.api.nvim_buf_is_valid(self.hint_buf) then
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
  if not self.hint_win or not vim.api.nvim_win_is_valid(self.hint_win) then return end
  if not self.win or not vim.api.nvim_win_is_valid(self.win) then return end
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
    _, self.win = float.open({ buf = self.buf })
  else
    self.win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(self.win, self.buf)
  end

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
    callback = function() self:update_hint() end,
  })
  vim.api.nvim_create_autocmd({ 'WinResized', 'VimResized' }, {
    group = self.hint_augroup,
    callback = function() self:_position_hint_window() end,
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
    callback = function() self:_close_hint_window() end,
  })
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
end

---Render lines into the buffer. Clears existing content, writes text, applies highlights.
---@param lines GitButlerLine[]
function Buffer:render(lines)
  self.lines = lines
  if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then return end

  vim.bo[self.buf].modifiable = true
  vim.api.nvim_buf_clear_namespace(self.buf, self.ns, 0, -1)

  local text_lines = {}
  for _, line in ipairs(lines) do
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

  vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, text_lines)

  -- Apply highlights
  for i, line in ipairs(lines) do
    if self:is_selected(line) then
      vim.api.nvim_buf_add_highlight(self.buf, self.ns, 'GitButlerSelected', i - 1, 0, -1)
    elseif line.hl then
      vim.api.nvim_buf_add_highlight(self.buf, self.ns, line.hl, i - 1, 0, -1)
    end
  end

  vim.bo[self.buf].modifiable = false

  self:update_hint()
end

---Refresh the pinned hint window contents based on current cursor context.
function Buffer:update_hint()
  if not self.view then return end
  if not self.hint_buf or not vim.api.nvim_buf_is_valid(self.hint_buf) then return end

  local line = self:get_cursor_line()
  local line_type = line and line.type or nil
  local selectable = line ~= nil and (line.type == 'commit' or line.type == 'file' or line.type == 'committed_file')
  local hints = require('gitbutler.ui.hints')
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
  if not self.win or not vim.api.nvim_win_is_valid(self.win) then return nil end
  local row = vim.api.nvim_win_get_cursor(self.win)[1]
  return self.lines[row]
end

---Get the branch context for the line under the cursor.
---Walk up from cursor to find the nearest branch header.
---@return table? branch data
function Buffer:get_cursor_branch()
  if not self.win or not vim.api.nvim_win_is_valid(self.win) then return nil end
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
  if not self.win or not vim.api.nvim_win_is_valid(self.win) then return nil end
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
  if not line or not line.data then return nil end
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
    if not self.win or not vim.api.nvim_win_is_valid(self.win) then return end
    row = vim.api.nvim_win_get_cursor(self.win)[1]
  end
  local line = self.lines[row]
  local key = self:select_key(line)
  if not key then return false end
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
  local mappings = config.values.keymaps.status or {}
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

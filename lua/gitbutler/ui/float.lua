local config = require('gitbutler.config')

local M = {}

---Create a floating window with a new buffer.
---@param opts? {width?: number, height?: number, border?: string, title?: string, relative?: string, row?: number, col?: number, style?: string, enter?: boolean, buf?: number}
---@return number buf, number win
function M.open(opts)
  opts = opts or {}
  local ui = vim.api.nvim_list_uis()[1] or { width = 80, height = 24 }

  local width = opts.width or config.values.float.width
  local height = opts.height or config.values.float.height

  -- Resolve fractional dimensions
  if width <= 1 then width = math.floor(ui.width * width) end
  if height <= 1 then height = math.floor(ui.height * height) end

  local row = opts.row or math.floor((ui.height - height) / 2)
  local col = opts.col or math.floor((ui.width - width) / 2)

  local buf = opts.buf or vim.api.nvim_create_buf(false, true)

  local win_opts = {
    relative = opts.relative or config.values.float.relative or 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    border = opts.border or config.values.float.border or 'rounded',
    style = opts.style or config.values.float.style or 'minimal',
    title = opts.title and (' ' .. opts.title .. ' ') or nil,
    title_pos = opts.title and 'center' or nil,
  }

  local win = vim.api.nvim_open_win(buf, opts.enter ~= false, win_opts)
  return buf, win
end

---Open a small input float near the cursor for text entry (commit message, branch name, etc).
---@param opts {title: string, on_submit: fun(text: string), on_abort?: fun(), height?: number, width?: number, content?: string[]}
---@return number buf, number win
function M.input(opts)
  local buf, win = M.open({
    title = opts.title,
    width = opts.width or config.values.input_float.width,
    height = opts.height or config.values.input_float.height,
    relative = 'editor',
    border = config.values.input_float.border,
    style = config.values.input_float.style,
  })

  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].filetype = 'gitbutler-input'

  if opts.content then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, opts.content)
  end

  vim.cmd('startinsert')

  -- Submit: ctrl-c ctrl-c
  vim.keymap.set({ 'n', 'i' }, '<C-c><C-c>', function()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local text = vim.trim(table.concat(lines, '\n'))
    vim.api.nvim_win_close(win, true)
    vim.api.nvim_buf_delete(buf, { force = true })
    if text ~= '' then
      opts.on_submit(text)
    end
  end, { buffer = buf })

  -- Abort: ctrl-c ctrl-k or q in normal mode
  local function abort()
    vim.api.nvim_win_close(win, true)
    vim.api.nvim_buf_delete(buf, { force = true })
    if opts.on_abort then opts.on_abort() end
  end

  vim.keymap.set({ 'n', 'i' }, '<C-c><C-k>', abort, { buffer = buf })
  vim.keymap.set('n', 'q', abort, { buffer = buf })

  return buf, win
end

---Show a picker popup near the cursor with a list of items.
---@param opts {title: string, items: string[], on_select: fun(item: string, index: number), on_abort?: fun()}
---@return number buf, number win
function M.picker(opts)
  local items = opts.items
  local height = math.min(#items, 15)
  local width = opts.width or config.values.picker.width

  -- Calculate max item width
  for _, item in ipairs(items) do
    width = math.max(width or 0, #item + 4)
  end

  local buf, win = M.open({
    title = opts.title,
    width = width,
    height = height,
    relative = 'editor',
    border = config.values.picker.border,
    style = config.values.picker.style,
  })

  -- Render items with prefix
  local lines = {}
  for i, item in ipairs(items) do
    lines[i] = '  ' .. item
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].filetype = 'gitbutler-picker'

  -- Highlight current line
  vim.wo[win].cursorline = true

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end

  -- Select with enter
  vim.keymap.set('n', '<CR>', function()
    local line = vim.api.nvim_win_get_cursor(win)[1]
    close()
    opts.on_select(items[line], line)
  end, { buffer = buf })

  -- Abort with q or escape
  local function abort()
    close()
    if opts.on_abort then opts.on_abort() end
  end

  vim.keymap.set('n', 'q', abort, { buffer = buf })
  vim.keymap.set('n', '<Esc>', abort, { buffer = buf })

  return buf, win
end

return M

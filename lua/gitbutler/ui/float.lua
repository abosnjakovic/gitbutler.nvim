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

  -- Resolve fractional dimensions (values < 1 are treated as fractions of screen size)
  if width < 1 then
    width = math.floor(ui.width * width)
  end
  if height < 1 then
    height = math.floor(ui.height * height)
  end

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
---When single_line is true, Enter submits and height defaults to 1.
---Otherwise, Ctrl-C Ctrl-C submits (for multi-line input like commit messages).
---@param opts {title: string, on_submit: fun(text: string), on_abort?: fun(), height?: number, width?: number, content?: string[], single_line?: boolean}
---@return number buf, number win
function M.input(opts)
  local is_single = opts.single_line == true
  -- Advertise the submit key in the title: single-line takes <CR>, multi-line
  -- (commit messages, PR bodies) needs Ctrl-C Ctrl-C since <CR> inserts a line.
  local hint = is_single and '  (⏎ save · Esc cancel)' or '  (Ctrl-C Ctrl-C save · Esc cancel)'
  local buf, win = M.open({
    title = (opts.title or 'Input') .. hint,
    width = opts.width or config.values.input_float.width,
    height = is_single and 1 or (opts.height or config.values.input_float.height),
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

  local function submit()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local text = vim.trim(table.concat(lines, '\n'))
    vim.cmd('stopinsert')
    vim.api.nvim_win_close(win, true)
    vim.api.nvim_buf_delete(buf, { force = true })
    if text ~= '' then
      opts.on_submit(text)
    end
  end

  local function abort()
    vim.cmd('stopinsert')
    vim.api.nvim_win_close(win, true)
    vim.api.nvim_buf_delete(buf, { force = true })
    if opts.on_abort then
      opts.on_abort()
    end
  end

  if is_single then
    -- Single-line: Enter submits, Esc aborts
    vim.keymap.set('i', '<CR>', submit, { buffer = buf })
    vim.keymap.set('n', '<CR>', submit, { buffer = buf })
  end

  -- Ctrl-C Ctrl-C always works as submit (multi-line and single-line)
  vim.keymap.set({ 'n', 'i' }, '<C-c><C-c>', submit, { buffer = buf })
  vim.keymap.set({ 'n', 'i' }, '<C-c><C-k>', abort, { buffer = buf })
  vim.keymap.set('n', 'q', abort, { buffer = buf })
  vim.keymap.set('n', '<Esc>', abort, { buffer = buf })

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
    if opts.on_abort then
      opts.on_abort()
    end
  end

  vim.keymap.set('n', 'q', abort, { buffer = buf })
  vim.keymap.set('n', '<Esc>', abort, { buffer = buf })

  return buf, win
end

---Fuzzy-filter `items` by `query`. Empty query passes everything through.
---@param items string[]
---@param query string
---@return string[]
function M._fuzzy_filter(items, query)
  if query == '' then
    return items
  end
  return vim.fn.matchfuzzy(items, query)
end

---Fuzzy picker: a 1-line prompt float (insert mode) stacked above a list
---float. Typing refilters, <C-n>/<C-p>/<Down>/<Up> move the selection,
---<CR> confirms the highlighted item, <Esc> aborts. Both windows always
---close together. Returns a handle used by tests to drive it directly.
---@param opts {title?: string, items: string[], on_select: fun(item: string, index: number), on_abort?: fun()}
---@return {prompt_buf: number, prompt_win: number, list_buf: number, list_win: number, refilter: fun(), confirm: fun(), abort: fun(), move: fun(delta: number)}
function M.fuzzy_picker(opts)
  local items = opts.items or {}
  local ui = vim.api.nvim_list_uis()[1] or { width = 80, height = 24 }
  local width = config.values.picker.width or 40
  for _, item in ipairs(items) do
    width = math.max(width, #item + 4)
  end
  width = math.min(width, ui.width - 4)

  local list_height = math.max(1, math.min(#items, 15))
  -- prompt (1 + border 2) above the list (list_height + border 2)
  local row = math.max(0, math.floor((ui.height - (list_height + 5)) / 2))
  local col = math.max(0, math.floor((ui.width - width) / 2))

  local prompt_buf, prompt_win = M.open({
    title = opts.title,
    width = width,
    height = 1,
    relative = 'editor',
    row = row,
    col = col,
    border = config.values.picker.border,
    style = config.values.picker.style,
  })
  local list_buf, list_win = M.open({
    width = width,
    height = list_height,
    relative = 'editor',
    row = row + 3,
    col = col,
    border = config.values.picker.border,
    style = config.values.picker.style,
    enter = false,
  })

  vim.bo[prompt_buf].buftype = 'nofile'
  vim.bo[prompt_buf].filetype = 'gitbutler-picker'
  vim.bo[list_buf].buftype = 'nofile'
  vim.bo[list_buf].filetype = 'gitbutler-picker'
  vim.wo[list_win].cursorline = true

  local filtered = items
  local selection = 1

  local function render()
    local lines = {}
    for i, item in ipairs(filtered) do
      lines[i] = '  ' .. item
    end
    vim.bo[list_buf].modifiable = true
    vim.api.nvim_buf_set_lines(list_buf, 0, -1, false, lines)
    vim.bo[list_buf].modifiable = false
    if #filtered > 0 and vim.api.nvim_win_is_valid(list_win) then
      vim.api.nvim_win_set_cursor(list_win, { math.min(selection, #filtered), 0 })
    end
  end

  -- Both windows always live and die together; `closed` makes close/confirm/
  -- abort idempotent so the WinClosed autocmds can fire during a normal close
  -- (or the user can :q one float) without double-running callbacks.
  local closed = false

  local function close()
    if closed then
      return
    end
    closed = true
    vim.cmd('stopinsert')
    for _, win in ipairs({ prompt_win, list_win }) do
      if vim.api.nvim_win_is_valid(win) then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
    for _, buf in ipairs({ prompt_buf, list_buf }) do
      if vim.api.nvim_buf_is_valid(buf) then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end
  end

  local function confirm()
    local item = filtered[selection]
    if closed or not item then
      return
    end
    close()
    opts.on_select(item, selection)
  end

  local function abort()
    if closed then
      return
    end
    close()
    if opts.on_abort then
      opts.on_abort()
    end
  end

  -- Externally-closed window (:q, <C-w>c) on either float aborts the picker
  -- so the sibling float never leaks.
  for _, win in ipairs({ prompt_win, list_win }) do
    vim.api.nvim_create_autocmd('WinClosed', {
      pattern = tostring(win),
      once = true,
      callback = abort,
    })
  end

  local function move(delta)
    if #filtered == 0 then
      return
    end
    selection = ((selection - 1 + delta) % #filtered) + 1
    if vim.api.nvim_win_is_valid(list_win) then
      vim.api.nvim_win_set_cursor(list_win, { selection, 0 })
    end
  end

  local function refilter()
    local query = vim.api.nvim_buf_get_lines(prompt_buf, 0, 1, false)[1] or ''
    filtered = M._fuzzy_filter(items, query)
    selection = 1
    render()
  end

  render()
  vim.cmd('startinsert')

  vim.api.nvim_create_autocmd('TextChangedI', { buffer = prompt_buf, callback = refilter })

  for _, key in ipairs({ '<C-n>', '<Down>' }) do
    vim.keymap.set('i', key, function()
      move(1)
    end, { buffer = prompt_buf })
  end
  for _, key in ipairs({ '<C-p>', '<Up>' }) do
    vim.keymap.set('i', key, function()
      move(-1)
    end, { buffer = prompt_buf })
  end
  vim.keymap.set({ 'i', 'n' }, '<CR>', confirm, { buffer = prompt_buf })
  vim.keymap.set({ 'i', 'n' }, '<Esc>', abort, { buffer = prompt_buf })
  vim.keymap.set('n', '<CR>', confirm, { buffer = list_buf })
  vim.keymap.set('n', '<Esc>', abort, { buffer = list_buf })
  vim.keymap.set('n', 'q', abort, { buffer = list_buf })

  return {
    prompt_buf = prompt_buf,
    prompt_win = prompt_win,
    list_buf = list_buf,
    list_win = list_win,
    refilter = refilter,
    confirm = confirm,
    abort = abort,
    move = move,
  }
end

return M

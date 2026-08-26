---Animated spinner for async operations that take noticeable time (gh
---shell-outs, multi-step pipelines like land or direct-to-main).
---
---One shared bottom-right float holds every in-flight operation, one line each.
---Each `start` used to open its own float at the same fixed position, so two
---concurrent operations drew on top of each other; a single window with N lines
---cannot overlap by construction, and the reflow is one `set_config`.

local M = {}

local FRAMES = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }
local INTERVAL_MS = 80
local MIN_WIDTH = 30

---In-flight operations, oldest first. Each handle owns one entry.
---@type { label: string }[]
M.active = {}

---The shared float. Internal; exposed so tests can inspect what is on screen.
M.buf = nil
M.win = nil

local timer
local frame = 1

local function teardown()
  if timer and not timer:is_closing() then
    timer:stop()
    timer:close()
  end
  timer = nil
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    pcall(vim.api.nvim_win_close, M.win, true)
  end
  M.win = nil
  if M.buf and vim.api.nvim_buf_is_valid(M.buf) then
    pcall(vim.api.nvim_buf_delete, M.buf, { force = true })
  end
  M.buf = nil
end

---Geometry for the current entry count. The bottom edge stays put as the box
---grows upward, so starting a second operation never shifts the first line.
local function geometry()
  local width = MIN_WIDTH
  for _, entry in ipairs(M.active) do
    width = math.max(width, vim.fn.strdisplaywidth(entry.label) + 6)
  end
  width = math.min(width, math.max(vim.o.columns - 4, MIN_WIDTH))
  local height = #M.active
  return {
    relative = 'editor',
    row = math.max(vim.o.lines - 3 - height, 1),
    col = math.max(vim.o.columns - width - 2, 0),
    width = width,
    height = height,
  }
end

local function render()
  if #M.active == 0 then
    return teardown()
  end

  if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then
    M.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[M.buf].buftype = 'nofile'
    vim.bo[M.buf].bufhidden = 'wipe'
  end

  local geo = geometry()
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    pcall(vim.api.nvim_win_set_config, M.win, geo)
  else
    local ok, win = pcall(
      vim.api.nvim_open_win,
      M.buf,
      false,
      vim.tbl_extend('force', geo, {
        style = 'minimal',
        border = 'rounded',
        focusable = false,
        noautocmd = true,
      })
    )
    if not ok then
      -- Headless or no UI: keep tracking entries, just draw nothing.
      M.win = nil
      return
    end
    M.win = win
    vim.wo[M.win].winhighlight = 'NormalFloat:Comment,FloatBorder:Comment'
  end

  local text = {}
  for _, entry in ipairs(M.active) do
    table.insert(text, FRAMES[frame] .. '  ' .. entry.label)
  end
  pcall(vim.api.nvim_buf_set_lines, M.buf, 0, -1, false, text)
end

local function ensure_timer()
  if timer then
    return
  end
  timer = vim.uv.new_timer()
  if not timer then
    return
  end
  timer:start(
    INTERVAL_MS,
    INTERVAL_MS,
    vim.schedule_wrap(function()
      frame = frame % #FRAMES + 1
      render()
    end)
  )
end

---@class GitButlerSpinnerHandle
---@field update fun(self: GitButlerSpinnerHandle, label: string)
---@field stop fun(self: GitButlerSpinnerHandle, final_msg?: string)

---@param label string
---@return GitButlerSpinnerHandle
function M.start(label)
  local entry = { label = label or '' }
  table.insert(M.active, entry)
  render()
  ensure_timer()

  local handle = {}

  function handle:update(new_label)
    entry.label = new_label or entry.label
    -- Re-render now so the label change lands without waiting for the next tick.
    render()
  end

  -- Idempotent: a double stop (error path plus a chained callback) must not
  -- re-notify or reflow.
  function handle:stop(final_msg)
    local removed = false
    for i, e in ipairs(M.active) do
      if e == entry then
        table.remove(M.active, i)
        removed = true
        break
      end
    end
    if not removed then
      return
    end
    render()
    if final_msg then
      vim.notify(final_msg, vim.log.levels.INFO)
    end
  end

  return handle
end

return M

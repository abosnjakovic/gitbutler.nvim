---Small animated spinner shown in a bottom-right floating window.
---Use for async operations that take noticeable time (gh shell-outs,
---multi-step pipelines). Cheap and self-contained — no external state.

local M = {}

local FRAMES = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }
local INTERVAL_MS = 80

---@class GitButlerSpinnerHandle
---@field update fun(self: GitButlerSpinnerHandle, label: string)
---@field stop fun(self: GitButlerSpinnerHandle, final_msg?: string)

---@param label string
---@return GitButlerSpinnerHandle
function M.start(label)
  local frame = 1
  local current_label = label or ''

  local width = math.max(#current_label + 6, 30)
  local buf = vim.api.nvim_create_buf(false, true)
  local row = math.max(vim.o.lines - 4, 1)
  local col = math.max(vim.o.columns - width - 2, 0)

  local ok_win, win = pcall(vim.api.nvim_open_win, buf, false, {
    relative = 'editor',
    row = row,
    col = col,
    width = width,
    height = 1,
    style = 'minimal',
    border = 'rounded',
    focusable = false,
    noautocmd = true,
  })

  if not ok_win then
    -- Headless or no UI — fall back to a no-op handle.
    return {
      update = function() end,
      stop = function(_, final_msg)
        if final_msg then
          vim.notify(final_msg, vim.log.levels.INFO)
        end
      end,
    }
  end

  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.wo[win].winhighlight = 'NormalFloat:Comment,FloatBorder:Comment'

  local function render()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    local text = FRAMES[frame] .. '  ' .. current_label
    pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, { text })
  end

  render()

  local timer = vim.uv.new_timer()
  if timer then
    timer:start(
      INTERVAL_MS,
      INTERVAL_MS,
      vim.schedule_wrap(function()
        frame = frame % #FRAMES + 1
        render()
      end)
    )
  end

  local stopped = false
  local handle = {}

  function handle:update(new_label)
    current_label = new_label or current_label
    -- Re-render immediately so label change is visible without waiting for the next tick.
    vim.schedule(render)
  end

  function handle:stop(final_msg)
    if stopped then
      return
    end
    stopped = true
    if timer and not timer:is_closing() then
      timer:stop()
      timer:close()
    end
    if win and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
    if buf and vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
    if final_msg then
      vim.notify(final_msg, vim.log.levels.INFO)
    end
  end

  return handle
end

return M

local buffer_mod = require('gitbutler.ui.buffer')
local forge = require('gitbutler.forge')
local spinner = require('gitbutler.ui.spinner')
local status_mod = require('gitbutler.ui.status')

local M = {}

---@type GitButlerBuffer?
M.instance = nil

---Format an ISO timestamp pair as a duration string ("2m14s") if both present.
local function duration(started, completed)
  if not started or not completed then
    return ''
  end
  local function parse(ts)
    local y, mo, d, h, mi, s = ts:match('(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)')
    if not y then
      return nil
    end
    return os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = s })
  end
  local a, b = parse(started), parse(completed)
  if not a or not b or b < a then
    return ''
  end
  local secs = b - a
  local m = math.floor(secs / 60)
  local s = secs % 60
  return string.format('%dm%02ds', m, s)
end

---Build buffer lines for a branch + its checks.
---@param branch string
---@param checks table[]
---@return GitButlerLine[]
function M.build_lines(branch, checks)
  local lines = {}
  local function add(text, hl, type_, data)
    table.insert(lines, { text = text, hl = hl, type = type_, data = data, indent = 0 })
  end

  add('GitButler CI — ' .. branch, 'GitButlerSection', 'section_header', nil)
  add('', nil, 'blank', nil)

  if #checks == 0 then
    add('no checks for this branch', 'GitButlerHelp', 'info', nil)
    return lines
  end

  local name_width = 30
  for _, check in ipairs(checks) do
    local n = #(check.name or '?')
    if n > name_width then
      name_width = n
    end
  end

  for _, check in ipairs(checks) do
    local glyph, hl = status_mod.ci_glyph(check)
    local dur = duration(check.started_at, check.completed_at)
    local right = dur ~= '' and dur or (check.status or '')
    local text = string.format('%s  %-' .. name_width .. 's  %s', glyph, check.name or '?', right)
    add(text, hl, 'ci_check', check)
  end

  return lines
end

local adapter_for_session

---Open the CI view for `branch`. If `injected_adapter` is provided, use it (tests).
---@param branch string
---@param injected_adapter? table
function M.open(branch, injected_adapter)
  local adapter = injected_adapter or adapter_for_session or forge.detect_from_remote()
  if not adapter then
    vim.notify('gitbutler: no forge adapter for this remote', vim.log.levels.WARN)
    return
  end
  adapter_for_session = adapter

  local buf = buffer_mod.Buffer.new()
  buf.view = 'ci'
  M.instance = buf

  buf:on('open_log', function(b)
    local line = b:get_cursor_line()
    if not line or line.type ~= 'ci_check' or not line.data then
      return
    end
    local sp = spinner.start('fetching log: ' .. (line.data.name or '?'))
    adapter.view_log(line.data.id, function(err, text)
      sp:stop()
      if err then
        vim.notify('gh view log: ' .. err, vim.log.levels.ERROR)
        return
      end
      vim.cmd('belowright split')
      local log_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_win_set_buf(0, log_buf)
      vim.api.nvim_buf_set_lines(log_buf, 0, -1, false, vim.split(text or '', '\n'))
      vim.bo[log_buf].buftype = 'nofile'
      vim.bo[log_buf].bufhidden = 'wipe'
      vim.bo[log_buf].filetype = 'log'
      vim.keymap.set('n', 'q', '<cmd>close<CR>', { buffer = log_buf })
    end)
  end)

  buf:on('open_in_browser', function(b)
    local line = b:get_cursor_line()
    if line and line.type == 'ci_check' and line.data and line.data.url then
      adapter.open_in_browser(line.data.url)
    end
  end)

  buf:on('rerun', function(b)
    local line = b:get_cursor_line()
    if not line or line.type ~= 'ci_check' or not line.data then
      return
    end
    local sp = spinner.start('re-running: ' .. (line.data.name or '?'))
    adapter.rerun(line.data.id, function(err)
      sp:stop()
      if err then
        vim.notify('gh rerun: ' .. err, vim.log.levels.ERROR)
        return
      end
      vim.notify('gitbutler: rerun queued', vim.log.levels.INFO)
      M.refresh(branch, adapter)
    end)
  end)

  buf:on('refresh', function()
    M.refresh(branch, adapter)
  end)
  buf:on('close', function()
    M.close()
  end)

  buf:open()
  M.refresh(branch, adapter)
end

function M.refresh(branch, adapter)
  if not M.instance then
    return
  end
  local buf = M.instance
  local sp = spinner.start('fetching CI for ' .. branch)
  adapter.list_checks(branch, function(err, checks)
    sp:stop()
    if err then
      vim.notify('gh list checks: ' .. err, vim.log.levels.ERROR)
      return
    end
    buf:render(M.build_lines(branch, checks or {}))
  end)
end

function M.close()
  if M.instance then
    M.instance:close()
    M.instance = nil
  end
end

return M

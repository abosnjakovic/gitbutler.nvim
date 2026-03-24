local cli = require('gitbutler.cli')
local float = require('gitbutler.ui.float')

local M = {}

local function notify(action, err)
  if err then
    vim.notify('gitbutler ' .. action .. ': ' .. err, vim.log.levels.ERROR)
  else
    vim.notify('gitbutler: ' .. action .. ' done', vim.log.levels.INFO)
  end
end

local function format_time(timestamp)
  if not timestamp or type(timestamp) ~= 'number' then return '' end
  return os.date('%Y-%m-%d %H:%M', timestamp)
end

---Open the operations log view.
function M.open()
  cli.oplog_list(function(err, data)
    if err then
      vim.notify('gitbutler oplog: ' .. err, vim.log.levels.ERROR)
      return
    end

    if type(data) ~= 'table' or #data == 0 then
      vim.notify('gitbutler: no operations in log', vim.log.levels.INFO)
      return
    end

    -- Build display lines
    local entries = {}
    local display = {}

    for _, entry in ipairs(data) do
      local id_short = (entry.id or ''):sub(1, 8)
      local title = entry.details and entry.details.title or '(unknown)'
      local body = entry.details and entry.details.body or nil
      local time = format_time(entry.createdAt)

      local line = id_short .. '  ' .. time .. '  ' .. title
      if body and type(body) == 'string' and body ~= '' then
        line = line .. '  — ' .. body:match('^([^\n]*)') or body
      end

      table.insert(display, line)
      table.insert(entries, {
        id = entry.id,
        id_short = id_short,
        title = title,
        body = body,
        time = time,
      })
    end

    local width = 0
    for _, l in ipairs(display) do
      width = math.max(width, #l + 4)
    end

    local buf, win = float.open({
      title = 'Operations Log  (r)estore (s)napshot (q)uit',
      width = math.max(width, 55),
      height = math.min(#display + 1, 25),
      border = 'rounded',
    })

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, display)
    vim.bo[buf].modifiable = false
    vim.bo[buf].buftype = 'nofile'
    vim.bo[buf].filetype = 'gitbutler-oplog'
    vim.wo[win].cursorline = true

    -- Highlights
    local ns = vim.api.nvim_create_namespace('gitbutler-oplog')
    for i, _ in ipairs(entries) do
      -- Highlight the sha portion
      vim.api.nvim_buf_add_highlight(buf, ns, 'GitButlerCommitHash', i - 1, 0, 8)
    end

    local function close()
      if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
      if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
    end

    local function get_entry()
      local row = vim.api.nvim_win_get_cursor(win)[1]
      return entries[row]
    end

    -- Restore to snapshot
    vim.keymap.set('n', 'r', function()
      local e = get_entry()
      if not e then return end

      vim.ui.select({ 'Yes', 'No' }, {
        prompt = 'Restore to ' .. e.id_short .. ' (' .. e.title .. ')?',
      }, function(choice)
        if choice ~= 'Yes' then return end
        close()
        cli.oplog_restore(e.id, function(restore_err, _)
          notify('restore ' .. e.id_short, restore_err)
          if not restore_err then
            local status = require('gitbutler.ui.status')
            status.refresh()
          end
        end)
      end)
    end, { buffer = buf })

    -- Create snapshot
    vim.keymap.set('n', 's', function()
      close()
      float.input({
        title = 'Snapshot message',
        height = 1,
        on_submit = function(message)
          cli.oplog_snapshot(message, function(snap_err, _)
            notify('snapshot', snap_err)
            if not snap_err then
              vim.defer_fn(function() M.open() end, 200)
            end
          end)
        end,
      })
    end, { buffer = buf })

    -- Close
    vim.keymap.set('n', 'q', close, { buffer = buf })
    vim.keymap.set('n', '<Esc>', close, { buffer = buf })
  end)
end

return M

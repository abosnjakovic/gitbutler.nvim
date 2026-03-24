local cli = require('gitbutler.cli')
local float = require('gitbutler.ui.float')

local M = {}

local function refresh_status()
  local status = require('gitbutler.ui.status')
  status.refresh()
end

local function notify(action, err)
  if err then
    vim.notify('gitbutler ' .. action .. ': ' .. err, vim.log.levels.ERROR)
  else
    vim.notify('gitbutler: ' .. action .. ' done', vim.log.levels.INFO)
  end
end

---Open the branch management popup.
---Shows applied and unapplied branches with actions.
function M.open()
  cli.branch_list(function(err, data)
    if err then
      vim.notify('gitbutler: ' .. err, vim.log.levels.ERROR)
      return
    end

    local entries = {} -- { name, applied, stack_id, merges_cleanly, commits_ahead, last_author }

    for _, stack in ipairs(data.appliedStacks or {}) do
      for _, head in ipairs(stack.heads or {}) do
        table.insert(entries, {
          name = head.name,
          applied = true,
          stack_id = stack.id,
          merges_cleanly = head.mergesCleanly,
          commits_ahead = head.commitsAhead,
          last_author = head.lastAuthor and head.lastAuthor.name or nil,
        })
      end
    end

    for _, branch in ipairs(data.branches or {}) do
      table.insert(entries, {
        name = branch.name,
        applied = false,
        merges_cleanly = branch.mergesCleanly,
        commits_ahead = branch.commitsAhead,
        last_author = branch.lastAuthor and branch.lastAuthor.name or nil,
        has_local = branch.hasLocal,
      })
    end

    if #entries == 0 then
      vim.notify('gitbutler: no branches found', vim.log.levels.WARN)
      return
    end

    -- Build display lines
    local display = {}
    local max_name = 0
    for _, e in ipairs(entries) do
      max_name = math.max(max_name, #e.name)
    end

    for _, e in ipairs(entries) do
      local status_icon = e.applied and '●' or '○'
      local details = {}
      if e.commits_ahead and type(e.commits_ahead) == 'number' then
        table.insert(details, e.commits_ahead .. ' ahead')
      end
      if e.merges_cleanly == false then
        table.insert(details, 'conflicts')
      end
      local detail_str = #details > 0 and ('  ' .. table.concat(details, ', ')) or ''
      local padding = string.rep(' ', max_name - #e.name + 1)
      table.insert(display, status_icon .. ' ' .. e.name .. padding .. detail_str)
    end

    local width = 0
    for _, l in ipairs(display) do
      width = math.max(width, #l + 4)
    end

    local buf, win = float.open({
      title = 'Branches  (a)pply (u)napply (n)ew (d)elete (r)ename',
      width = math.max(width, 55),
      height = math.min(#display + 1, 20),
      border = 'rounded',
    })

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, display)
    vim.bo[buf].modifiable = false
    vim.bo[buf].buftype = 'nofile'
    vim.bo[buf].filetype = 'gitbutler-branches'
    vim.wo[win].cursorline = true

    -- Highlight applied vs unapplied
    local ns = vim.api.nvim_create_namespace('gitbutler-branches')
    for i, e in ipairs(entries) do
      local hl = e.applied and 'GitButlerBranchApplied' or 'GitButlerBranchUnapplied'
      vim.api.nvim_buf_add_highlight(buf, ns, hl, i - 1, 0, -1)
    end

    local function close()
      if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
      if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
    end

    local function get_entry()
      local row = vim.api.nvim_win_get_cursor(win)[1]
      return entries[row]
    end

    local function reopen()
      close()
      refresh_status()
      -- Small delay to let but process, then reopen
      vim.defer_fn(function() M.open() end, 200)
    end

    -- Apply branch
    vim.keymap.set('n', 'a', function()
      local e = get_entry()
      if not e or e.applied then return end
      close()
      cli.apply(e.name, function(apply_err, _)
        notify('apply ' .. e.name, apply_err)
        if not apply_err then
          refresh_status()
          vim.defer_fn(function() M.open() end, 200)
        end
      end)
    end, { buffer = buf })

    -- Unapply branch
    vim.keymap.set('n', 'u', function()
      local e = get_entry()
      if not e or not e.applied then return end
      close()
      cli.unapply(e.name, function(unapply_err, _)
        notify('unapply ' .. e.name, unapply_err)
        if not unapply_err then
          refresh_status()
          vim.defer_fn(function() M.open() end, 200)
        end
      end)
    end, { buffer = buf })

    -- New branch
    vim.keymap.set('n', 'n', function()
      close()
      float.input({
        title = 'New branch name',
        height = 1,
        on_submit = function(name)
          cli.branch_new(name, function(new_err, _)
            notify('branch new ' .. name, new_err)
            if not new_err then reopen() end
          end)
        end,
      })
    end, { buffer = buf })

    -- Delete branch
    vim.keymap.set('n', 'd', function()
      local e = get_entry()
      if not e then return end
      vim.ui.select({ 'Yes', 'No' }, { prompt = 'Delete branch ' .. e.name .. '?' }, function(choice)
        if choice ~= 'Yes' then return end
        close()
        cli.branch_delete(e.name, function(del_err, _)
          notify('delete ' .. e.name, del_err)
          if not del_err then reopen() end
        end)
      end)
    end, { buffer = buf })

    -- Rename branch
    vim.keymap.set('n', 'r', function()
      local e = get_entry()
      if not e then return end
      close()
      float.input({
        title = 'Rename ' .. e.name,
        content = { e.name },
        height = 1,
        on_submit = function(new_name)
          cli.run({ 'reword', e.name, '-m', new_name, '--json' }, function(ren_err, _)
            notify('rename → ' .. new_name, ren_err)
            if not ren_err then reopen() end
          end)
        end,
      })
    end, { buffer = buf })

    -- Close
    vim.keymap.set('n', 'q', close, { buffer = buf })
    vim.keymap.set('n', '<Esc>', close, { buffer = buf })

    -- Enter: show branch details
    vim.keymap.set('n', '<CR>', function()
      local e = get_entry()
      if not e then return end
      close()
      -- Open status filtered to this branch context
      vim.notify('gitbutler: ' .. e.name .. (e.applied and ' (applied)' or ' (unapplied)'), vim.log.levels.INFO)
    end, { buffer = buf })
  end)
end

return M

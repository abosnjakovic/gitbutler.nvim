local M = {}

function M.setup(opts)
  local config = require('gitbutler.config')
  config.setup(opts)

  local highlights = require('gitbutler.ui.highlights')
  highlights.setup()

  -- User commands
  vim.api.nvim_create_user_command('Butler', function()
    require('gitbutler.ui.status').toggle()
  end, { desc = 'Toggle GitButler status' })

  vim.api.nvim_create_user_command('ButlerAbsorb', function()
    require('gitbutler.cli').absorb(function(err, _)
      if err then
        vim.notify('gitbutler absorb: ' .. err, vim.log.levels.ERROR)
      else
        vim.notify('gitbutler: absorb done', vim.log.levels.INFO)
        require('gitbutler.ui.status').refresh()
      end
    end)
  end, { desc = 'GitButler absorb' })

  vim.api.nvim_create_user_command('ButlerPush', function()
    require('gitbutler.cli').push(nil, function(err, _)
      if err then
        vim.notify('gitbutler push: ' .. err, vim.log.levels.ERROR)
      else
        vim.notify('gitbutler: push done', vim.log.levels.INFO)
      end
    end)
  end, { desc = 'GitButler push all' })

  vim.api.nvim_create_user_command('ButlerPull', function()
    require('gitbutler.cli').pull(function(err, _)
      if err then
        vim.notify('gitbutler pull: ' .. err, vim.log.levels.ERROR)
      else
        vim.notify('gitbutler: pull done', vim.log.levels.INFO)
        require('gitbutler.ui.status').refresh()
      end
    end)
  end, { desc = 'GitButler pull' })

  vim.api.nvim_create_user_command('ButlerUndo', function()
    require('gitbutler.cli').undo(function(err, _)
      if err then
        vim.notify('gitbutler undo: ' .. err, vim.log.levels.ERROR)
      else
        vim.notify('gitbutler: undo done', vim.log.levels.INFO)
        require('gitbutler.ui.status').refresh()
      end
    end)
  end, { desc = 'GitButler undo' })

  vim.api.nvim_create_user_command('ButlerBranches', function()
    require('gitbutler.ui.branch').open()
  end, { desc = 'GitButler branch management' })

  vim.api.nvim_create_user_command('ButlerLog', function(cmd)
    local branch = cmd.args ~= '' and cmd.args or nil
    if branch then
      require('gitbutler.ui.log').open(branch)
    else
      -- Default to first applied branch
      require('gitbutler.cli').branch_list(function(err, data)
        if err then
          vim.notify('gitbutler: ' .. err, vim.log.levels.ERROR)
          return
        end
        local name
        for _, stack in ipairs(data.appliedStacks or {}) do
          for _, head in ipairs(stack.heads or {}) do
            if head.name then
              name = head.name
              break
            end
          end
          if name then
            break
          end
        end
        if name then
          require('gitbutler.ui.log').open(name)
        else
          vim.notify('gitbutler: no applied branches', vim.log.levels.WARN)
        end
      end)
    end
  end, { nargs = '?', desc = 'GitButler commit log' })

  vim.api.nvim_create_user_command('ButlerOplog', function()
    require('gitbutler.ui.oplog').open()
  end, { desc = 'GitButler operations log' })

  vim.api.nvim_create_user_command('ButlerTimeline', function()
    require('gitbutler.ui.timeline').open()
  end, { desc = 'GitButler commit timeline' })

  vim.api.nvim_create_user_command('ButlerAutoMerge', function(cmd)
    local name = cmd.args ~= '' and cmd.args or nil
    if not name then
      vim.notify('gitbutler: branch name required (`:ButlerAutoMerge <branch>`)', vim.log.levels.WARN)
      return
    end
    require('gitbutler.actions').pr_auto_merge(name)
  end, { nargs = '?', desc = 'GitButler toggle PR auto-merge' })

  vim.api.nvim_create_user_command('ButlerCI', function(cmd)
    local name = cmd.args ~= '' and cmd.args or nil
    if not name then
      vim.notify('gitbutler: branch name required (`:ButlerCI <branch>`)', vim.log.levels.WARN)
      return
    end
    require('gitbutler.ui.ci').open(name)
  end, { nargs = '?', desc = 'GitButler CI view for branch' })
end

return M

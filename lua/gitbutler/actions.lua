local cli = require('gitbutler.cli')
local float = require('gitbutler.ui.float')

local M = {}

local function refresh()
  local status = require('gitbutler.ui.status')
  status.refresh()
end

local function notify_result(action, err, _result)
  if err then
    vim.notify('gitbutler ' .. action .. ': ' .. err, vim.log.levels.ERROR)
  else
    vim.notify('gitbutler: ' .. action .. ' done', vim.log.levels.INFO)
    refresh()
  end
end

---Extract branch names from `but branch --json` output.
---Shape: { appliedStacks: [{ heads: [{ name }] }], branches: [{ name }] }
local function extract_branch_names(data)
  local names = {}
  for _, stack in ipairs(data.appliedStacks or {}) do
    for _, head in ipairs(stack.heads or {}) do
      if head.name then
        table.insert(names, head.name)
      end
    end
  end
  -- Also include unapplied branches
  for _, b in ipairs(data.branches or {}) do
    if b.name then
      table.insert(names, b.name)
    end
  end
  return names
end

---Open the file under cursor.
function M.open_file(buf)
  local line = buf:get_cursor_line()
  if not line or not line.data or not line.data.path then return end
  local path = line.data.path

  buf:close()
  local status = require('gitbutler.ui.status')
  status.instance = nil
  vim.cmd('edit ' .. vim.fn.fnameescape(path))
end

---Assign a file to a branch via inline picker.
function M.assign_to_branch(buf)
  local line = buf:get_cursor_line()
  if not line or (line.type ~= 'file' and line.type ~= 'committed_file') or not line.data then return end

  local file_path = line.data.path
  if not file_path then return end

  cli.branch_list(function(err, data)
    if err then
      vim.notify('gitbutler: ' .. err, vim.log.levels.ERROR)
      return
    end

    local names = extract_branch_names(data)
    if #names == 0 then
      vim.notify('gitbutler: no branches available', vim.log.levels.WARN)
      return
    end

    float.picker({
      title = 'Assign to branch',
      items = names,
      on_select = function(branch_name)
        cli.stage(file_path, branch_name, function(stage_err, _)
          notify_result('stage ' .. file_path .. ' → ' .. branch_name, stage_err, nil)
        end)
      end,
    })
  end)
end

---Absorb all uncommitted changes into logical commits.
function M.absorb(_buf)
  cli.absorb(function(err, result)
    notify_result('absorb', err, result)
  end)
end

---Commit changes to the branch under cursor.
function M.commit(buf)
  local branch = buf:get_cursor_branch()
  local branch_name = branch and branch.name or nil

  float.input({
    title = 'Commit' .. (branch_name and (' to ' .. branch_name) or ''),
    on_submit = function(message)
      cli.commit(branch_name, message, function(err, result)
        notify_result('commit', err, result)
      end)
    end,
  })
end

---Amend: absorb uncommitted changes into HEAD commit of current branch.
function M.amend(buf)
  local branch = buf:get_cursor_branch()
  local branch_name = branch and branch.name or nil
  local args = { 'amend', '--json' }
  if branch_name then
    table.insert(args, 2, branch_name)
  end

  cli.run(args, function(err, result)
    notify_result('amend', err, result)
  end)
end

---Squash: combine commit under cursor into its parent.
function M.squash(buf)
  local line = buf:get_cursor_line()
  if not line or line.type ~= 'commit' or not line.data then return end

  local sha = line.data.sha
  if not sha then return end

  cli.squash(sha, function(err, result)
    notify_result('squash', err, result)
  end)
end

---Move a commit to a different branch.
function M.move(buf)
  local line = buf:get_cursor_line()
  if not line or line.type ~= 'commit' or not line.data then return end

  local sha = line.data.sha
  if not sha then return end

  cli.branch_list(function(err, data)
    if err then
      vim.notify('gitbutler: ' .. err, vim.log.levels.ERROR)
      return
    end

    local names = extract_branch_names(data)

    float.picker({
      title = 'Move commit to',
      items = names,
      on_select = function(target_branch)
        cli.move(sha, target_branch, function(move_err, result)
          notify_result('move → ' .. target_branch, move_err, result)
        end)
      end,
    })
  end)
end

---Describe/reword a commit or branch.
function M.describe(buf)
  local line = buf:get_cursor_line()
  if not line or not line.data then return end

  if line.type == 'commit' then
    local sha = line.data.sha
    if not sha then return end
    local current_msg = line.data.commit and line.data.commit.message or ''

    float.input({
      title = 'Reword commit',
      content = current_msg ~= '' and vim.split(current_msg, '\n') or nil,
      on_submit = function(message)
        cli.reword(sha, message, function(err, result)
          notify_result('reword', err, result)
        end)
      end,
    })
  elseif line.type == 'branch' then
    local name = line.data.name
    if not name then return end

    float.input({
      title = 'Rename branch',
      content = { name },
      on_submit = function(new_name)
        cli.run({ 'reword', name, '-m', new_name, '--json' }, function(err, result)
          notify_result('rename → ' .. new_name, err, result)
        end)
      end,
    })
  end
end

---Undo last operation.
function M.undo(_buf)
  cli.undo(function(err, result)
    notify_result('undo', err, result)
  end)
end

---Push the branch under cursor.
function M.push(buf)
  local branch = buf:get_cursor_branch()
  local name = branch and branch.name or nil
  cli.push(name, function(err, result)
    notify_result('push', err, result)
  end)
end

---Push all branches.
function M.push_all(_buf)
  cli.push(nil, function(err, result)
    notify_result('push all', err, result)
  end)
end

---Close the status buffer.
function M.close(_buf)
  local status = require('gitbutler.ui.status')
  status.close()
end

---Create a new branch.
function M.branch_new(_buf)
  float.input({
    title = 'New branch name',
    height = 1,
    on_submit = function(name)
      cli.branch_new(name, function(err, result)
        notify_result('branch new ' .. name, err, result)
      end)
    end,
  })
end

---Discard changes for file under cursor.
function M.discard(buf)
  local line = buf:get_cursor_line()
  if not line or line.type ~= 'file' or not line.data then return end

  local path = line.data.path
  if not path then return end

  vim.ui.select({ 'Yes', 'No' }, { prompt = 'Discard changes to ' .. path .. '?' }, function(choice)
    if choice ~= 'Yes' then return end
    vim.system({ 'git', 'checkout', '--', path }, { text = true }, function(result)
      vim.schedule(function()
        if result.code ~= 0 then
          vim.notify('gitbutler discard: ' .. (result.stderr or 'failed'), vim.log.levels.ERROR)
        else
          vim.notify('gitbutler: discarded ' .. path, vim.log.levels.INFO)
          refresh()
        end
      end)
    end)
  end)
end

---Toggle fold on branch headers, show diff on file lines.
function M.toggle_fold(buf)
  local line = buf:get_cursor_line()
  if not line then return end

  -- File lines: show inline diff in a split below
  if line.type == 'file' or line.type == 'committed_file' then
    local cli_id = line.data and line.data.cli_id
    if not cli_id then return end

    local err, result = cli.run_sync({ 'diff', cli_id })
    if err then
      vim.notify('gitbutler diff: ' .. err, vim.log.levels.ERROR)
      return
    end

    local diff_lines = vim.split(tostring(result), '\n')
    vim.cmd('belowright split')
    local diff_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(0, diff_buf)
    vim.api.nvim_buf_set_lines(diff_buf, 0, -1, false, diff_lines)
    vim.bo[diff_buf].buftype = 'nofile'
    vim.bo[diff_buf].bufhidden = 'wipe'
    vim.bo[diff_buf].filetype = 'gitbutler-diff'

    local ns = vim.api.nvim_create_namespace('gitbutler-diff')
    for i, l in ipairs(diff_lines) do
      if l:match('│%+') then
        vim.api.nvim_buf_add_highlight(diff_buf, ns, 'DiffAdd', i - 1, 0, -1)
      elseif l:match('│%-') then
        vim.api.nvim_buf_add_highlight(diff_buf, ns, 'DiffDelete', i - 1, 0, -1)
      elseif l:match('^[─╮╯╭]') or l:match('^%s*[─╮╯╭]') then
        vim.api.nvim_buf_add_highlight(diff_buf, ns, 'Comment', i - 1, 0, -1)
      end
    end

    vim.keymap.set('n', 'q', '<cmd>close<CR>', { buffer = diff_buf })
    return
  end

  -- Branch/section headers: toggle fold
  local toggled = buf:toggle_fold()
  if toggled then
    refresh()
  end
end

---Show help popup.
function M.help(_buf)
  local help_lines = {
    'GitButler Status — Keybindings',
    '',
    '<CR>     Open file',
    's        Assign file to branch',
    'a        Absorb changes',
    'c        Commit to branch',
    'A        Amend (absorb into HEAD)',
    'S        Squash commit into parent',
    'm        Move commit to branch',
    'd        Describe/reword',
    'u        Undo last operation',
    'p        Push branch',
    'P        Push all branches',
    'B        Branch management',
    'b        New branch',
    'l        Commit log for branch',
    'O        Operations log',
    'x        Discard file changes',
    '<Tab>    Diff / toggle fold',
    'r        Refresh',
    'q        Close',
    '?        This help',
  }

  local help_buf, help_win = float.open({
    title = 'Help',
    width = 45,
    height = #help_lines,
  })

  vim.api.nvim_buf_set_lines(help_buf, 0, -1, false, help_lines)
  vim.bo[help_buf].modifiable = false

  local function close_help()
    if vim.api.nvim_win_is_valid(help_win) then
      vim.api.nvim_win_close(help_win, true)
    end
    if vim.api.nvim_buf_is_valid(help_buf) then
      vim.api.nvim_buf_delete(help_buf, { force = true })
    end
  end

  vim.keymap.set('n', 'q', close_help, { buffer = help_buf })
  vim.keymap.set('n', '<Esc>', close_help, { buffer = help_buf })
end

---Open branch management popup.
function M.branches(_buf)
  require('gitbutler.ui.branch').open()
end

---Open commit log for the branch under cursor.
function M.log(buf)
  local branch = buf:get_cursor_branch()
  local name = branch and branch.name or nil

  if not name then
    -- No branch context — show picker
    local cli_mod = require('gitbutler.cli')
    cli_mod.branch_list(function(err, data)
      if err then
        vim.notify('gitbutler: ' .. err, vim.log.levels.ERROR)
        return
      end
      local names = {}
      for _, stack in ipairs(data.appliedStacks or {}) do
        for _, head in ipairs(stack.heads or {}) do
          if head.name then table.insert(names, head.name) end
        end
      end
      if #names == 1 then
        require('gitbutler.ui.log').open(names[1])
      elseif #names > 1 then
        float.picker({
          title = 'Log for branch',
          items = names,
          on_select = function(selected) require('gitbutler.ui.log').open(selected) end,
        })
      end
    end)
    return
  end

  require('gitbutler.ui.log').open(name)
end

---Open operations log.
function M.oplog(_buf)
  require('gitbutler.ui.oplog').open()
end

return M

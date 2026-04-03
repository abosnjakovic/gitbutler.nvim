local cli = require('gitbutler.cli')
local float = require('gitbutler.ui.float')

local M = {}

local function refresh()
  local status = require('gitbutler.ui.status')
  status.refresh()
end

local function notify_start(action)
  vim.notify('gitbutler: ' .. action .. '...', vim.log.levels.INFO)
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

---Open the file(s) under cursor or selected, or show commit details for recent commits.
function M.open_file(buf)
  -- Multi-select: open each selected file without closing status buffer
  local selected = buf:get_selected_lines({ 'file', 'committed_file' })
  if #selected > 0 then
    buf:clear_selection()
    for _, line in ipairs(selected) do
      if line.data and line.data.path then
        vim.cmd('edit ' .. vim.fn.fnameescape(line.data.path))
      end
    end
    return
  end

  -- Single file / recent commit: existing behaviour
  local line = buf:get_cursor_line()
  if not line or not line.data then return end

  if line.type == 'recent_commit' then
    local sha = line.data.sha
    if not sha then return end

    local result = vim.system(
      { 'git', 'show', '--patch', '--stat', '--format=%H%n%an <%ae>%n%aD%n%n%B', sha },
      { text = true }
    ):wait()

    if result.code ~= 0 or not result.stdout then
      vim.notify('gitbutler: failed to show commit', vim.log.levels.ERROR)
      return
    end

    local show_lines = vim.split(result.stdout, '\n')
    vim.cmd('belowright split')
    local diff_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(0, diff_buf)
    vim.api.nvim_buf_set_lines(diff_buf, 0, -1, false, show_lines)
    vim.bo[diff_buf].buftype = 'nofile'
    vim.bo[diff_buf].bufhidden = 'wipe'
    vim.bo[diff_buf].filetype = 'diff'
    vim.keymap.set('n', 'q', '<cmd>close<CR>', { buffer = diff_buf })
    return
  end

  if not line.data.path then return end
  local path = line.data.path

  buf:close()
  local status = require('gitbutler.ui.status')
  status.instance = nil
  vim.cmd('edit ' .. vim.fn.fnameescape(path))
end

---Assign file(s) to a branch via inline picker.
function M.assign_to_branch(buf)
  local selected = buf:get_selected_lines({ 'file', 'committed_file' })
  local targets
  if #selected > 0 then
    targets = selected
  else
    local line = buf:get_cursor_line()
    if not line or (line.type ~= 'file' and line.type ~= 'committed_file') or not line.data then return end
    targets = { line }
  end

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
        notify_start('staging')
        local i = 0
        local function stage_next()
          i = i + 1
          if i > #targets then
            buf:clear_selection()
            vim.notify('gitbutler: staged ' .. #targets .. ' file(s) → ' .. branch_name, vim.log.levels.INFO)
            refresh()
            return
          end
          local id = targets[i].data.cli_id or targets[i].data.path
          cli.stage(id, branch_name, function(stage_err, _)
            if stage_err then
              buf:clear_selection()
              vim.notify('gitbutler stage: ' .. stage_err, vim.log.levels.ERROR)
              refresh()
              return
            end
            stage_next()
          end)
        end
        stage_next()
      end,
    })
  end)
end

---Absorb all uncommitted changes into logical commits.
function M.absorb(_buf)
  notify_start('absorb')
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
      notify_start('commit')
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

  notify_start('amend')
  cli.run(args, function(err, result)
    notify_result('amend', err, result)
  end)
end

---Squash: combine selected commits or commit under cursor into parent.
function M.squash(buf)
  local selected = buf:get_selected_lines({ 'commit' })
  if #selected > 0 then
    local shas = {}
    for _, line in ipairs(selected) do
      table.insert(shas, line.data.sha)
    end
    notify_start('squash')
    cli.squash(shas, function(err, result)
      buf:clear_selection()
      notify_result('squash ' .. #shas .. ' commits', err, result)
    end)
    return
  end

  -- Single commit fallback
  local line = buf:get_cursor_line()
  if not line or line.type ~= 'commit' or not line.data then return end
  local sha = line.data.sha
  if not sha then return end
  notify_start('squash')
  cli.squash(sha, function(err, result)
    notify_result('squash', err, result)
  end)
end

---Move commit(s) to a different branch.
function M.move(buf)
  local selected = buf:get_selected_lines({ 'commit' })
  local targets
  if #selected > 0 then
    targets = selected
  else
    local line = buf:get_cursor_line()
    if not line or line.type ~= 'commit' or not line.data then return end
    targets = { line }
  end

  cli.branch_list(function(err, data)
    if err then
      vim.notify('gitbutler: ' .. err, vim.log.levels.ERROR)
      return
    end

    local names = extract_branch_names(data)

    float.picker({
      title = 'Move commit(s) to',
      items = names,
      on_select = function(target_branch)
        notify_start('move')
        local i = 0
        local function move_next()
          i = i + 1
          if i > #targets then
            buf:clear_selection()
            vim.notify('gitbutler: moved ' .. #targets .. ' commit(s) → ' .. target_branch, vim.log.levels.INFO)
            refresh()
            return
          end
          local sha = targets[i].data.sha
          cli.move(sha, target_branch, function(move_err, _)
            if move_err then
              buf:clear_selection()
              vim.notify('gitbutler move: ' .. move_err, vim.log.levels.ERROR)
              refresh()
              return
            end
            move_next()
          end)
        end
        move_next()
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
        notify_start('reword')
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
      single_line = true,
      content = { name },
      on_submit = function(new_name)
        notify_start('rename')
        cli.run({ 'reword', name, '-m', new_name, '--json' }, function(err, result)
          notify_result('rename → ' .. new_name, err, result)
        end)
      end,
    })
  end
end

---Undo last operation.
function M.undo(_buf)
  notify_start('undo')
  cli.undo(function(err, result)
    notify_result('undo', err, result)
  end)
end

---Push the branch under cursor.
function M.push(buf)
  local branch = buf:get_cursor_branch()
  local name = branch and branch.name or nil
  notify_start('push')
  cli.push(name, function(err, result)
    notify_result('push', err, result)
  end)
end

---Push all branches.
function M.push_all(_buf)
  notify_start('push all')
  cli.push(nil, function(err, result)
    notify_result('push all', err, result)
  end)
end

---Pull (sync) from upstream.
function M.pull(_buf)
  notify_start('pull')
  cli.pull(function(err, result)
    notify_result('pull', err, result)
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
    single_line = true,
    on_submit = function(name)
      notify_start('branch new')
      cli.branch_new(name, function(err, result)
        notify_result('branch new ' .. name, err, result)
      end)
    end,
  })
end

---Discard changes for file(s) under cursor or selected.
function M.discard(buf)
  local selected = buf:get_selected_lines({ 'file' })
  local targets
  if #selected > 0 then
    targets = selected
  else
    local line = buf:get_cursor_line()
    if not line or line.type ~= 'file' or not line.data then return end
    targets = { line }
  end

  local paths = {}
  for _, t in ipairs(targets) do
    table.insert(paths, t.data.path or t.data.cli_id)
  end
  local prompt = 'Discard changes to ' .. table.concat(paths, ', ') .. '?'

  vim.ui.select({ 'Yes', 'No' }, { prompt = prompt }, function(choice)
    if choice ~= 'Yes' then return end
    notify_start('discard')
    local i = 0
    local function discard_next()
      i = i + 1
      if i > #targets then
        buf:clear_selection()
        vim.notify('gitbutler: discarded ' .. #targets .. ' file(s)', vim.log.levels.INFO)
        refresh()
        return
      end
      cli.discard(targets[i].data.cli_id, function(err, _)
        if err then
          buf:clear_selection()
          vim.notify('gitbutler discard: ' .. err, vim.log.levels.ERROR)
          refresh()
          return
        end
        discard_next()
      end)
    end
    discard_next()
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

---Toggle selection on the line under cursor.
function M.toggle_select(buf)
  local toggled = buf:toggle_select()
  -- Re-render to show updated markers without a full refresh (preserves selection)
  if buf.lines and #buf.lines > 0 then
    buf:render(buf.lines)
  end
  if toggled and buf.win and vim.api.nvim_win_is_valid(buf.win) then
    local cursor = vim.api.nvim_win_get_cursor(buf.win)
    local max_row = vim.api.nvim_buf_line_count(buf.buf)
    if cursor[1] < max_row then
      vim.api.nvim_win_set_cursor(buf.win, { cursor[1] + 1, cursor[2] })
    end
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
    'F        Pull / sync from upstream',
    'B        Branch management',
    'b        New branch',
    'l        Commit log for branch',
    'O        Operations log',
    'x        Discard file changes',
    '<Tab>    Diff / toggle fold',
    'r        Refresh',
    'q        Close',
    '<Space>  Select / deselect',
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

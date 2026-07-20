local cli = require('gitbutler.cli')
local float = require('gitbutler.ui.float')
local spinner = require('gitbutler.ui.spinner')

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
  if not line or not line.data then
    return
  end

  if line.type == 'recent_commit' then
    local sha = line.data.sha
    if not sha then
      return
    end

    local result = vim
      .system({ 'git', 'show', '--patch', '--stat', '--format=%H%n%an <%ae>%n%aD%n%n%B', sha }, { text = true })
      :wait()

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
    vim.keymap.set('n', '<Tab>', '<cmd>close<CR>', { buffer = diff_buf })
    -- Commits are immutable; absorb `r`/`<C-r>` so they don't fall through to vim's replace.
    vim.keymap.set('n', 'r', '<cmd>close<CR>', { buffer = diff_buf })
    vim.keymap.set('n', '<C-r>', '<cmd>close<CR>', { buffer = diff_buf })
    return
  end

  if not line.data.path then
    return
  end
  local path = line.data.path

  buf:close()
  local status = require('gitbutler.ui.status')
  status.instance = nil
  vim.cmd('edit ' .. vim.fn.fnameescape(path))
end

---Enter stack mode: apply/unapply/move stacks.
function M.stack_start(buf)
  require('gitbutler.ui.modes').enter(buf, 'stack')
end

---Pure scan: row index of the branch row named `name`, or nil.
---@param lines? GitButlerLine[]
---@param name string
---@return integer?
function M._branch_row(lines, name)
  for row, line in ipairs(lines or {}) do
    if line.type == 'branch' and line.data and line.data.name == name then
      return row
    end
  end
  return nil
end

---Fuzzy-pick an applied branch and move the cursor to its row.
function M.goto_branch(buf)
  local function pick(names)
    if #names == 0 then
      vim.notify('gitbutler: no applied branches', vim.log.levels.WARN)
      return
    end
    float.fuzzy_picker({
      title = 'Go to branch',
      items = names,
      on_select = function(name)
        local row = M._branch_row(buf.lines, name)
        if row and buf.win and vim.api.nvim_win_is_valid(buf.win) then
          vim.api.nvim_win_set_cursor(buf.win, { row, 0 })
        end
      end,
    })
  end

  local data = require('gitbutler.ui.status').data
  if data then
    local names = {}
    for _, stack in ipairs(data.stacks or {}) do
      for _, branch in ipairs(stack.branches or {}) do
        if branch.name then
          table.insert(names, branch.name)
        end
      end
    end
    pick(names)
    return
  end

  -- No cached status (shouldn't happen in a live view) — fall back to the CLI.
  cli.branch_list(function(err, bdata)
    if err then
      vim.notify('gitbutler: ' .. err, vim.log.levels.ERROR)
      return
    end
    local names = {}
    for _, stack in ipairs(bdata.appliedStacks or {}) do
      for _, head in ipairs(stack.heads or {}) do
        if head.name then
          table.insert(names, head.name)
        end
      end
    end
    pick(names)
  end)
end

---Absorb all uncommitted changes into logical commits.
function M.absorb(_buf)
  notify_start('absorb')
  cli.absorb(function(err, result)
    notify_result('absorb', err, result)
  end)
end

---Enter commit mode: pick a branch or commit row as the insert anchor.
function M.commit_mode_start(buf)
  require('gitbutler.ui.modes').enter(buf, 'commit', nil, { above = false })
end

---Insert an empty commit after the commit or branch under cursor (no mode).
function M.insert_empty_commit(buf)
  local line = buf:get_cursor_line()
  if not line or (line.type ~= 'commit' and line.type ~= 'branch') or not (line.data and line.data.cli_id) then
    vim.notify('gitbutler: place the cursor on a commit or branch', vim.log.levels.WARN)
    return
  end
  notify_start('empty commit')
  cli.commit_empty({ after = line.data.cli_id }, function(err, result)
    notify_result('empty commit', err, result)
  end)
end

---Esc in normal mode: exit an active mode, else clear marks.
function M.back(buf)
  require('gitbutler.ui.modes').back(buf)
end

---Toggle the committed-file list for the commit under cursor.
function M.toggle_file_list(buf)
  local line = buf:get_cursor_line()
  local sha = line and line.type == 'commit' and line.data and line.data.sha or nil
  if not sha then
    vim.notify('gitbutler: place the cursor on a commit', vim.log.levels.WARN)
    return
  end
  buf.file_lists[sha] = not buf.file_lists[sha] or nil
  require('gitbutler.ui.status').rerender()
end

---Toggle committed-file lists for every commit.
function M.toggle_all_file_lists(buf)
  buf.show_all_files = not buf.show_all_files
  require('gitbutler.ui.status').rerender()
end

---Reword the commit under cursor in an editor split (full message, gitcommit ft).
function M.reword_editor(buf)
  local line = buf:get_cursor_line()
  if not line or line.type ~= 'commit' or not (line.data and line.data.sha) then
    vim.notify('gitbutler: place the cursor on a commit', vim.log.levels.WARN)
    return
  end
  local sha = line.data.sha
  local message = line.data.commit and line.data.commit.message or ''

  vim.cmd('belowright split')
  local ewin = vim.api.nvim_get_current_win()
  local ebuf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(ewin, ebuf)
  vim.api.nvim_buf_set_lines(ebuf, 0, -1, false, vim.split(message, '\n'))
  vim.bo[ebuf].buftype = 'nofile'
  vim.bo[ebuf].bufhidden = 'wipe'
  vim.bo[ebuf].filetype = 'gitcommit'

  local function close_split()
    if vim.api.nvim_win_is_valid(ewin) then
      vim.api.nvim_win_close(ewin, true)
    end
  end
  local function submit()
    local text = vim.trim(table.concat(vim.api.nvim_buf_get_lines(ebuf, 0, -1, false), '\n'))
    close_split()
    if text == '' then
      return
    end
    notify_start('reword')
    cli.reword(sha, text, function(err, result)
      notify_result('reword', err, result)
    end)
  end

  vim.keymap.set({ 'n', 'i' }, '<C-c><C-c>', submit, { buffer = ebuf })
  vim.keymap.set('n', 'q', close_split, { buffer = ebuf })
  vim.keymap.set('n', '<Esc>', close_split, { buffer = ebuf })
end

---Describe/reword a commit or branch.
function M.describe(buf)
  local line = buf:get_cursor_line()
  if not line or not line.data then
    return
  end

  if line.type == 'commit' then
    local sha = line.data.sha
    if not sha then
      return
    end
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
    if not name then
      return
    end

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

---Undo last operation (confirms first).
function M.undo(_buf)
  vim.ui.select({ 'Yes', 'No' }, { prompt = 'Undo last operation?' }, function(choice)
    if choice ~= 'Yes' then
      return
    end
    notify_start('undo')
    cli.undo(function(err, result)
      notify_result('undo', err, result)
    end)
  end)
end

---Redo last undone operation (confirms first).
function M.redo(_buf)
  vim.ui.select({ 'Yes', 'No' }, { prompt = 'Redo?' }, function(choice)
    if choice ~= 'Yes' then
      return
    end
    notify_start('redo')
    cli.redo(function(err, result)
      notify_result('redo', err, result)
    end)
  end)
end

---Exact cli_id match wins; else unique prefix match; else nil.
function M._jump_target(lines, query)
  if query == '' then
    return nil
  end
  local prefix_hit
  for i, l in ipairs(lines) do
    local id = l.data and l.data.cli_id
    if id == query then
      return i
    end
    if id and vim.startswith(id, query) then
      if prefix_hit then
        return nil
      end -- ambiguous
      prefix_hit = i
    end
  end
  return prefix_hit
end

-- ponytail: input()-based jump v1; incremental per-key highlighting arrives
-- when phase 3 brings a real input loop.
---Prompt for a cli_id (or unique prefix) and move the cursor to its row.
function M.jump_to_id(buf)
  local ok, query = pcall(vim.fn.input, 'jump to id: ')
  if not ok or query == '' then
    return
  end
  local row = M._jump_target(buf.lines, query)
  if not row then
    vim.notify('gitbutler: no unique match', vim.log.levels.WARN)
    return
  end
  if buf.win and vim.api.nvim_win_is_valid(buf.win) then
    vim.api.nvim_win_set_cursor(buf.win, { row, 0 })
  end
end

---Run an arbitrary `but` subcommand and surface its output.
function M.but_command(_buf)
  local ok, args = pcall(vim.fn.input, 'but ')
  if not ok or args == '' then
    return
  end
  -- ponytail: naive split, no shell quoting — use ! for that
  local parts = vim.split(args, '%s+', { trimempty = true })
  cli.run(parts, { raw = true }, function(err, out)
    if err then
      vim.notify('gitbutler but: ' .. err, vim.log.levels.ERROR)
      -- A failed command may still have mutated the workspace partway.
      refresh()
      return
    end
    vim.notify(out ~= '' and out or ('but ' .. args .. ': done'), vim.log.levels.INFO)
    refresh()
  end)
end

---Run an arbitrary shell command and surface its output.
function M.shell_command(_buf)
  local ok, cmd = pcall(vim.fn.input, '$ ')
  if not ok or cmd == '' then
    return
  end
  vim.system(
    { 'sh', '-c', cmd },
    { text = true },
    vim.schedule_wrap(function(result)
      if result.code ~= 0 then
        local msg = (result.stderr and result.stderr ~= '') and result.stderr or ('exited ' .. result.code)
        vim.notify('gitbutler $: ' .. vim.trim(msg), vim.log.levels.ERROR)
        -- A failed command may still have mutated the workspace partway.
        refresh()
        return
      end
      local out = result.stdout or ''
      vim.notify(out ~= '' and out or ('$ ' .. cmd .. ': done'), vim.log.levels.INFO)
      refresh()
    end)
  )
end

---Clipboard text for a status row: commit sha / file path / branch name /
---'zz' for the uncommitted header; nil for rows with nothing copyable.
function M._copy_text(line)
  if not line or not line.data then
    return nil
  end
  if line.type == 'commit' then
    return line.data.sha
  elseif line.type == 'file' or line.type == 'committed_file' then
    return line.data.path
  elseif line.type == 'branch' then
    return line.data.name
  elseif line.type == 'uncommitted_header' then
    return 'zz'
  end
  return nil
end

---Copy the row under cursor's id/path/name to the `+` and unnamed registers.
function M.copy_selection(buf)
  local text = M._copy_text(buf:get_cursor_line())
  if not text then
    vim.notify('gitbutler: nothing to copy on this row', vim.log.levels.WARN)
    return
  end
  vim.fn.setreg('+', text)
  vim.fn.setreg('"', text)
  local display = #text > 40 and (text:sub(1, 40) .. '…') or text
  vim.notify('gitbutler: copied ' .. display, vim.log.levels.INFO)
end

---Push the branch under cursor (syncs with upstream first).
function M.push(buf)
  local branch = buf:get_cursor_branch()
  local name = branch and branch.name or nil
  notify_start('sync (pull + push)')
  cli.pull(function(err, result)
    if err then
      notify_result('pull', err, result)
      return
    end
    cli.push(name, function(err2, result2)
      notify_result('push', err2, result2)
    end)
  end)
end

---Build the ephemeral branch name used by direct_to_main.
---@param ts integer Unix timestamp (typically os.time())
---@return string
function M.ephemeral_branch_name(ts)
  return 'direct-to-main-' .. tostring(ts)
end

---Format a step-tagged error message used by surface_error.
---@param step string Step label (e.g. 'commit', 'push')
---@param body string Error body
---@return string
function M.format_step_error(step, body)
  return '[gitbutler ' .. step .. '] ' .. body
end

---Notify ERROR + write to :messages history so the user can recall it later.
local function surface_error(step, body)
  local msg = M.format_step_error(step, body)
  vim.notify(msg, vim.log.levels.ERROR)
  vim.api.nvim_echo({ { msg, 'ErrorMsg' } }, true, {})
end

---Pull the new commit's SHA out of a `but commit --json` result. Current CLIs
---nest it as `{ result = { commit_id } }`; older ones returned a flat
---`{ commit_id }`. Tolerate both so the feature survives either shape.
---@param result any Decoded JSON from cli.commit
---@return string? sha
function M.commit_id_of(result)
  if type(result) ~= 'table' then
    return nil
  end
  local nested = type(result.result) == 'table' and result.result.commit_id or nil
  local sha = nested or result.commit_id
  if type(sha) == 'string' and sha ~= '' then
    return sha
  end
  return nil
end
local commit_id_of = M.commit_id_of

---Commit selected (or unassigned) files onto an ephemeral virtual branch,
---then land that branch directly onto the target with `but land`, which
---fast-forwards (or merges) the target, pushes to the remote, and reconciles
---the workspace in a single call.
function M.direct_to_main(buf)
  local file_ids = {}
  local selected = buf:get_selected_lines({ 'file' })
  if #selected > 0 then
    for _, line in ipairs(selected) do
      if line.data and line.data.cli_id then
        table.insert(file_ids, line.data.cli_id)
      end
    end
  else
    for _, line in ipairs(buf.lines or {}) do
      if line.type == 'file' and line.data and line.data.unassigned and line.data.cli_id then
        table.insert(file_ids, line.data.cli_id)
      end
    end
  end

  if #file_ids == 0 then
    vim.notify('gitbutler: no unassigned changes', vim.log.levels.WARN)
    return
  end

  local title = 'Commit to main (' .. #file_ids .. ' file' .. (#file_ids > 1 and 's' or '') .. ')'
  float.input({
    title = title,
    on_submit = function(message)
      if not message or vim.trim(message) == '' then
        return
      end

      local ts = os.time()
      local ephemeral_name = M.ephemeral_branch_name(ts)

      local sp = spinner.start('committing ' .. #file_ids .. ' file(s)')
      cli.commit(ephemeral_name, message, function(commit_err, commit_result)
        if commit_err then
          sp:stop()
          buf:clear_selection()
          surface_error('commit', commit_err)
          refresh()
          return
        end

        local ephemeral_sha = commit_id_of(commit_result)
        if not ephemeral_sha then
          sp:stop()
          buf:clear_selection()
          surface_error('commit', 'no commit_id in response from but commit')
          refresh()
          return
        end

        -- Land the ephemeral branch straight onto the target. `but land` does the
        -- fast-forward-or-merge, the remote push, and the workspace reconcile in one
        -- call; on rejection (e.g. a protected branch) it exits non-zero with a message.
        sp:update('landing onto target')
        cli.land(ephemeral_name, function(land_err)
          sp:stop()
          buf:clear_selection()
          if land_err then
            surface_error('land', land_err)
            refresh()
            return
          end
          vim.notify('gitbutler: direct-to-main done (landed ' .. ephemeral_sha:sub(1, 7) .. ')', vim.log.levels.INFO)
          refresh()
        end)
      end, file_ids, true)
    end,
  })
end

---Headless variant of direct_to_main used by tests/manual/direct_to_main.sh.
---Looks up cliIds via `but status --json`, runs the same pipeline synchronously.
---Returns nil on success, a string error on the first failed step.
---@param file_path string Path of the unassigned file to commit (relative to cwd)
---@param message string Commit message
---@return string? err
function M.direct_to_main_test_harness(file_path, message)
  local status_res = vim.system({ 'but', 'status', '--format=json' }, { text = true }):wait()
  if status_res.code ~= 0 then
    return 'but status: ' .. vim.trim(status_res.stderr or '')
  end
  local ok, decoded = pcall(vim.json.decode, status_res.stdout or '')
  if not ok or type(decoded) ~= 'table' then
    return 'but status: invalid JSON'
  end

  local cli_id
  for _, c in ipairs(decoded.uncommittedChanges or {}) do
    if c.filePath == file_path then
      cli_id = c.cliId
      break
    end
  end
  if not cli_id then
    return 'file not in uncommittedChanges: ' .. file_path
  end

  local ts = os.time()
  local ephemeral_name = M.ephemeral_branch_name(ts)

  -- but commit -c <ephemeral> -m <msg> -p <cli_id> --json
  local commit_res = vim
    .system({ 'but', 'commit', ephemeral_name, '-c', '-m', message, '-p', cli_id, '--format=json' }, { text = true })
    :wait()
  if commit_res.code ~= 0 then
    return 'commit: ' .. vim.trim(commit_res.stderr or '')
  end
  local commit_ok, commit_decoded = pcall(vim.json.decode, commit_res.stdout or '')
  local ephemeral_sha = commit_ok and commit_id_of(commit_decoded) or nil
  if not ephemeral_sha then
    return 'commit: no commit_id in response'
  end

  -- but land <ephemeral> --yes: fast-forward-or-merge the target, push, reconcile.
  local land = vim.system({ 'but', 'land', ephemeral_name, '--yes', '--format=json' }, { text = true }):wait()
  if land.code ~= 0 then
    return 'land: ' .. vim.trim(land.stderr or '')
  end

  return nil
end

---Push all branches (syncs with upstream first).
function M.push_all(_buf)
  notify_start('sync all (pull + push)')
  cli.pull(function(err, result)
    if err then
      notify_result('pull', err, result)
      return
    end
    cli.push(nil, function(err2, result2)
      notify_result('push all', err2, result2)
    end)
  end)
end

---Create a forge review (PR/MR) for the branch under cursor. Pre-fills the
---title/body float with the most recent commit's subject and body.
function M.pr_create(buf)
  local branch = buf:get_cursor_branch()
  local name = branch and branch.name or nil
  if not name then
    vim.notify('gitbutler: no branch under cursor', vim.log.levels.WARN)
    return
  end

  -- Pre-fill from latest commit.
  local commits = branch and branch.commits or {}
  local latest = commits[#commits]
  local content
  if latest and latest.message and latest.message ~= '' then
    content = vim.split(latest.message, '\n')
  end

  float.input({
    title = 'New PR for ' .. name,
    content = content,
    on_submit = function(message)
      if not message or vim.trim(message) == '' then
        return
      end
      notify_start('pr new')
      local sp = spinner.start('creating PR for ' .. name)
      cli.pr_new(name, message, function(err, result)
        sp:stop()
        if err then
          vim.notify('gitbutler pr: ' .. err, vim.log.levels.ERROR)
          refresh()
          return
        end
        local url = type(result) == 'table' and (result.url or result.htmlUrl) or nil
        vim.notify('gitbutler pr: created' .. (url and (' — ' .. url) or ''), vim.log.levels.INFO)
        refresh()
      end)
    end,
  })
end

---Toggle draft/ready state of the PR for the branch under cursor.
---State is read from `branch.reviewState` when present; otherwise the action
---calls `set-draft` first and the user can press D again to flip if needed.
function M.pr_toggle_draft(buf)
  local branch = buf:get_cursor_branch()
  local name = branch and branch.name or nil
  if not name then
    vim.notify('gitbutler: no branch under cursor', vim.log.levels.WARN)
    return
  end
  if not branch.reviewId then
    vim.notify('gitbutler: no PR for this branch', vim.log.levels.WARN)
    return
  end

  local is_draft = branch.reviewState == 'draft'
  if is_draft then
    notify_start('pr set-ready')
    cli.pr_set_ready(name, function(err, _)
      notify_result('pr set-ready', err, nil)
    end)
  else
    notify_start('pr set-draft')
    cli.pr_set_draft(name, function(err, _)
      notify_result('pr set-draft', err, nil)
    end)
  end
end

---Toggle auto-merge for the PR on the branch under cursor or named explicitly.
---@param buf_or_name table|string Either the status buffer or a branch name string
function M.pr_auto_merge(buf_or_name)
  local name
  if type(buf_or_name) == 'string' then
    name = buf_or_name
  elseif type(buf_or_name) == 'table' then
    local branch = buf_or_name:get_cursor_branch()
    name = branch and branch.name or nil
  end
  if not name then
    vim.notify('gitbutler: no branch specified', vim.log.levels.WARN)
    return
  end

  notify_start('pr auto-merge')
  cli.pr_auto_merge(name, function(err, _)
    notify_result('pr auto-merge', err, nil)
  end)
end

---Open the CI view for the branch under cursor. The adapter decides whether
---there are runs to show; `branch.ci` from `but status` is often null even
---when `gh` has runs, so we don't gate on it here.
---
---When the cursor branch is part of a stack, query the stack HEAD branch —
---that's what the forge has CI for (the PR's head ref). Base branches in a
---stack typically have no runs of their own.
function M.ci_open(buf)
  local data = buf:get_cursor_branch()
  if not data or not data.name then
    vim.notify('gitbutler: no branch under cursor', vim.log.levels.WARN)
    return
  end

  local query_name = data.name
  local stack_branches = data.stack and data.stack.branches or nil
  if stack_branches and stack_branches[1] and stack_branches[1].name then
    query_name = stack_branches[1].name
  end

  require('gitbutler.ui.ci').open(query_name)
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
    if not line or line.type ~= 'file' or not line.data then
      return
    end
    targets = { line }
  end

  local paths = {}
  for _, t in ipairs(targets) do
    table.insert(paths, t.data.path or t.data.cli_id)
  end
  local prompt = 'Discard changes to ' .. table.concat(paths, ', ') .. '?'

  vim.ui.select({ 'Yes', 'No' }, { prompt = prompt }, function(choice)
    if choice ~= 'Yes' then
      return
    end
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
  if not line then
    return
  end

  -- File lines: show inline diff in a split below
  if line.type == 'file' or line.type == 'committed_file' then
    local cli_id = line.data and line.data.cli_id
    if not cli_id then
      return
    end

    local err, result = cli.run_sync({ 'diff', cli_id })
    if err then
      vim.notify('gitbutler diff: ' .. err, vim.log.levels.ERROR)
      return
    end

    local diff_lines = vim.split(tostring(result), '\n')
    vim.cmd('belowright split')
    local diff_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(0, diff_buf)
    vim.bo[diff_buf].buftype = 'nofile'
    vim.bo[diff_buf].bufhidden = 'wipe'
    vim.bo[diff_buf].filetype = 'gitbutler-diff'

    local ns = vim.api.nvim_create_namespace('gitbutler-diff')

    local function render(lines_to_render)
      pcall(vim.api.nvim_buf_set_lines, diff_buf, 0, -1, false, lines_to_render)
      vim.api.nvim_buf_clear_namespace(diff_buf, ns, 0, -1)
      for i, l in ipairs(lines_to_render) do
        if l:match('│%+') then
          vim.api.nvim_buf_add_highlight(diff_buf, ns, 'DiffAdd', i - 1, 0, -1)
        elseif l:match('│%-') then
          vim.api.nvim_buf_add_highlight(diff_buf, ns, 'DiffDelete', i - 1, 0, -1)
        elseif l:match('^[─╮╯╭]') or l:match('^%s*[─╮╯╭]') then
          vim.api.nvim_buf_add_highlight(diff_buf, ns, 'Comment', i - 1, 0, -1)
        end
      end
    end

    render(diff_lines)

    local function refetch()
      if not vim.api.nvim_buf_is_valid(diff_buf) then
        return
      end
      local re_err, re_result = cli.run_sync({ 'diff', cli_id })
      if re_err then
        vim.notify('gitbutler diff: ' .. re_err, vim.log.levels.ERROR)
        return
      end
      render(vim.split(tostring(re_result), '\n'))
    end

    vim.keymap.set('n', 'q', '<cmd>close<CR>', { buffer = diff_buf })
    vim.keymap.set('n', '<Tab>', '<cmd>close<CR>', { buffer = diff_buf })
    vim.keymap.set('n', 'r', refetch, { buffer = diff_buf, desc = 'gitbutler: refresh file diff' })
    vim.keymap.set('n', '<C-r>', refetch, { buffer = diff_buf, desc = 'gitbutler: refresh file diff' })
    return
  end

  -- Branch/section headers: toggle fold
  local toggled = buf:toggle_fold()
  if toggled then
    if buf.view == 'status' then
      -- Graph rows are rebuilt from cached data; folds don't need a CLI refetch.
      require('gitbutler.ui.status').rerender()
    else
      refresh()
    end
  end
end

---Toggle selection on the line under cursor.
function M.toggle_select(buf)
  local toggled = buf:toggle_select()
  -- Graph rows bake the ✔︎ mark at build time, so the status view must
  -- rebuild rows from cached data rather than repaint stale lines.
  if buf.view == 'status' then
    require('gitbutler.ui.status').rerender()
  elseif buf.lines and #buf.lines > 0 then
    buf:render(buf.lines)
  end
  if toggled and buf.win and vim.api.nvim_win_is_valid(buf.win) then
    local cursor = vim.api.nvim_win_get_cursor(buf.win)
    local target = M._next_selectable(buf.lines, cursor[1], 1, 1)
    if target ~= cursor[1] then
      vim.api.nvim_win_set_cursor(buf.win, { target, cursor[2] })
    end
  end
end

---Show help popup.
function M.help(_buf)
  local help_lines = {
    'GitButler Status — Keybindings',
    '',
    'Navigation',
    '  j/k      Next / previous row',
    '  J/K      Next / previous section',
    '  <C-d>/<C-u>  Jump 10 rows',
    '  g/G      Uncommitted area / merge base',
    '  t        Go to branch (fuzzy picker)',
    '  /        Jump to CLI id',
    '  <Esc>    Back (exit mode, else clear marks)',
    '',
    'Marks',
    '  <Space>  Mark / unmark (homogeneous multi-select)',
    '',
    'Modes',
    '  r/R      Rub source onto target (assign/amend/squash/move/…)',
    '  c        Commit mode (pick where the commit lands)',
    '  m        Move mode (reorder / retarget commits)',
    '  s        Stack mode (apply / unapply / move)',
    '',
    'Operations',
    '  n        Insert empty commit',
    '  b        New branch',
    '  x        Discard (confirm)',
    '  u/U      Undo / redo (confirm)',
    '  <CR>     Describe / reword (float)',
    '  M        Reword in an editor split',
    '  f/F      Toggle file list (commit / all)',
    '  y        Copy sha / path / name',
    '  :        Run a but command',
    '  !        Run a shell command',
    '  <Tab>    Inline diff / fold',
    '  <C-r>    Refresh',
    '',
    'Extras',
    '  o        Open file',
    '  A        Absorb changes',
    '  p/P      Push branch / all',
    '  v        Create PR',
    '  V        Toggle PR draft',
    '  C        CI view',
    '  L        Land directly onto target',
    '  i        Pull / integrate upstream',
    '  T        Timeline',
    '  H        Commit log',
    '  O        Operations log',
    '  B        Branch management',
    '',
    '  q  Close    ?  This help',
  }

  local width = 66
  for _, l in ipairs(help_lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l) + 4)
  end
  local help_buf, help_win = float.open({
    title = 'Help',
    width = width,
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
          if head.name then
            table.insert(names, head.name)
          end
        end
      end
      if #names == 1 then
        require('gitbutler.ui.log').open(names[1])
      elseif #names > 1 then
        float.picker({
          title = 'Log for branch',
          items = names,
          on_select = function(selected)
            require('gitbutler.ui.log').open(selected)
          end,
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

---Open commit timeline.
function M.timeline(_buf)
  require('gitbutler.ui.timeline').open()
end

---Row types that can act as a rub source (they have a row in the verb matrix).
local RUB_SOURCE_TYPES = {
  file = true,
  committed_file = true,
  commit = true,
  branch = true,
  uncommitted_header = true,
}

---Short human label for a rub source row (path / sha7 / branch name).
local function rub_label(line)
  local d = line.data or {}
  if line.type == 'commit' then
    return (d.sha or d.cli_id or '?'):sub(1, 7)
  end
  return d.path or d.name or d.cli_id or '?'
end

---Enter rub mode with the marked lines (or the cursor line) as source.
function M.rub_start(buf)
  local sources = buf:get_selected_lines()
  if #sources == 0 then
    local line = buf:get_cursor_line()
    sources = line and { line } or {}
  end

  local kind = sources[1] and sources[1].type or nil
  if not kind or not RUB_SOURCE_TYPES[kind] then
    vim.notify('gitbutler: nothing to rub here', vim.log.levels.WARN)
    return
  end

  local ids, rows = {}, {}
  for _, src in ipairs(sources) do
    local id = src.data and src.data.cli_id
    if not id then
      vim.notify('gitbutler: row has no CLI id', vim.log.levels.WARN)
      return
    end
    table.insert(ids, id)
    for row, l in ipairs(buf.lines or {}) do
      if l == src then
        table.insert(rows, row)
        break
      end
    end
  end

  local label = rub_label(sources[1]) .. (#sources > 1 and (' +' .. (#sources - 1)) or '')
  buf:clear_selection()
  -- Repaint the cleared ● marks before the mode overlays go on. Marks only
  -- affect glyphs, so the captured row indexes stay valid.
  require('gitbutler.ui.status').rerender()
  require('gitbutler.ui.modes').enter_rub(buf, { kind = kind, ids = ids, rows = rows, label = label })
end

---Enter move mode with the marked commits (or the cursor commit/branch) as source.
function M.move_start(buf)
  local sources = buf:get_selected_lines()
  if #sources == 0 then
    local line = buf:get_cursor_line()
    sources = line and { line } or {}
  end

  local kind = sources[1] and sources[1].type or nil
  if kind ~= 'commit' and kind ~= 'branch' then
    vim.notify('gitbutler: nothing to move here', vim.log.levels.WARN)
    return
  end

  local ids, rows = {}, {}
  for _, src in ipairs(sources) do
    local id = src.data and src.data.cli_id
    if not id then
      vim.notify('gitbutler: row has no CLI id', vim.log.levels.WARN)
      return
    end
    table.insert(ids, id)
    for row, l in ipairs(buf.lines or {}) do
      if l == src then
        table.insert(rows, row)
        break
      end
    end
  end

  local label = rub_label(sources[1]) .. (#sources > 1 and (' +' .. (#sources - 1)) or '')
  buf:clear_selection()
  require('gitbutler.ui.status').rerender()
  require('gitbutler.ui.modes').enter(buf, 'move', { kind = kind, ids = ids, rows = rows, label = label }, {
    above = false,
  })
end

---Enter rub mode with every unassigned file as source (reverse rub).
function M.rub_reverse(buf)
  local ids, rows = {}, {}
  for row, line in ipairs(buf.lines or {}) do
    if line.type == 'file' and line.data and line.data.unassigned and line.data.cli_id then
      table.insert(ids, line.data.cli_id)
      table.insert(rows, row)
    end
  end
  if #ids == 0 then
    vim.notify('gitbutler: no unassigned changes', vim.log.levels.WARN)
    return
  end
  local label = #ids .. ' unassigned file' .. (#ids > 1 and 's' or '')
  require('gitbutler.ui.modes').enter_rub(buf, { kind = 'file', ids = ids, rows = rows, label = label })
end

---Pure scanner: from row `from`, move `count` selectable rows in `dir` (1/-1).
---Returns the destination row (stays put when no further selectable row exists).
---@param filter? fun(line: GitButlerLine, row: integer): boolean Extra qualifier (e.g. mode target filter)
function M._next_selectable(lines, from, dir, count, filter)
  local at = from
  for _ = 1, count do
    local j = at + dir
    local found
    while j >= 1 and j <= #lines do
      if lines[j] and lines[j].selectable and (not filter or filter(lines[j], j)) then
        found = j
        break
      end
      j = j + dir
    end
    if not found then
      break
    end
    at = found
  end
  return at
end

local SECTION_TYPES = { branch = true, uncommitted_header = true }

---Pure scanner: next section header (branch / uncommitted area) in `dir`.
function M._next_section(lines, from, dir)
  local j = from + dir
  while j >= 1 and j <= #lines do
    if lines[j] and SECTION_TYPES[lines[j].type] then
      return j
    end
    j = j + dir
  end
  return from
end

local function move_cursor(buf, target)
  if buf.win and vim.api.nvim_win_is_valid(buf.win) then
    vim.api.nvim_win_set_cursor(buf.win, { target, 0 })
  end
end

---Guard: keymap handlers below assume a live window; bail out early in
---headless contexts (e.g. tests) rather than let cursor_row throw.
local function has_win(buf)
  return buf.win and vim.api.nvim_win_is_valid(buf.win)
end

local function cursor_row(buf)
  return vim.api.nvim_win_get_cursor(buf.win)[1]
end

function M.cursor_down(buf)
  if not has_win(buf) then
    return
  end
  move_cursor(buf, M._next_selectable(buf.lines, cursor_row(buf), 1, 1, buf.mode_filter))
end
function M.cursor_up(buf)
  if not has_win(buf) then
    return
  end
  move_cursor(buf, M._next_selectable(buf.lines, cursor_row(buf), -1, 1, buf.mode_filter))
end
function M.jump_down(buf)
  if not has_win(buf) then
    return
  end
  move_cursor(buf, M._next_selectable(buf.lines, cursor_row(buf), 1, 10, buf.mode_filter))
end
function M.jump_up(buf)
  if not has_win(buf) then
    return
  end
  move_cursor(buf, M._next_selectable(buf.lines, cursor_row(buf), -1, 10, buf.mode_filter))
end
function M.section_down(buf)
  if not has_win(buf) then
    return
  end
  move_cursor(buf, M._next_section(buf.lines, cursor_row(buf), 1))
end
function M.section_up(buf)
  if not has_win(buf) then
    return
  end
  move_cursor(buf, M._next_section(buf.lines, cursor_row(buf), -1))
end
function M.details_toggle(buf)
  require('gitbutler.ui.details').toggle(buf)
end
function M.details_toggle_full(buf)
  require('gitbutler.ui.details').toggle_full(buf)
end
function M.details_grow(_buf)
  require('gitbutler.ui.details').resize(5)
end
function M.details_shrink(_buf)
  require('gitbutler.ui.details').resize(-5)
end
function M.goto_top(buf)
  if buf.mode_filter then
    local target = M._next_selectable(buf.lines, 0, 1, 1, buf.mode_filter)
    if target >= 1 then
      move_cursor(buf, target)
    end
    return
  end
  move_cursor(buf, 1)
end
function M.goto_bottom(buf)
  for i = #buf.lines, 1, -1 do
    if buf.lines[i].selectable and (not buf.mode_filter or buf.mode_filter(buf.lines[i], i)) then
      move_cursor(buf, i)
      return
    end
  end
end

return M

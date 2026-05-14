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

---Assign file(s) to a branch via inline picker.
function M.assign_to_branch(buf)
  local selected = buf:get_selected_lines({ 'file', 'committed_file' })
  local targets
  if #selected > 0 then
    targets = selected
  else
    local line = buf:get_cursor_line()
    if not line or (line.type ~= 'file' and line.type ~= 'committed_file') or not line.data then
      return
    end
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
---When files are selected, only those files are committed. Otherwise all changes.
function M.commit(buf)
  local branch = buf:get_cursor_branch()
  local branch_name = branch and branch.name or nil

  local selected = buf:get_selected_lines({ 'file' })
  local file_ids
  if #selected > 0 then
    file_ids = {}
    for _, line in ipairs(selected) do
      table.insert(file_ids, line.data.cli_id)
    end
  end

  local title = 'Commit' .. (branch_name and (' to ' .. branch_name) or '')
  if file_ids then
    title = title .. ' (' .. #file_ids .. ' file' .. (#file_ids > 1 and 's' or '') .. ')'
  end

  float.input({
    title = title,
    on_submit = function(message)
      notify_start('commit')
      cli.commit(branch_name, message, function(err, result)
        buf:clear_selection()
        notify_result('commit', err, result)
      end, file_ids)
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
  if not line or line.type ~= 'commit' or not line.data then
    return
  end
  local sha = line.data.sha
  if not sha then
    return
  end
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
    if not line or line.type ~= 'commit' or not line.data then
      return
    end
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

---Undo last operation.
function M.undo(_buf)
  notify_start('undo')
  cli.undo(function(err, result)
    notify_result('undo', err, result)
  end)
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

---Format a step-tagged error message used by surface_error/surface_warn.
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

---Notify WARN + write to :messages history. Used for non-fatal cleanup steps.
local function surface_warn(step, body)
  local msg = M.format_step_error(step, body)
  vim.notify(msg, vim.log.levels.WARN)
  vim.api.nvim_echo({ { msg, 'WarningMsg' } }, true, {})
end

---Check whether advancing `target` to `ephemeral_sha` would be a fast-forward,
---i.e. whether `target` is an ancestor of `ephemeral_sha`.
---@return boolean? true if FF-safe, false if not, nil on git error
local function is_fast_forward(target, ephemeral_sha)
  local r = vim
    .system({ 'git', 'merge-base', '--is-ancestor', target, ephemeral_sha }, { text = true })
    :wait()
  if r.code == 0 then
    return true
  elseif r.code == 1 then
    return false
  end
  return nil
end

---Resolve the local target branch name (e.g. 'main' or 'master') via origin/HEAD,
---falling back to a local-branch probe if origin has no HEAD ref.
local function resolve_target_branch()
  local head = vim.system({ 'git', 'symbolic-ref', '--short', 'refs/remotes/origin/HEAD' }, { text = true }):wait()
  if head.code == 0 and head.stdout then
    local ref = vim.trim(head.stdout)
    local stripped = ref:gsub('^origin/', '')
    if stripped ~= '' then
      return stripped
    end
  end

  for _, name in ipairs({ 'main', 'master' }) do
    local probe = vim.system({ 'git', 'rev-parse', '--verify', name }, { text = true }):wait()
    if probe.code == 0 then
      return name
    end
  end

  return nil
end

---Push <target> to origin via raw git. The target ref sits outside GitButler's
---virtual-branch surface, so `but push` is not the right tool here.
local function git_push_target(target, callback)
  vim.system({ 'git', 'push', 'origin', target .. ':' .. target }, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        local msg = (result.stderr and result.stderr ~= '') and result.stderr
          or ('git push exited with code ' .. result.code)
        callback(vim.trim(msg))
      else
        callback(nil)
      end
    end)
  end)
end

---Commit selected (or unassigned) files onto an ephemeral virtual branch,
---advance the local target ref via git update-ref after a fast-forward
---pre-flight, push the target to origin, then sync the workspace via
---but pull + but clean and delete the remote ephemeral ref.
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

      notify_start('commit')
      cli.commit(ephemeral_name, message, function(commit_err, commit_result)
        if commit_err then
          buf:clear_selection()
          surface_error('commit', commit_err)
          refresh()
          return
        end

        local ephemeral_sha = type(commit_result) == 'table' and commit_result.commit_id or nil
        if not ephemeral_sha or ephemeral_sha == '' then
          buf:clear_selection()
          surface_error('commit', 'no commit_id in response from but commit')
          refresh()
          return
        end

        local target = resolve_target_branch()
        if not target then
          buf:clear_selection()
          surface_error('target-resolve', 'could not resolve target branch (no origin/HEAD, no local main/master)')
          refresh()
          return
        end

        -- Step 3: refresh remote-tracking ref (non-fatal).
        local fetch = vim.system({ 'git', 'fetch', 'origin', target }, { text = true }):wait()
        if fetch.code ~= 0 then
          surface_warn('fetch', vim.trim(fetch.stderr or ('exit ' .. fetch.code)))
        end

        -- Step 4: fast-forward pre-flight.
        local ff = is_fast_forward(target, ephemeral_sha)
        if ff == false then
          buf:clear_selection()
          local local_sha = vim.trim((vim.system({ 'git', 'rev-parse', '--short', target }, { text = true }):wait().stdout or ''))
          local origin_sha = vim.trim((vim.system({ 'git', 'rev-parse', '--short', 'origin/' .. target }, { text = true }):wait().stdout or ''))
          surface_error(
            'preflight',
            'local ' .. target .. ' not ancestor of new commit — reconcile manually before retrying.\n'
              .. 'local ' .. target .. ' is at ' .. local_sha .. ', origin/' .. target .. ' is at ' .. origin_sha .. '. Try:\n'
              .. '  git fetch origin && git reset --hard origin/' .. target
          )
          refresh()
          return
        elseif ff == nil then
          buf:clear_selection()
          surface_error('preflight', 'git merge-base --is-ancestor failed')
          refresh()
          return
        end

        -- Step 5: advance local target ref.
        local upd = vim.system({ 'git', 'update-ref', 'refs/heads/' .. target, ephemeral_sha }, { text = true }):wait()
        if upd.code ~= 0 then
          buf:clear_selection()
          surface_error('update-ref', vim.trim(upd.stderr or ('exit ' .. upd.code)))
          refresh()
          return
        end

        -- Step 6: push target to origin.
        notify_start('git push ' .. target)
        git_push_target(target, function(push_err)
          if push_err then
            buf:clear_selection()
            surface_error('push', push_err .. ' (local ' .. target .. ' already advanced; remote is now behind)')
            refresh()
            return
          end

          -- Step 7: but pull (non-fatal).
          cli.pull(function(pull_err, _)
            if pull_err then
              surface_warn('pull', pull_err)
            end

            -- Step 8: but clean (non-fatal).
            cli.clean(function(clean_err, _)
              if clean_err then
                surface_warn('clean', clean_err)
              end

              -- Step 9: delete remote ephemeral ref (non-fatal).
              vim.system({ 'git', 'push', 'origin', ':' .. ephemeral_name }, { text = true }, function(del)
                vim.schedule(function()
                  if del.code ~= 0 then
                    surface_warn('delete-remote-ephemeral', vim.trim(del.stderr or ('exit ' .. del.code)))
                  end

                  buf:clear_selection()
                  vim.notify(
                    'gitbutler: direct-to-main done (' .. target .. ' ← ' .. ephemeral_sha:sub(1, 7) .. ')',
                    vim.log.levels.INFO
                  )
                  refresh()
                end)
              end)
            end)
          end)
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
  local status_res = vim.system({ 'but', 'status', '--json' }, { text = true }):wait()
  if status_res.code ~= 0 then
    return 'but status: ' .. vim.trim(status_res.stderr or '')
  end
  local ok, decoded = pcall(vim.json.decode, status_res.stdout or '')
  if not ok or type(decoded) ~= 'table' then
    return 'but status: invalid JSON'
  end

  local cli_id
  for _, c in ipairs(decoded.unassignedChanges or {}) do
    if c.filePath == file_path then
      cli_id = c.cliId
      break
    end
  end
  if not cli_id then
    return 'file not in unassignedChanges: ' .. file_path
  end

  local ts = os.time()
  local ephemeral_name = M.ephemeral_branch_name(ts)

  -- but commit -c <ephemeral> -m <msg> -p <cli_id> --json
  local commit_res = vim
    .system({ 'but', 'commit', ephemeral_name, '-c', '-m', message, '-p', cli_id, '--json' }, { text = true })
    :wait()
  if commit_res.code ~= 0 then
    return 'commit: ' .. vim.trim(commit_res.stderr or '')
  end
  local commit_ok, commit_decoded = pcall(vim.json.decode, commit_res.stdout or '')
  local ephemeral_sha = commit_ok and type(commit_decoded) == 'table' and commit_decoded.commit_id or nil
  if not ephemeral_sha then
    return 'commit: no commit_id in response'
  end

  local target = resolve_target_branch()
  if not target then
    return 'target-resolve: could not resolve target branch'
  end

  vim.system({ 'git', 'fetch', 'origin', target }, { text = true }):wait()

  local ff = is_fast_forward(target, ephemeral_sha)
  if ff == false then
    return 'preflight: local ' .. target .. ' not ancestor of new commit'
  elseif ff == nil then
    return 'preflight: git merge-base failed'
  end

  local upd = vim.system({ 'git', 'update-ref', 'refs/heads/' .. target, ephemeral_sha }, { text = true }):wait()
  if upd.code ~= 0 then
    return 'update-ref: ' .. vim.trim(upd.stderr or '')
  end

  local push = vim.system({ 'git', 'push', 'origin', target .. ':' .. target }, { text = true }):wait()
  if push.code ~= 0 then
    return 'push: ' .. vim.trim(push.stderr or '')
  end

  vim.system({ 'but', 'pull', '--json' }, { text = true }):wait()
  vim.system({ 'but', 'clean', '--json' }, { text = true }):wait()
  vim.system({ 'git', 'push', 'origin', ':' .. ephemeral_name }, { text = true }):wait()

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
      cli.pr_new(name, message, function(err, result)
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

---Open the CI view for the branch under cursor.
function M.ci_open(buf)
  local branch = buf:get_cursor_branch()
  local name = branch and branch.name or nil
  if not name then
    vim.notify('gitbutler: no branch under cursor', vim.log.levels.WARN)
    return
  end
  if not branch.ci or branch.ci == vim.NIL then
    vim.notify('gitbutler: no CI runs for this branch', vim.log.levels.WARN)
    return
  end
  require('gitbutler.ui.ci').open(name)
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
    vim.keymap.set('n', '<Tab>', '<cmd>close<CR>', { buffer = diff_buf })
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
    'R        Create PR for the branch under cursor',
    'D        Toggle PR draft/ready',
    'C        Open CI view for branch',
    'M        Commit & push selected (or unassigned) to main',
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

---Uncommit file(s) from a commit back to unstaged.
function M.uncommit(buf)
  local selected = buf:get_selected_lines({ 'committed_file' })
  local targets
  if #selected > 0 then
    targets = selected
  else
    local line = buf:get_cursor_line()
    if not line or line.type ~= 'committed_file' or not line.data then
      return
    end
    targets = { line }
  end

  local i = 0
  local function uncommit_next()
    i = i + 1
    if i > #targets then
      buf:clear_selection()
      vim.notify('gitbutler: uncommitted ' .. #targets .. ' file(s)', vim.log.levels.INFO)
      refresh()
      return
    end
    cli.uncommit(targets[i].data.cli_id, function(err, _)
      if err then
        buf:clear_selection()
        vim.notify('gitbutler uncommit: ' .. err, vim.log.levels.ERROR)
        refresh()
        return
      end
      uncommit_next()
    end)
  end
  uncommit_next()
end

---Open commit timeline.
function M.timeline(_buf)
  require('gitbutler.ui.timeline').open()
end

return M

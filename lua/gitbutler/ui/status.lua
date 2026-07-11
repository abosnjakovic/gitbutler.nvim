local buffer_mod = require('gitbutler.ui.buffer')
local cli = require('gitbutler.cli')

local M = {}

---@type GitButlerBuffer?
M.instance = nil

---Per-session aggregate CI cache keyed by stack head branch name.
---Value: { state = 'pass' | 'fail' | 'pending' | 'unknown', sha = string }
---Invalidated when the cached sha mismatches the current head sha.
M._ci_cache = M._ci_cache or {}

---Map an aggregate state to a single suffix glyph + highlight.
---@param state? string
---@return string glyph
---@return string? highlight
local function aggregate_glyph(state)
  if state == 'pass' then
    return '✓', 'GitButlerCIPass'
  elseif state == 'fail' then
    return '✗', 'GitButlerCIFail'
  elseif state == 'pending' then
    return '◐', 'GitButlerCIRunning'
  end
  return '', nil
end

---Aggregate adapter `check[]` results into a single state.
---fail > pending > pass.
---@param checks table[]
---@return string state
local function aggregate_state(checks)
  local has_fail, has_pending, has_pass = false, false, false
  for _, c in ipairs(checks) do
    if c.status == 'in_progress' or c.status == 'queued' then
      has_pending = true
    elseif c.status == 'completed' then
      if c.conclusion == 'success' then
        has_pass = true
      else
        has_fail = true
      end
    end
  end
  if has_fail then
    return 'fail'
  elseif has_pending then
    return 'pending'
  elseif has_pass then
    return 'pass'
  end
  return 'unknown'
end

---Kick off background CI fetches for any stack head with a PR whose
---aggregate isn't in cache (or whose sha has moved). On completion,
---re-render the status buffer so the new glyph appears.
---@param data table Decoded `but status --json` payload
local function kick_off_ci_fetches(data)
  local forge_ok, forge = pcall(require, 'gitbutler.forge')
  if not forge_ok then
    return
  end
  local adapter = forge.detect_from_remote and forge.detect_from_remote() or nil
  if not adapter or not adapter.list_checks then
    return
  end

  for _, stack in ipairs(data.stacks or {}) do
    local head = stack.branches and stack.branches[1] or nil
    if head and head.name and head.reviewId and head.reviewId ~= vim.NIL then
      local head_sha = (head.commits and head.commits[1] and head.commits[1].commitId) or ''
      local cached = M._ci_cache[head.name]
      if not cached or cached.sha ~= head_sha then
        -- Mark as in-flight (state=pending, sha=head_sha) so concurrent renders don't refetch.
        M._ci_cache[head.name] = { state = 'pending', sha = head_sha, in_flight = true }
        adapter.list_checks(head.name, function(err, checks)
          if err or not checks then
            -- Leave the placeholder so we don't hammer a failing endpoint.
            M._ci_cache[head.name].in_flight = false
            return
          end
          M._ci_cache[head.name] = { state = aggregate_state(checks), sha = head_sha }
          -- Trigger a refresh so the new glyph appears. The next render's
          -- kick_off_ci_fetches will see the cache populated and not refetch.
          if M.instance then
            M.refresh()
          end
        end)
      end
    end
  end
end

---Look up the cached CI aggregate glyph for a stack. All branches in a
---stack share the head's PR, so all rows in the stack get the same glyph.
---@param stack table
---@return string glyph
local function stack_ci_suffix(stack)
  local head = stack.branches and stack.branches[1] or nil
  if not head or not head.name then
    return ''
  end
  local cached = M._ci_cache[head.name]
  if not cached or not cached.state or cached.state == 'unknown' then
    return ''
  end
  local glyph = aggregate_glyph(cached.state)
  if glyph == '' then
    return ''
  end
  return '  ' .. glyph
end

---Map changeType strings to display prefix and highlight group.
local change_display = {
  added = { prefix = 'A', hl = 'GitButlerFileAdd' },
  modified = { prefix = 'M', hl = 'GitButlerFileMod' },
  deleted = { prefix = 'D', hl = 'GitButlerFileDel' },
  renamed = { prefix = 'R', hl = 'GitButlerFileRenamed' },
}

---Map a branch.ci object from `but status --json` to a display glyph + highlight group.
---@param ci? { status?: string, conclusion?: string }
---@return string glyph
---@return string? highlight
function M.ci_glyph(ci)
  if ci == nil or ci == vim.NIL then
    return '', nil
  end
  local status_val = ci.status
  if status_val == 'queued' then
    return '○', 'GitButlerCIQueued'
  elseif status_val == 'in_progress' then
    return '◐', 'GitButlerCIRunning'
  elseif status_val == 'completed' then
    local c = ci.conclusion
    if c == 'success' then
      return '✓', 'GitButlerCIPass'
    elseif c == 'failure' or c == 'cancelled' or c == 'timed_out' then
      return '✗', 'GitButlerCIFail'
    end
  end
  return '?', 'GitButlerCIUnknown'
end

local function change_hl(change_type)
  local d = change_display[change_type]
  if d then
    return d.prefix, d.hl
  end
  return 'M', 'GitButlerFileMod'
end

---Build structured lines from but status --json output.
---
---Real JSON shape:
---  stacks[].branches[].name, .commits[].commitId, .commits[].message, .commits[].changes[].filePath
---  stacks[].assignedChanges[].filePath, .changeType
---  uncommittedChanges[].filePath, .changeType  (older CLIs: unassignedChanges)
---  mergeBase.commitId, .message
---  upstreamState.behind
---@param buf table GitButlerBuffer
---@param data table Parsed JSON
---@return GitButlerLine[]
local function build_lines(buf, data)
  local lines = {}

  local function add(text, hl, line_type, data_tbl, opts)
    opts = opts or {}
    table.insert(lines, {
      text = text,
      hl = hl,
      type = line_type,
      data = data_tbl,
      foldable = opts.foldable,
      folded = opts.folded,
      indent = opts.indent or 0,
    })
  end

  -- Header with upstream info
  local behind = data.upstreamState and data.upstreamState.behind or 0
  local header = 'GitButler Status'
  if behind > 0 then
    header = header .. '  (upstream: ' .. behind .. ' behind)'
  end
  add(header, 'GitButlerSection', 'section_header', nil)
  add('', nil, 'blank', nil)

  -- Stacks → branches
  local stacks = data.stacks or {}
  for _, stack in ipairs(stacks) do
    local assigned_changes = stack.assignedChanges or {}

    for _, branch in ipairs(stack.branches or {}) do
      local name = branch.name or '(unnamed)'
      local commits = branch.commits or {}
      local status_label = branch.branchStatus or ''

      local parts = {}
      if #commits > 0 then
        table.insert(parts, #commits .. ' commit' .. (#commits > 1 and 's' or ''))
      end
      if #assigned_changes > 0 then
        table.insert(parts, #assigned_changes .. ' uncommitted')
      end
      if status_label ~= '' and status_label ~= 'nothingToPush' then
        table.insert(parts, status_label)
      end
      local suffix = #parts > 0 and ('  (' .. table.concat(parts, ', ') .. ')') or ''

      local glyph = M.ci_glyph(branch.ci)
      local glyph_prefix = glyph ~= '' and (glyph .. ' ') or ''
      local review_suffix = ''
      if branch.reviewId and branch.reviewId ~= vim.NIL then
        review_suffix = '  #' .. tostring(branch.reviewId)
      end
      local ci_aggregate_suffix = stack_ci_suffix(stack)

      local fold_id = 'branch:' .. name
      local is_folded = buf:is_folded(fold_id)

      add(glyph_prefix .. name .. suffix .. review_suffix .. ci_aggregate_suffix, 'GitButlerBranchApplied', 'branch', {
        branch = branch,
        stack = stack,
        name = name,
        stack_cli_id = stack.cliId,
        fold_id = fold_id,
      }, { foldable = true, folded = is_folded })

      if not is_folded then
        -- Commits
        for _, commit in ipairs(commits) do
          local sha_short = (commit.commitId or ''):sub(1, 7)
          local msg = (commit.message or ''):match('^([^\n]*)') or ''

          add(sha_short .. ' ' .. msg, 'GitButlerCommitHash', 'commit', {
            commit = commit,
            sha = commit.commitId,
            cli_id = commit.cliId,
            branch_name = name,
            stack_cli_id = stack.cliId,
          }, { indent = 1 })

          -- Committed file changes (shown with -f flag)
          if commit.changes then
            for _, change in ipairs(commit.changes) do
              local prefix, hl = change_hl(change.changeType)
              add(prefix .. '  ' .. change.filePath, hl, 'committed_file', {
                path = change.filePath,
                change_type = change.changeType,
                cli_id = change.cliId,
                commit_id = commit.commitId,
                branch_name = name,
              }, { indent = 2 })
            end
          end
        end

        -- Assigned but uncommitted changes
        if #assigned_changes > 0 then
          add('Uncommitted', 'GitButlerSection', 'section_header', nil, { indent = 1 })
          for _, change in ipairs(assigned_changes) do
            local prefix, hl = change_hl(change.changeType)
            add(prefix .. '  ' .. change.filePath, hl, 'file', {
              path = change.filePath,
              change_type = change.changeType,
              cli_id = change.cliId,
              branch_name = name,
              stack_cli_id = stack.cliId,
            }, { indent = 2 })
          end
        end
      end

      add('', nil, 'blank', nil)
    end
  end

  -- Unassigned changes. Newer CLIs name this `uncommittedChanges`; older ones
  -- used `unassignedChanges`. Read either so the section survives the rename.
  local unassigned = data.uncommittedChanges or data.unassignedChanges or {}
  if #unassigned > 0 then
    local fold_id = 'unassigned'
    local is_folded = buf:is_folded(fold_id)

    add('Unassigned changes (' .. #unassigned .. ')', 'GitButlerUnassigned', 'section_header', {
      fold_id = fold_id,
    }, { foldable = true, folded = is_folded })

    if not is_folded then
      for _, change in ipairs(unassigned) do
        local prefix, hl = change_hl(change.changeType)
        add(prefix .. '  ' .. change.filePath, hl, 'file', {
          path = change.filePath,
          change_type = change.changeType,
          cli_id = change.cliId,
          branch_name = nil,
          unassigned = true,
        }, { indent = 1 })
      end
    end

    add('', nil, 'blank', nil)
  end

  -- Recent commits (from git log, always shown for context)
  local recent = data._recent_commits or {}
  if #recent > 0 then
    local fold_id = 'recent'
    local is_folded = buf:is_folded(fold_id)

    add('Recent commits (' .. #recent .. ')', 'GitButlerSection', 'section_header', {
      fold_id = fold_id,
    }, { foldable = true, folded = is_folded })

    if not is_folded then
      for _, entry in ipairs(recent) do
        add(entry.sha .. ' ' .. entry.message, 'GitButlerCommitHash', 'recent_commit', {
          sha = entry.full_sha,
          message = entry.message,
        }, { indent = 1 })
      end
    end

    add('', nil, 'blank', nil)
  end

  -- Merge base info
  local mb = data.mergeBase
  if mb and mb.commitId then
    local msg = (mb.message or ''):match('^([^\n]*)') or ''
    add('Base: ' .. (mb.commitId or ''):sub(1, 7) .. ' ' .. msg, 'GitButlerHelp', 'info', nil)
  end

  return lines
end

---Open or refresh the status buffer.
function M.open()
  if M.instance then
    M.refresh()
    return
  end

  local buf = buffer_mod.Buffer.new()
  buf.view = 'status'
  M.instance = buf

  local actions = require('gitbutler.actions')
  buf:on('open_file', actions.open_file)
  buf:on('assign_to_branch', actions.assign_to_branch)
  buf:on('absorb', actions.absorb)
  buf:on('commit', actions.commit)
  buf:on('amend', actions.amend)
  buf:on('squash', actions.squash)
  buf:on('move', actions.move)
  buf:on('describe', actions.describe)
  buf:on('undo', actions.undo)
  buf:on('push', actions.push)
  buf:on('push_all', actions.push_all)
  buf:on('pr_create', actions.pr_create)
  buf:on('pr_toggle_draft', actions.pr_toggle_draft)
  buf:on('pull', actions.pull)
  buf:on('close', actions.close)
  buf:on('refresh', function()
    M.refresh()
  end)
  buf:on('branch_new', actions.branch_new)
  buf:on('discard', actions.discard)
  buf:on('toggle_fold', actions.toggle_fold)
  buf:on('toggle_select', actions.toggle_select)
  buf:on('help', actions.help)
  buf:on('branches', actions.branches)
  buf:on('log', actions.log)
  buf:on('oplog', actions.oplog)
  buf:on('timeline', actions.timeline)
  buf:on('uncommit', actions.uncommit)
  buf:on('direct_to_main', actions.direct_to_main)
  buf:on('ci_open', actions.ci_open)

  buf:open()
  M.refresh()
end

---Fetch recent commits via git log (sync, fast).
local function get_recent_commits(count)
  local result = vim
    .system({ 'git', 'log', '--oneline', '--no-decorate', '-n', tostring(count or 10) }, { text = true })
    :wait()
  if result.code ~= 0 or not result.stdout then
    return {}
  end

  local commits = {}
  for line in result.stdout:gmatch('[^\n]+') do
    local sha, msg = line:match('^(%S+)%s+(.*)')
    if sha then
      table.insert(commits, { sha = sha, full_sha = sha, message = msg })
    end
  end
  return commits
end

---Refresh the status buffer with fresh data from `but status`.
function M.refresh()
  if not M.instance then
    return
  end
  local buf = M.instance

  cli.status(function(err, data)
    if err then
      vim.notify('gitbutler: ' .. err, vim.log.levels.ERROR)
      return
    end

    if type(data) ~= 'table' then
      vim.notify('gitbutler: unexpected status output', vim.log.levels.WARN)
      return
    end

    -- Augment with recent commits from git log
    data._recent_commits = get_recent_commits(10)

    local lines = build_lines(buf, data)
    buf:render(lines)

    -- Kick off async CI aggregate fetches for stack heads with PRs.
    -- The callback will trigger another refresh when results arrive; the
    -- cache prevents refetch loops.
    kick_off_ci_fetches(data)
  end)
end

---Close the status buffer.
function M.close()
  if M.instance then
    M.instance:close()
    M.instance = nil
  end
end

---Toggle the status buffer.
function M.toggle()
  if M.instance and M.instance.buf and vim.api.nvim_buf_is_valid(M.instance.buf) then
    M.close()
  else
    M.instance = nil
    M.open()
  end
end

return M

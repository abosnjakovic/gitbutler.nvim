local cli = require('gitbutler.cli')
local buffer_mod = require('gitbutler.ui.buffer')

local M = {}

---@type GitButlerBuffer?
M.instance = nil

---Map changeType strings to display prefix and highlight group.
local change_display = {
  added = { prefix = 'A', hl = 'GitButlerFileAdd' },
  modified = { prefix = 'M', hl = 'GitButlerFileMod' },
  deleted = { prefix = 'D', hl = 'GitButlerFileDel' },
  renamed = { prefix = 'R', hl = 'GitButlerFileRenamed' },
}

local function change_hl(change_type)
  local d = change_display[change_type]
  if d then return d.prefix, d.hl end
  return 'M', 'GitButlerFileMod'
end

---Build structured lines from but status --json output.
---
---Real JSON shape:
---  stacks[].branches[].name, .commits[].commitId, .commits[].message, .commits[].changes[].filePath
---  stacks[].assignedChanges[].filePath, .changeType
---  unassignedChanges[].filePath, .changeType
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

      local fold_id = 'branch:' .. name
      local is_folded = buf:is_folded(fold_id)

      add(name .. suffix, 'GitButlerBranchApplied', 'branch', {
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

  -- Unassigned changes
  local unassigned = data.unassignedChanges or {}
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

  add('Press ? for help', 'GitButlerHelp', 'help', nil)

  return lines
end

---Open or refresh the status buffer.
function M.open()
  if M.instance then
    M.refresh()
    return
  end

  local buf = buffer_mod.Buffer.new()
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
  buf:on('close', actions.close)
  buf:on('refresh', function() M.refresh() end)
  buf:on('branch_new', actions.branch_new)
  buf:on('discard', actions.discard)
  buf:on('toggle_fold', actions.toggle_fold)
  buf:on('help', actions.help)
  buf:on('branches', actions.branches)
  buf:on('log', actions.log)
  buf:on('oplog', actions.oplog)

  buf:open()
  M.refresh()
end

---Refresh the status buffer with fresh data from `but status`.
function M.refresh()
  if not M.instance then return end
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

    local lines = build_lines(buf, data)
    buf:render(lines)
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

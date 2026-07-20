local M = {}

local HL = {
  connector = 'GitButlerGraphConnector',
  cli_id = 'GitButlerCliId',
  section = 'GitButlerSection',
  branch = 'GitButlerBranchApplied',
  sha = 'GitButlerCommitHash',
  msg = 'GitButlerCommitMessage',
  mark = 'GitButlerMark',
  dim = 'GitButlerHelp',
  upstream = 'GitButlerUpstream',
}

local change_display = {
  added = { prefix = 'A', hl = 'GitButlerFileAdd' },
  modified = { prefix = 'M', hl = 'GitButlerFileMod' },
  deleted = { prefix = 'D', hl = 'GitButlerFileDel' },
  renamed = { prefix = 'R', hl = 'GitButlerFileRenamed' },
}

---`vim.json.decode` maps JSON null to `vim.NIL`, which is truthy, so a bare
---`x or {}` guard doesn't catch it. Use this at every list-iteration site.
local function list(v)
  return type(v) == 'table' and v or {}
end

local function change_prefix(change_type)
  local d = change_display[change_type]
  if d then
    return d.prefix, d.hl
  end
  return 'M', 'GitButlerFileMod'
end

---@class GraphRow: GitButlerLine

local function row(kind, entity, selectable)
  return { text = '', spans = {}, type = kind, data = entity, selectable = selectable == true, graph = true }
end

local function add(r, txt, hl)
  if hl then
    table.insert(r.spans, { #r.text, #r.text + #txt, hl })
  end
  r.text = r.text .. txt
end

local function subject(message)
  return (message or ''):match('^([^\n]*)') or ''
end

---Glyph for the start of a markable row: ✔︎ replaces the connector when marked.
local function lead(r, marked, glyph, glyph_hl)
  if marked then
    add(r, '✔︎', HL.mark)
  else
    add(r, glyph, glyph_hl or HL.connector)
  end
end

---Build graph rows from decoded `but status --json -f -v` output.
---@param data table
---@param state? { selected?: table<string,boolean>, fold_state?: table<string,boolean>, branch_suffix?: fun(stack: table, branch: table): {[1]:string,[2]:string?}[] }
---@return GraphRow[]
function M.build(data, state)
  state = state or {}
  local selected = state.selected or {}
  local folds = state.fold_state or {}
  local rows = {}
  local function push(r)
    table.insert(rows, r)
  end

  -- Uncommitted area. Newer CLIs name this `uncommittedChanges`; older ones
  -- used `unassignedChanges`.
  local unassigned = list(data.uncommittedChanges)
  if #unassigned == 0 then
    unassigned = list(data.unassignedChanges)
  end
  local hdr = row('uncommitted_header', { cli_id = 'zz', fold_id = 'unassigned' }, true)
  add(hdr, '╭┄', HL.connector)
  add(hdr, 'zz', HL.cli_id)
  add(hdr, ' [uncommitted]', HL.section)
  if #unassigned == 0 then
    add(hdr, ' (no changes)', HL.dim)
  end
  push(hdr)

  if not folds['unassigned'] then
    for _, ch in ipairs(unassigned) do
      local prefix, hl = change_prefix(ch.changeType)
      local key = 'change:' .. (ch.cliId or ch.filePath)
      local r = row('file', {
        path = ch.filePath,
        change_type = ch.changeType,
        cli_id = ch.cliId,
        branch_name = nil,
        unassigned = true,
        mark_key = key,
      }, true)
      lead(r, selected[key], '┊')
      add(r, '  ')
      add(r, ch.cliId or '??', HL.cli_id)
      add(r, ' ' .. prefix, hl)
      add(r, ' ' .. ch.filePath, hl)
      push(r)
    end
  end
  local gap = row('connector', nil, false)
  add(gap, '┊', HL.connector)
  push(gap)

  -- Stacks
  for _, stack in ipairs(list(data.stacks)) do
    for bi, branch in ipairs(list(stack.branches)) do
      local name = branch.name or '(unnamed)'
      local fold_id = 'branch:' .. name
      local br = row('branch', {
        branch = branch,
        stack = stack,
        name = name,
        cli_id = branch.cliId,
        stack_cli_id = stack.cliId,
        fold_id = fold_id,
      }, true)
      add(br, bi == 1 and '┊╭┄' or '┊├┄', HL.connector)
      add(br, branch.cliId or '??', HL.cli_id)
      add(br, ' [' .. name .. ']', HL.branch)
      if state.branch_suffix then
        for _, piece in ipairs(state.branch_suffix(stack, branch)) do
          add(br, piece[1], piece[2])
        end
      end
      push(br)

      if not folds[fold_id] then
        -- Stack-level assigned-but-uncommitted changes render under the head branch.
        if bi == 1 then
          for _, ch in ipairs(list(stack.assignedChanges)) do
            local prefix, hl = change_prefix(ch.changeType)
            local key = 'change:' .. (ch.cliId or ch.filePath)
            local r = row('file', {
              path = ch.filePath,
              change_type = ch.changeType,
              cli_id = ch.cliId,
              branch_name = name,
              stack_cli_id = stack.cliId,
              mark_key = key,
            }, true)
            lead(r, selected[key], '┊┊')
            add(r, '  ')
            add(r, ch.cliId or '??', HL.cli_id)
            add(r, ' ' .. prefix, hl)
            add(r, ' ' .. ch.filePath, hl)
            push(r)
          end
        end

        local pushed = branch.branchStatus == 'nothingToPush'
        for _, commit in ipairs(list(branch.commits)) do
          local key = 'commit:' .. (commit.commitId or '')
          local cr = row('commit', {
            commit = commit,
            sha = commit.commitId,
            cli_id = commit.cliId,
            branch_name = name,
            stack_cli_id = stack.cliId,
            mark_key = key,
          }, true)
          if selected[key] then
            add(cr, '✔︎', HL.mark)
          else
            add(cr, '┊', HL.connector)
            add(cr, '●', pushed and 'GitButlerCommitDotPushed' or HL.connector)
          end
          add(cr, ' ')
          add(cr, (commit.commitId or ''):sub(1, 7), HL.sha)
          add(cr, ' ' .. subject(commit.message), HL.msg)
          push(cr)

          for _, ch in ipairs(list(commit.changes)) do
            local prefix, hl = change_prefix(ch.changeType)
            local ckey = 'cfile:' .. (ch.cliId or ch.filePath)
            local fr = row('committed_file', {
              path = ch.filePath,
              change_type = ch.changeType,
              cli_id = ch.cliId,
              commit_id = commit.commitId,
              branch_name = name,
              mark_key = ckey,
            }, true)
            lead(fr, selected[ckey], '┊│')
            add(fr, '    ')
            add(fr, prefix, hl)
            add(fr, ' ' .. ch.filePath, hl)
            push(fr)
          end
        end
      end
    end
    local join = row('connector', nil, false)
    add(join, '├╯', HL.connector)
    push(join)
  end

  -- Upstream section
  local up = data.upstreamState
  if type(up) == 'table' and (up.behind or 0) > 0 then
    local lc = type(up.latestCommit) == 'table' and up.latestCommit or {}
    local r = row('upstream', { sha = lc.commitId }, false)
    add(r, '┊', HL.connector)
    add(r, '● ', HL.upstream)
    add(r, (lc.commitId or ''):sub(1, 7), HL.sha)
    add(r, ' (upstream) ⏫ ' .. up.behind .. ' commit' .. (up.behind > 1 and 's' or ''), HL.upstream)
    push(r)
  end

  -- Merge base
  local mb = data.mergeBase
  if type(mb) == 'table' and mb.commitId then
    local r = row('merge_base', { sha = mb.commitId }, true)
    add(r, '├╯ ', HL.connector)
    add(r, (mb.commitId):sub(1, 7), HL.sha)
    add(r, ' (common base)', HL.dim)
    local date = (mb.createdAt or ''):sub(1, 10)
    if date ~= '' then
      add(r, ' ' .. date, HL.dim)
    end
    add(r, ' ' .. subject(mb.message), HL.msg)
    push(r)
  end

  return rows
end

return M

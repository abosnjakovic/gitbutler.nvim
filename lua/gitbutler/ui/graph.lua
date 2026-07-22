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
  dot_pushed = 'GitButlerCommitDotPushed',
  dot_integrated = 'GitButlerCommitDotIntegrated',
  dot_modified = 'GitButlerCommitDotModified',
}

local change_display = {
  added = { prefix = 'A', hl = 'GitButlerFileAdd' },
  modified = { prefix = 'M', hl = 'GitButlerFileMod' },
  deleted = { prefix = 'D', hl = 'GitButlerFileDel' },
  renamed = { prefix = 'R', hl = 'GitButlerFileRenamed' },
}

-- git diff-tree name-status letters -> highlight, for landed-history files.
local BASE_FILE_HL = {
  A = 'GitButlerFileAdd',
  M = 'GitButlerFileMod',
  D = 'GitButlerFileDel',
  R = 'GitButlerFileRenamed',
}

---`vim.json.decode` maps JSON null to `vim.NIL`, which is truthy, so a bare
---`x or {}` guard doesn't catch it. Use this at every list-iteration site.
local function list(v)
  return type(v) == 'table' and v or {}
end

---Same as `list`, for scalar fields: JSON null decodes to `vim.NIL` (userdata),
---which survives an `x or default` guard and blows up on concat/`:sub`.
local function scalar(v, default)
  if v == nil or v == vim.NIL or type(v) == 'userdata' then
    return default
  end
  return v
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
  return scalar(message, ''):match('^([^\n]*)') or ''
end

---Fold indicator drawn between the connector glyph and the cli id.
local function fold_marker(folded)
  return folded and '▸ ' or '▾ '
end

---Commit dot glyph + highlight for one commit row.
---The payload carries no per-commit state field, so classification comes from
---`branch.branchStatus` plus the branch's `upstreamCommits` list.
---ponytail: rewritten-detection matches on subject text because the payload
---exposes no change-id. `◐` asserts divergence, so a false positive lies:
---it is only emitted when the subject is unambiguous on both sides — exactly
---one upstream match and unique among the branch's own commits. Any ambiguity
---falls back to the plain dot. Swap to change-ids if the CLI ever emits them.
---@param commit table
---@param branch table
---@return string glyph, string? hl
local function commit_dot(commit, branch)
  local status = branch.branchStatus
  if status == 'integrated' then
    return '●', HL.dot_integrated
  end

  local upstream = list(branch.upstreamCommits)
  local id = scalar(commit.commitId, '')
  -- Whole-list id scan first: an exact id match anywhere outranks any
  -- subject-based guess.
  for _, uc in ipairs(upstream) do
    if id ~= '' and scalar(uc.commitId, '') == id then
      return '●', HL.upstream
    end
  end

  local subj = subject(commit.message)
  if subj ~= '' then
    local up_matches, local_matches = 0, 0
    for _, uc in ipairs(upstream) do
      if subject(uc.message) == subj then
        up_matches = up_matches + 1
      end
    end
    for _, lc in ipairs(list(branch.commits)) do
      if subject(lc.message) == subj then
        local_matches = local_matches + 1
      end
    end
    if up_matches == 1 and local_matches == 1 then
      return '◐', HL.dot_modified
    end
  end

  if status == 'nothingToPush' then
    return '●', HL.dot_pushed
  end
  return '●', HL.connector
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
---@param state? { selected?: table<string,boolean>, fold_state?: table<string,boolean>, file_lists?: table<string,boolean>, show_all_files?: boolean, branch_suffix?: fun(stack: table, branch: table): {[1]:string,[2]:string?}[], base_history?: table, base_expanded?: table<string,boolean>, base_more?: boolean, base_count?: integer }
---@return GraphRow[]
function M.build(data, state)
  state = state or {}
  local selected = state.selected or {}
  local folds = state.fold_state or {}
  local file_lists = state.file_lists or {}
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
  -- Buffer:toggle_fold only walks rows flagged foldable.
  hdr.foldable = true
  add(hdr, '╭┄' .. fold_marker(folds['unassigned']), HL.connector)
  add(hdr, 'zz', HL.cli_id)
  add(hdr, ' [uncommitted]', HL.section)
  if #unassigned == 0 then
    add(hdr, ' (no changes)', HL.dim)
  end
  push(hdr)

  if not folds['unassigned'] then
    for _, ch in ipairs(unassigned) do
      local prefix, hl = change_prefix(ch.changeType)
      local cli_id = scalar(ch.cliId, nil)
      local path = scalar(ch.filePath, '(unknown)')
      local key = 'change:' .. (cli_id or path)
      local r = row('file', {
        path = path,
        change_type = ch.changeType,
        cli_id = cli_id,
        branch_name = nil,
        unassigned = true,
        mark_key = key,
      }, true)
      lead(r, selected[key], '┊')
      add(r, '  ')
      add(r, cli_id or '??', HL.cli_id)
      add(r, ' ' .. prefix, hl)
      add(r, ' ' .. path, hl)
      push(r)
    end
  end
  local gap = row('connector', nil, false)
  add(gap, '┊', HL.connector)
  push(gap)

  -- Stacks
  for _, stack in ipairs(list(data.stacks)) do
    for bi, branch in ipairs(list(stack.branches)) do
      local name = scalar(branch.name, '(unnamed)')
      local fold_id = 'branch:' .. name
      local branch_cli_id = scalar(branch.cliId, nil)
      local br = row('branch', {
        branch = branch,
        stack = stack,
        name = name,
        cli_id = branch_cli_id,
        stack_cli_id = scalar(stack.cliId, nil),
        fold_id = fold_id,
      }, true)
      br.foldable = true
      add(br, (bi == 1 and '┊╭┄' or '┊├┄') .. fold_marker(folds[fold_id]), HL.connector)
      add(br, branch_cli_id or '??', HL.cli_id)
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
            local cli_id = scalar(ch.cliId, nil)
            local path = scalar(ch.filePath, '(unknown)')
            local key = 'change:' .. (cli_id or path)
            local r = row('file', {
              path = path,
              change_type = ch.changeType,
              cli_id = cli_id,
              branch_name = name,
              stack_cli_id = stack.cliId,
              mark_key = key,
            }, true)
            lead(r, selected[key], '┊┊')
            add(r, '  ')
            add(r, cli_id or '??', HL.cli_id)
            add(r, ' ' .. prefix, hl)
            add(r, ' ' .. path, hl)
            push(r)
          end
        end

        for _, commit in ipairs(list(branch.commits)) do
          local key = 'commit:' .. scalar(commit.commitId, '')
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
            local glyph, glyph_hl = commit_dot(commit, branch)
            add(cr, '┊', HL.connector)
            add(cr, glyph, glyph_hl)
          end
          add(cr, ' ')
          add(cr, scalar(commit.commitId, ''):sub(1, 7), HL.sha)
          add(cr, ' ' .. subject(commit.message), HL.msg)
          push(cr)

          -- Official default: committed-file rows hidden until toggled (f/F).
          local show_files = state.show_all_files or file_lists[commit.commitId]
          for _, ch in ipairs(show_files and list(commit.changes) or {}) do
            local prefix, hl = change_prefix(ch.changeType)
            local cli_id = scalar(ch.cliId, nil)
            local path = scalar(ch.filePath, '(unknown)')
            local ckey = 'cfile:' .. (cli_id or path)
            local fr = row('committed_file', {
              path = path,
              change_type = ch.changeType,
              cli_id = cli_id,
              commit_id = commit.commitId,
              branch_name = name,
              mark_key = ckey,
            }, true)
            lead(fr, selected[ckey], '┊│')
            add(fr, '    ')
            add(fr, prefix, hl)
            add(fr, ' ' .. path, hl)
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
  local behind = type(up) == 'table' and scalar(up.behind, 0) or 0
  if behind > 0 then
    local lc = type(up.latestCommit) == 'table' and up.latestCommit or {}
    local r = row('upstream', { sha = lc.commitId }, false)
    add(r, '┊', HL.connector)
    add(r, '● ', HL.upstream)
    add(r, scalar(lc.commitId, ''):sub(1, 7), HL.sha)
    add(r, ' (upstream) ⏫ ' .. behind .. ' commit' .. (behind > 1 and 's' or ''), HL.upstream)
    push(r)
  end

  -- Merge base
  local mb = data.mergeBase
  local mb_sha = type(mb) == 'table' and scalar(mb.commitId, '') or ''
  if mb_sha ~= '' then
    local r = row('merge_base', { sha = mb_sha }, true)
    -- No stacks above means no lane to join back into: cap the trunk instead.
    add(r, #list(data.stacks) > 0 and '├╯ ' or '┴ ', HL.connector)
    add(r, mb_sha:sub(1, 7), HL.sha)
    add(r, ' (common base)', HL.dim)
    local date = scalar(mb.createdAt, ''):sub(1, 10)
    if date ~= '' then
      add(r, ' ' .. date, HL.dim)
    end
    add(r, ' ' .. subject(mb.message), HL.msg)
    push(r)
  end

  -- Landed trunk history below the common base. Read-only: these commits are
  -- already merged, so they carry no cli_id and no mutation verbs apply. The
  -- commit list is fed in via `state` from a git-log fetch so build() stays a
  -- pure function of its inputs.
  local base_hist = list(state.base_history)
  local base_expanded = state.base_expanded or {}
  for _, c in ipairs(base_hist) do
    local sha = scalar(c.sha, '')
    local short = scalar(c.short_sha, sha:sub(1, 7))
    local expanded = base_expanded[sha] == true
    local cr = row('base_commit', {
      sha = sha,
      short_sha = short,
      message = scalar(c.message, ''),
      fold_id = 'base:' .. sha,
    }, true)
    cr.foldable = true
    add(cr, '  ' .. (expanded and '▾' or '▸') .. ' ', HL.connector)
    add(cr, short, HL.sha)
    add(cr, ' ' .. subject(scalar(c.message, '')), HL.dim)
    push(cr)

    if expanded then
      for _, body_line in ipairs(list(c.body)) do
        local br = row('base_body', { sha = sha }, false)
        add(br, '      ' .. body_line, HL.msg)
        push(br)
      end
      for _, f in ipairs(list(c.files)) do
        local status = scalar(f.status, 'M')
        local hl = BASE_FILE_HL[status] or HL.msg
        local fr = row('base_file', { sha = sha, path = scalar(f.path, ''), status = status }, false)
        add(fr, '      ' .. status .. ' ' .. scalar(f.path, ''), hl)
        push(fr)
      end
    end
  end

  if state.base_more then
    local mr = row('base_more', {}, true)
    add(mr, '  ↓ load more', HL.dim)
    if state.base_count then
      add(mr, ' (' .. state.base_count .. ' shown)', HL.dim)
    end
    push(mr)
  end

  return rows
end

return M

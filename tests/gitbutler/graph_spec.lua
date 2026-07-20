local fixtures = require('tests.gitbutler.fixtures')
local graph = require('gitbutler.ui.graph')
local h = require('tests.gitbutler.helpers')

h.test('graph: uncommitted header first, with zz cli id', function()
  local rows = graph.build(fixtures.status_full, {})
  h.assert_eq('╭┄▾ zz [uncommitted]', rows[1].text)
  h.assert_eq('uncommitted_header', rows[1].type)
  h.assert_eq('zz', rows[1].data.cli_id)
  h.assert_truthy(rows[1].selectable)
end)

h.test('graph: unassigned file rows carry cli id and path', function()
  local rows = graph.build(fixtures.status_full, {})
  h.assert_eq('┊  up M neovim/.config/nvim/plugin/git.lua', rows[2].text)
  h.assert_eq('file', rows[2].type)
  h.assert_eq('up', rows[2].data.cli_id)
  h.assert_truthy(rows[2].data.unassigned)
  h.assert_truthy(rows[2].selectable)
end)

h.test('graph: empty uncommitted area says (no changes)', function()
  local rows = graph.build(fixtures.status_empty, {})
  h.assert_eq('╭┄▾ zz [uncommitted] (no changes)', rows[1].text)
end)

h.test('graph: branch header row with notch and name', function()
  local rows = graph.build(fixtures.status_full, {})
  local br
  for _, r in ipairs(rows) do
    if r.type == 'branch' then
      br = r
      break
    end
  end
  h.assert_eq('┊╭┄▾ br [feature-auth]', br.text)
  h.assert_eq('feature-auth', br.data.name)
  h.assert_eq('g0', br.data.stack_cli_id)
  h.assert_truthy(br.selectable)
end)

h.test('graph: commit rows have dot glyph, sha7, subject only', function()
  local rows = graph.build(fixtures.status_full, {})
  local commits = {}
  for _, r in ipairs(rows) do
    if r.type == 'commit' then
      table.insert(commits, r)
    end
  end
  h.assert_eq(2, #commits)
  h.assert_eq('┊● c4d75df add login endpoint', commits[1].text)
  h.assert_eq('┊● a1b2c3d initial auth setup', commits[2].text)
  h.assert_eq('c4', commits[1].data.cli_id)
  h.assert_eq('feature-auth', commits[1].data.branch_name)
end)

h.test('graph: committed files and assigned changes render with lane glyphs', function()
  local rows = graph.build(fixtures.status_full, { show_all_files = true })
  local texts = {}
  for _, r in ipairs(rows) do
    table.insert(texts, r.text)
  end
  h.assert_truthy(vim.tbl_contains(texts, '┊│    A src/auth.lua'))
  h.assert_truthy(vim.tbl_contains(texts, '┊┊  ac A src/pending.lua'))
end)

h.test('graph: committed-file rows hidden by default', function()
  local rows = graph.build(fixtures.status_full, {})
  for _, r in ipairs(rows) do
    h.assert_truthy(r.type ~= 'committed_file', 'committed_file row leaked: ' .. r.text)
  end
end)

h.test('graph: file_lists toggles a single commit file list', function()
  local sha = fixtures.status_full.stacks[1].branches[1].commits[1].commitId
  local rows = graph.build(fixtures.status_full, { file_lists = { [sha] = true } })
  local shown = {}
  for _, r in ipairs(rows) do
    if r.type == 'committed_file' then
      table.insert(shown, r)
    end
  end
  h.assert_truthy(#shown > 0, 'toggled commit shows its files')
  for _, r in ipairs(shown) do
    h.assert_eq(sha, r.data.commit_id)
  end
end)

h.test('graph: stack closes with join, merge base last', function()
  local rows = graph.build(fixtures.status_full, {})
  local last = rows[#rows]
  h.assert_eq('merge_base', last.type)
  h.assert_eq('├╯ a89ff8c (common base) 2026-03-24 Initial empty commit', last.text)
  h.assert_truthy(last.selectable)
  local join_found = false
  for _, r in ipairs(rows) do
    if r.text == '├╯' then
      join_found = true
    end
  end
  h.assert_truthy(join_found, 'stack join row ├╯ missing')
end)

h.test('graph: spans are within line byte length', function()
  local rows = graph.build(fixtures.status_full, {})
  for _, r in ipairs(rows) do
    for _, s in ipairs(r.spans or {}) do
      h.assert_truthy(s[1] >= 0 and s[2] <= #r.text and s[1] < s[2], 'bad span in: ' .. r.text)
    end
  end
end)

h.test('graph: upstream-behind row renders with empty sha and plural commits', function()
  local rows = graph.build(fixtures.status_behind, {})
  local up
  for _, r in ipairs(rows) do
    if r.type == 'upstream' then
      up = r
      break
    end
  end
  h.assert_truthy(up, 'no upstream row found')
  h.assert_eq('┊●  (upstream) ⏫ 3 commits', up.text)
  h.assert_falsy(up.selectable)
end)

h.test('graph: multi-branch stack uses stacked notch for non-head branches', function()
  local data = {
    stacks = {
      {
        cliId = 'g0',
        branches = {
          { cliId = 'b1', name = 'branch-one', commits = {} },
          { cliId = 'b2', name = 'branch-two', commits = {} },
        },
      },
    },
  }
  local rows = graph.build(data, {})
  local branches = {}
  for _, r in ipairs(rows) do
    if r.type == 'branch' then
      table.insert(branches, r)
    end
  end
  h.assert_eq(2, #branches)
  h.assert_eq('┊╭┄▾ b1 [branch-one]', branches[1].text)
  h.assert_eq('┊├┄▾ b2 [branch-two]', branches[2].text)
end)

h.test('graph: commit.changes as vim.NIL does not error', function()
  local data = vim.deepcopy(fixtures.status_full)
  data.stacks[1].branches[1].commits[1].changes = vim.NIL
  local ok, err = pcall(graph.build, data, { show_all_files = true })
  h.assert_truthy(ok, 'graph.build errored: ' .. tostring(err))
end)

h.test('graph: folded headers render ▸, expanded render ▾', function()
  local rows = graph.build(fixtures.status_full, {
    fold_state = { unassigned = true, ['branch:feature-auth'] = true },
  })
  h.assert_eq('╭┄▸ zz [uncommitted]', rows[1].text)
  for _, r in ipairs(rows) do
    if r.type == 'branch' then
      h.assert_eq('┊╭┄▸ br [feature-auth]', r.text)
    end
  end
end)

h.test('graph: vim.NIL scalars (behind, createdAt, message) render sanely', function()
  local data = vim.deepcopy(fixtures.status_full)
  data.upstreamState = { behind = vim.NIL, latestCommit = { commitId = vim.NIL } }
  data.mergeBase.createdAt = vim.NIL
  data.stacks[1].branches[1].commits[1].message = vim.NIL
  local ok, rows = pcall(graph.build, data, {})
  h.assert_truthy(ok, 'graph.build errored: ' .. tostring(rows))
  for _, r in ipairs(rows) do
    h.assert_truthy(r.type ~= 'upstream', 'behind=NIL suppresses the upstream row')
  end
  h.assert_eq('├╯ a89ff8c (common base) Initial empty commit', rows[#rows].text)
  for _, r in ipairs(rows) do
    if r.type == 'commit' then
      h.assert_eq('┊● c4d75df ', r.text)
      break
    end
  end
end)

h.test('graph: commit dots classify integrated, upstream and rewritten', function()
  local function dot_hl(branch_over)
    local data = vim.deepcopy(fixtures.status_full)
    local branch = data.stacks[1].branches[1]
    for k, v in pairs(branch_over) do
      branch[k] = v
    end
    for _, r in ipairs(graph.build(data, {})) do
      if r.type == 'commit' then
        -- spans[1] is the ┊ lane, spans[2] is the dot.
        return r.text, r.spans[2][3]
      end
    end
  end

  local _, integrated = dot_hl({ branchStatus = 'integrated' })
  h.assert_eq('GitButlerCommitDotIntegrated', integrated)

  local _, pushed = dot_hl({ branchStatus = 'nothingToPush' })
  h.assert_eq('GitButlerCommitDotPushed', pushed)

  local _, local_only = dot_hl({ branchStatus = 'completelyUnpushed' })
  h.assert_eq('GitButlerGraphConnector', local_only)

  local sha = fixtures.status_full.stacks[1].branches[1].commits[1].commitId
  local _, upstream = dot_hl({ upstreamCommits = { { commitId = sha, message = 'x' } } })
  h.assert_eq('GitButlerUpstream', upstream)

  local text, rewritten = dot_hl({
    upstreamCommits = { { commitId = 'deadbeef', message = 'add login endpoint' } },
  })
  h.assert_eq('GitButlerCommitDotModified', rewritten)
  h.assert_truthy(text:find('◐', 1, true), 'rewritten commit uses ◐: ' .. text)
end)

h.test('graph: merge base caps with ┴ when no stacks precede it', function()
  local rows = graph.build(fixtures.status_empty, {})
  local last = rows[#rows]
  h.assert_eq('merge_base', last.type)
  h.assert_truthy(last.text:sub(1, #'┴') == '┴', 'empty workspace caps the trunk: ' .. last.text)
end)

h.test('graph: ambiguous subjects never claim a rewrite', function()
  local data = vim.deepcopy(fixtures.status_full)
  local branch = data.stacks[1].branches[1]
  -- Two local commits share one subject; the single upstream entry cannot
  -- name which of them it rewrote, so neither may claim ◐.
  branch.commits[1].message = 'updates'
  branch.commits[2].message = 'updates'
  branch.upstreamCommits = { { commitId = 'deadbeef', message = 'updates' } }
  for _, r in ipairs(graph.build(data, {})) do
    if r.type == 'commit' then
      h.assert_falsy(r.text:find('◐', 1, true), 'ambiguous subject stays a plain dot: ' .. r.text)
      h.assert_truthy(r.spans[2][3] ~= 'GitButlerCommitDotModified', 'no rewrite highlight')
    end
  end
end)

h.test('graph: an exact id match anywhere in upstreamCommits beats a subject match', function()
  local data = vim.deepcopy(fixtures.status_full)
  local branch = data.stacks[1].branches[1]
  local sha = branch.commits[1].commitId
  -- The subject-matching decoy comes FIRST; the real id match is second.
  branch.upstreamCommits = {
    { commitId = 'deadbeef', message = branch.commits[1].message },
    { commitId = sha, message = 'unrelated' },
  }
  for _, r in ipairs(graph.build(data, {})) do
    if r.type == 'commit' and r.data.sha == sha then
      h.assert_eq('GitButlerUpstream', r.spans[2][3])
    end
  end
end)

h.test('graph: absent ids and empty subjects do not collide into a state', function()
  local data = vim.deepcopy(fixtures.status_full)
  local branch = data.stacks[1].branches[1]
  branch.branchStatus = 'completelyUnpushed'
  branch.commits[1].commitId = vim.NIL
  branch.commits[1].message = vim.NIL
  branch.upstreamCommits = { { commitId = vim.NIL, message = vim.NIL } }
  for _, r in ipairs(graph.build(data, {})) do
    if r.type == 'commit' then
      h.assert_eq('GitButlerGraphConnector', r.spans[2][3], 'empty vs empty is not a match: ' .. r.text)
    end
  end
end)

-- The CLI emits JSON null (vim.NIL) for absent fields, and vim.NIL is TRUTHY,
-- so `x or default` guards walk straight through it. Two separate reviews found
-- crash sites this fuzz would have caught; it asserts the whole payload surface
-- rather than the three fields a plan happened to name.
h.test('graph: vim.NIL in any payload field does not crash the render', function()
  local paths = {
    { 'uncommittedChanges', 1, 'cliId' },
    { 'uncommittedChanges', 1, 'filePath' },
    { 'uncommittedChanges', 1, 'changeType' },
    { 'stacks', 1, 'cliId' },
    { 'stacks', 1, 'assignedChanges', 1, 'cliId' },
    { 'stacks', 1, 'assignedChanges', 1, 'filePath' },
    { 'stacks', 1, 'branches', 1, 'cliId' },
    { 'stacks', 1, 'branches', 1, 'name' },
    { 'stacks', 1, 'branches', 1, 'branchStatus' },
    { 'stacks', 1, 'branches', 1, 'commits', 1, 'cliId' },
    { 'stacks', 1, 'branches', 1, 'commits', 1, 'commitId' },
    { 'stacks', 1, 'branches', 1, 'commits', 1, 'message' },
    { 'stacks', 1, 'branches', 1, 'commits', 1, 'changes', 1, 'cliId' },
    { 'stacks', 1, 'branches', 1, 'commits', 1, 'changes', 1, 'filePath' },
    { 'mergeBase', 'commitId' },
    { 'mergeBase', 'createdAt' },
    { 'mergeBase', 'message' },
    { 'upstreamState', 'behind' },
    { 'upstreamState', 'latestCommit' },
  }

  for _, path in ipairs(paths) do
    local data = vim.deepcopy(fixtures.status_full)
    local node = data
    for i = 1, #path - 1 do
      node = node and node[path[i]]
    end
    if node then
      node[path[#path]] = vim.NIL
      local ok, err = pcall(graph.build, data, { show_all_files = true })
      h.assert_truthy(ok, 'vim.NIL at ' .. table.concat(vim.tbl_map(tostring, path), '.') .. ' → ' .. tostring(err))
    end
  end
end)

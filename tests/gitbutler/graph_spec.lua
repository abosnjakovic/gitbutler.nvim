local fixtures = require('tests.gitbutler.fixtures')
local graph = require('gitbutler.ui.graph')
local h = require('tests.gitbutler.helpers')

h.test('graph: uncommitted header first, with zz cli id', function()
  local rows = graph.build(fixtures.status_full, {})
  h.assert_eq('╭┄zz [uncommitted]', rows[1].text)
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
  h.assert_eq('╭┄zz [uncommitted] (no changes)', rows[1].text)
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
  h.assert_eq('┊╭┄br [feature-auth]', br.text)
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
  local rows = graph.build(fixtures.status_full, {})
  local texts = {}
  for _, r in ipairs(rows) do
    table.insert(texts, r.text)
  end
  h.assert_truthy(vim.tbl_contains(texts, '┊│    A src/auth.lua'))
  h.assert_truthy(vim.tbl_contains(texts, '┊┊  ac A src/pending.lua'))
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
  h.assert_eq('┊╭┄b1 [branch-one]', branches[1].text)
  h.assert_eq('┊├┄b2 [branch-two]', branches[2].text)
end)

h.test('graph: commit.changes as vim.NIL does not error', function()
  local data = vim.deepcopy(fixtures.status_full)
  data.stacks[1].branches[1].commits[1].changes = vim.NIL
  local ok, err = pcall(graph.build, data, {})
  h.assert_truthy(ok, 'graph.build errored: ' .. tostring(err))
end)

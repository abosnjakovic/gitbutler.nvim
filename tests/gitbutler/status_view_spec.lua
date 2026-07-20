local fixtures = require('tests.gitbutler.fixtures')
local h = require('tests.gitbutler.helpers')
local test, assert_eq, assert_truthy, assert_falsy = h.test, h.assert_eq, h.assert_truthy, h.assert_falsy

print('\n=== Status view tests ===')

---Collect the set of highlight groups used by a graph row's spans.
local function span_hls(line)
  local hls = {}
  for _, s in ipairs(line.spans or {}) do
    hls[s[3]] = true
  end
  return hls
end

test('status: renders graph rows', function()
  local lines = h.capture_lines(fixtures.status_full)
  assert_eq('╭┄▾ zz [uncommitted]', lines[1].text)
  assert_truthy(lines[1].graph)
  local found_branch = false
  for _, l in ipairs(lines) do
    if l.type == 'branch' and l.data.name == 'feature-auth' then
      found_branch = true
    end
  end
  assert_truthy(found_branch)
end)

test('renders branch from stacks', function()
  local lines = h.capture_lines(fixtures.status_full)
  assert_truthy(lines)

  local branch_line
  for _, l in ipairs(lines) do
    if l.type == 'branch' then
      branch_line = l
      break
    end
  end

  assert_truthy(branch_line)
  assert_eq('feature-auth', branch_line.data.name)
  assert_truthy(branch_line.foldable, 'branch header is foldable')
  assert_truthy(span_hls(branch_line)['GitButlerBranchApplied'], 'branch name span highlighted')
end)

test('renders commits with sha and message', function()
  local lines = h.capture_lines(fixtures.status_full)

  local commit
  for _, l in ipairs(lines) do
    if l.type == 'commit' then
      commit = l
      break
    end
  end

  assert_truthy(commit)
  assert_eq('c4d75dfd95bf28d3ce1b6dc1a99bb96338aae8fa', commit.data.sha)
  assert_eq('feature-auth', commit.data.branch_name)
  assert_truthy(commit.text:find('c4d75df'), 'short sha in text')
  assert_truthy(commit.text:find('add login endpoint'), 'message in text')
end)

test('renders committed files with cli_id', function()
  local lines = h.capture_lines(fixtures.status_full, true)

  local files = {}
  for _, l in ipairs(lines) do
    if l.type == 'committed_file' then
      table.insert(files, l)
    end
  end

  assert_eq(2, #files)
  assert_eq('src/auth.lua', files[1].data.path)
  assert_eq('c4:xw', files[1].data.cli_id)
  assert_truthy(span_hls(files[1])['GitButlerFileAdd'], 'added file span highlighted')
end)

test('renders assigned uncommitted changes', function()
  local lines = h.capture_lines(fixtures.status_full)

  local assigned = {}
  for _, l in ipairs(lines) do
    if l.type == 'file' and l.data and l.data.branch_name then
      table.insert(assigned, l)
    end
  end

  assert_eq(1, #assigned)
  assert_eq('src/pending.lua', assigned[1].data.path)
  assert_eq('ac', assigned[1].data.cli_id)
end)

test('renders unassigned changes with cli_id', function()
  local lines = h.capture_lines(fixtures.status_full)

  local unassigned = {}
  for _, l in ipairs(lines) do
    if l.type == 'file' and l.data and l.data.unassigned then
      table.insert(unassigned, l)
    end
  end

  assert_eq(2, #unassigned)
  assert_eq('neovim/.config/nvim/plugin/git.lua', unassigned[1].data.path)
  assert_eq('up', unassigned[1].data.cli_id)
  assert_eq('plan.md', unassigned[2].data.path)
end)

test('shows upstream behind count as upstream row', function()
  local lines = h.capture_lines(fixtures.status_behind)
  local up
  for _, l in ipairs(lines) do
    if l.type == 'upstream' then
      up = l
      break
    end
  end
  assert_truthy(up, 'upstream row rendered')
  assert_truthy(up.text:find('⏫ 3 commits', 1, true), 'behind count in upstream row')
end)

test('handles empty workspace', function()
  local lines = h.capture_lines(fixtures.status_empty)
  assert_truthy(lines)
  assert_eq('╭┄▾ zz [uncommitted] (no changes)', lines[1].text)
  assert_truthy(#lines >= 2, 'at least uncommitted header + merge base')
end)

test('truncates multiline commit messages', function()
  local lines = h.capture_lines(fixtures.status_full)

  local commits = {}
  for _, l in ipairs(lines) do
    if l.type == 'commit' then
      table.insert(commits, l)
    end
  end

  assert_truthy(#commits >= 2)
  assert_truthy(commits[2].text:find('initial auth setup'))
  assert_falsy(commits[2].text:find('multiline'))
end)

test('rerender bakes marks and folds from cached data without a CLI call', function()
  local status = require('gitbutler.ui.status')
  local buf = h.mock_buffer()
  local cap = h.mock_render(buf)
  buf.selected = { ['change:up'] = true }
  buf.fold_state = { ['branch:feature-auth'] = true }
  status.instance = buf
  status.data = fixtures.status_full

  status.rerender()

  status.instance = nil
  status.data = nil

  assert_truthy(cap.lines, 'rerender produced rows')
  assert_truthy(cap.lines[2].text:find('✔︎', 1, true), 'marked row shows check glyph')
  for _, l in ipairs(cap.lines) do
    assert_truthy(l.type ~= 'commit', 'folded branch hides commits')
  end
end)

local h = require('tests.gitbutler.helpers')
local fixtures = require('tests.gitbutler.fixtures')
local test, assert_eq, assert_truthy, assert_falsy = h.test, h.assert_eq, h.assert_truthy, h.assert_falsy

print('\n=== Status view tests ===')

test('renders branch from stacks', function()
  local lines = h.capture_lines(fixtures.status_full)
  assert_truthy(lines)

  local branch_line
  for _, l in ipairs(lines) do
    if l.type == 'branch' then branch_line = l; break end
  end

  assert_truthy(branch_line)
  assert_eq('feature-auth', branch_line.data.name)
  assert_eq('GitButlerBranchApplied', branch_line.hl)
end)

test('renders commits with sha and message', function()
  local lines = h.capture_lines(fixtures.status_full)

  local commit
  for _, l in ipairs(lines) do
    if l.type == 'commit' then commit = l; break end
  end

  assert_truthy(commit)
  assert_eq('c4d75dfd95bf28d3ce1b6dc1a99bb96338aae8fa', commit.data.sha)
  assert_eq('feature-auth', commit.data.branch_name)
  assert_truthy(commit.text:find('c4d75df'), 'short sha in text')
  assert_truthy(commit.text:find('add login endpoint'), 'message in text')
end)

test('renders committed files with cli_id', function()
  local lines = h.capture_lines(fixtures.status_full)

  local files = {}
  for _, l in ipairs(lines) do
    if l.type == 'committed_file' then table.insert(files, l) end
  end

  assert_eq(2, #files)
  assert_eq('src/auth.lua', files[1].data.path)
  assert_eq('c4:xw', files[1].data.cli_id)
  assert_eq('GitButlerFileAdd', files[1].hl)
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

test('shows upstream behind count in header', function()
  local lines = h.capture_lines(fixtures.status_behind)
  assert_truthy(lines[1].text:find('3 behind'), 'behind in header')
end)

test('handles empty workspace', function()
  local lines = h.capture_lines(fixtures.status_empty)
  assert_truthy(lines)
  assert_truthy(#lines >= 2, 'at least header + help')
end)

test('truncates multiline commit messages', function()
  local lines = h.capture_lines(fixtures.status_full)

  local commits = {}
  for _, l in ipairs(lines) do
    if l.type == 'commit' then table.insert(commits, l) end
  end

  assert_truthy(#commits >= 2)
  assert_truthy(commits[2].text:find('initial auth setup'))
  assert_falsy(commits[2].text:find('multiline'))
end)

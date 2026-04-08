local h = require('tests.gitbutler.helpers')
local fixtures = require('tests.gitbutler.fixtures')
local timeline = require('gitbutler.ui.timeline')
local test, assert_eq, assert_truthy = h.test, h.assert_eq, h.assert_truthy

print('\n=== Timeline view tests ===')

test('parse_git_log parses structured git log output', function()
  local raw = table.concat({
    'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2|a1b2c3d|adam|2026-04-08|origin/main, main|Fix auth bug',
    'f4e5d6c7a8b9f4e5d6c7a8b9f4e5d6c7a8b9f4e5|f4e5d6c|sarah|2026-04-08|feat/ui|Update sidebar',
    '8c9d0e1f2a3b8c9d0e1f2a3b8c9d0e1f2a3b8c9d|8c9d0e1|adam|2026-04-07||Add endpoint',
  }, '\n')

  local commits = timeline.parse_git_log(raw)
  assert_eq(3, #commits)
  assert_eq('a1b2c3d', commits[1].short_sha)
  assert_eq('adam', commits[1].author)
  assert_eq('2026-04-08', commits[1].date)
  assert_eq('origin/main, main', commits[1].refs)
  assert_eq('Fix auth bug', commits[1].message)
  assert_eq('', commits[3].refs)
end)

test('parse_git_log handles empty input', function()
  local commits = timeline.parse_git_log('')
  assert_eq(0, #commits)
end)

test('parse_git_log handles message with pipe characters', function()
  local raw = 'abc123abc123abc123abc123abc123abc123abc12345|abc1234|adam|2026-04-08|main|Fix foo|bar baz'
  local commits = timeline.parse_git_log(raw)
  assert_eq(1, #commits)
  assert_eq('Fix foo|bar baz', commits[1].message)
end)

test('parse_diff_tree parses name-status output', function()
  local raw = table.concat({
    'M\tsrc/auth.lua',
    'A\tsrc/token.lua',
    'D\tsrc/old.lua',
  }, '\n')

  local files = timeline.parse_diff_tree(raw)
  assert_eq(3, #files)
  assert_eq('src/auth.lua', files[1].path)
  assert_eq('M', files[1].status)
  assert_eq('src/token.lua', files[2].path)
  assert_eq('A', files[2].status)
  assert_eq('D', files[3].status)
end)

test('parse_diff_tree handles empty output', function()
  local files = timeline.parse_diff_tree('')
  assert_eq(0, #files)
end)

test('build_lines groups commits by date', function()
  local buf = h.mock_buffer()
  local lines = timeline.build_lines(buf, fixtures.timeline_commits, 7)

  local headers = {}
  for _, l in ipairs(lines) do
    if l.type == 'date_header' then table.insert(headers, l) end
  end

  assert_eq(2, #headers)
  assert_truthy(headers[1].text:find('2026%-04%-08'))
  assert_truthy(headers[2].text:find('2026%-04%-07'))
end)

test('build_lines creates timeline_commit lines with correct data', function()
  local buf = h.mock_buffer()
  local lines = timeline.build_lines(buf, fixtures.timeline_commits, 7)

  local commits = {}
  for _, l in ipairs(lines) do
    if l.type == 'timeline_commit' then table.insert(commits, l) end
  end

  assert_eq(3, #commits)
  assert_eq('a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2', commits[1].data.sha)
  assert_eq('adam', commits[1].data.author)
  assert_eq('origin/main, main', commits[1].data.refs)
  assert_truthy(commits[1].text:find('a1b2c3d'))
  assert_truthy(commits[1].text:find('adam'))
  assert_truthy(commits[1].text:find('Fix auth bug'))
end)

test('build_lines renders refs in commit text when present', function()
  local buf = h.mock_buffer()
  local lines = timeline.build_lines(buf, fixtures.timeline_commits, 7)

  local first_commit
  for _, l in ipairs(lines) do
    if l.type == 'timeline_commit' then first_commit = l; break end
  end

  assert_truthy(first_commit.text:find('main'))
end)

test('build_lines omits ref column when refs empty', function()
  local buf = h.mock_buffer()
  local lines = timeline.build_lines(buf, fixtures.timeline_commits, 7)

  local third_commit
  local count = 0
  for _, l in ipairs(lines) do
    if l.type == 'timeline_commit' then
      count = count + 1
      if count == 3 then third_commit = l; break end
    end
  end

  assert_eq('', third_commit.data.refs)
end)

test('build_lines handles empty commit list', function()
  local buf = h.mock_buffer()
  local lines = timeline.build_lines(buf, fixtures.timeline_commits_empty, 7)

  assert_truthy(#lines >= 2)
  local commits = {}
  for _, l in ipairs(lines) do
    if l.type == 'timeline_commit' then table.insert(commits, l) end
  end
  assert_eq(0, #commits)
end)

test('build_lines marks commits as foldable', function()
  local buf = h.mock_buffer()
  local lines = timeline.build_lines(buf, fixtures.timeline_commits, 7)

  local commit
  for _, l in ipairs(lines) do
    if l.type == 'timeline_commit' then commit = l; break end
  end

  assert_truthy(commit.foldable)
  assert_truthy(commit.folded, 'commits start folded')
end)

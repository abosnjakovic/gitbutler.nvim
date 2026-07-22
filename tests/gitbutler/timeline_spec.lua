local h = require('tests.gitbutler.helpers')
local timeline = require('gitbutler.ui.timeline')
local test, assert_eq, assert_truthy = h.test, h.assert_eq, h.assert_truthy

print('\n=== Landed-history helper tests ===')

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

-- fetch_base excludes the base commit itself (--skip=1) so it isn't shown
-- twice: once as the (common base) row and once in the history below it.
test('fetch_base passes --skip=1 and the base sha to git log', function()
  local captured
  local orig = vim.system
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.system = function(cmd)
    captured = cmd
    return { wait = function() end }
  end
  timeline.fetch_base('deadbeef', 15, function() end)
  vim.system = orig

  assert_truthy(vim.tbl_contains(captured, '--skip=1'), 'skips the base commit itself')
  assert_eq('deadbeef', captured[#captured], 'base sha is the final positional arg')
  local n_idx
  for i, a in ipairs(captured) do
    if a == '-n' then
      n_idx = i
    end
  end
  assert_eq('15', captured[n_idx + 1], 'limit is passed to -n')
end)

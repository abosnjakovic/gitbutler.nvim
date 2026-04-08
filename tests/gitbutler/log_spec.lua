local h = require('tests.gitbutler.helpers')
local fixtures = require('tests.gitbutler.fixtures')
local test, assert_eq, assert_truthy, assert_type = h.test, h.assert_eq, h.assert_truthy, h.assert_type

print('\n=== Log view tests ===')

test('show_branch fixture has correct structure', function()
  local data = fixtures.show_branch
  assert_eq('feature-auth', data.branch)
  assert_eq(2, #data.commits)
  assert_eq('9331c55fb5b4f279474e60e07f106a9b354f8cad', data.commits[1].sha)
  assert_eq('9331c55fb', data.commits[1].short_sha)
  assert_eq(3, data.commits[1].files_changed)
  assert_eq(3, #data.commits[1].files)
end)

test('show_branch files have stats', function()
  local file = fixtures.show_branch.commits[1].files[1]
  assert_eq('src/auth.lua', file.path)
  assert_eq('added', file.status)
  assert_eq(80, file.insertions)
  assert_eq(0, file.deletions)
end)

test('show_branch_empty has no commits', function()
  assert_eq(0, #fixtures.show_branch_empty.commits)
  assert_eq('empty-branch', fixtures.show_branch_empty.branch)
end)

test('show_branch full_message preserves multiline', function()
  local msg = fixtures.show_branch.commits[1].full_message
  assert_truthy(msg:find('\n'), 'full_message has newline')
  assert_truthy(msg:find('JWT'), 'full_message has body')
end)

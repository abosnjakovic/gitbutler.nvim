local fixtures = require('tests.gitbutler.fixtures')
local h = require('tests.gitbutler.helpers')
local log = require('gitbutler.ui.log')
local test, assert_eq, assert_truthy = h.test, h.assert_eq, h.assert_truthy

local function mock_buf(folded_ids)
  folded_ids = folded_ids or {}
  return {
    is_folded = function(_, id)
      return folded_ids[id] == true
    end,
    fold_state = {},
  }
end

local function find_lines(lines, line_type)
  local out = {}
  for _, line in ipairs(lines) do
    if line.type == line_type then
      table.insert(out, line)
    end
  end
  return out
end

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

test('build_lines renders body when commit expanded', function()
  local lines = log.build_lines(mock_buf(), fixtures.show_branch)
  local body = find_lines(lines, 'commit_body')
  assert_eq(1, #body, 'one body line for first commit (subject-only commit 2 has none)')
  assert_eq('Implements the /login route with JWT', body[1].text)
  assert_eq('GitButlerCommitBody', body[1].hl)
  assert_eq(1, body[1].indent)
end)

test('build_lines hides body when commit folded', function()
  local folded = { ['commit:9331c55fb5b4f279474e60e07f106a9b354f8cad'] = true }
  local lines = log.build_lines(mock_buf(folded), fixtures.show_branch)
  local body = find_lines(lines, 'commit_body')
  assert_eq(0, #body, 'folded commit emits no body lines')
end)

test('build_lines stores full_message in commit data for reword', function()
  local lines = log.build_lines(mock_buf(), fixtures.show_branch)
  local commits = find_lines(lines, 'commit')
  assert_eq(2, #commits)
  assert_eq('add login endpoint\n\nImplements the /login route with JWT', commits[1].data.full_message)
  assert_eq('initial setup', commits[2].data.full_message)
end)

test('build_lines emits blank separator only when body and files both present', function()
  local lines = log.build_lines(mock_buf(), fixtures.show_branch)
  -- Commit 1 has body + files: expect a blank with indent=1 after body
  local indented_blanks = 0
  for _, line in ipairs(lines) do
    if line.type == 'blank' and line.indent == 1 then
      indented_blanks = indented_blanks + 1
    end
  end
  assert_eq(1, indented_blanks, 'one indented separator (commit 1 only; commit 2 has no body)')
end)

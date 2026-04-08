local h = require('tests.gitbutler.helpers')
local fixtures = require('tests.gitbutler.fixtures')
local test, assert_eq, assert_falsy, assert_type = h.test, h.assert_eq, h.assert_falsy, h.assert_type

print('\n=== Branch data tests ===')

test('branch list fixture has correct structure', function()
  local data = fixtures.branch_list
  assert_eq(1, #data.appliedStacks)
  assert_eq('feature-auth', data.appliedStacks[1].heads[1].name)
  assert_eq(1, #data.branches)
  assert_eq('old-experiment', data.branches[1].name)
end)

test('nil commitsAhead is not a number (vim.NIL)', function()
  local head = fixtures.branch_list.appliedStacks[1].heads[1]
  assert_falsy(type(head.commitsAhead) == 'number')
end)

test('numeric commitsAhead is preserved', function()
  local branch = fixtures.branch_list.branches[1]
  assert_type('number', branch.commitsAhead)
  assert_eq(83, branch.commitsAhead)
end)

test('empty branch list has correct structure', function()
  local data = fixtures.branch_list_empty
  assert_eq(0, #data.appliedStacks)
  assert_eq(0, #data.branches)
end)

local fixtures = require('tests.gitbutler.fixtures')
local h = require('tests.gitbutler.helpers')
local test, assert_eq, assert_falsy, assert_type, assert_truthy =
  h.test, h.assert_eq, h.assert_falsy, h.assert_type, h.assert_truthy

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

-- Regression: rendering a branch whose commitsAhead is vim.NIL (JSON null)
-- once crashed on a string concatenation. Ported from the orphaned
-- branch_spec.lua (busted-style, never wired into the runner).
test('branch.open does not crash on nil commitsAhead', function()
  local branch_ui = require('gitbutler.ui.branch')
  local cli = require('gitbutler.cli')
  local float = require('gitbutler.ui.float')

  local orig_list, orig_open = cli.branch_list, float.open
  cli.branch_list = function(callback)
    callback(nil, fixtures.branch_list)
  end
  float.open = function()
    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(buf, false, {
      relative = 'editor',
      width = 10,
      height = 5,
      row = 0,
      col = 0,
      style = 'minimal',
    })
    return buf, win
  end

  local ok = pcall(branch_ui.open)

  cli.branch_list, float.open = orig_list, orig_open
  assert_truthy(ok, 'branch.open threw on vim.NIL commitsAhead')
end)

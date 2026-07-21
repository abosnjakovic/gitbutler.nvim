local commit_diff = require('gitbutler.ui.commit_diff')
local config = require('gitbutler.config')
local h = require('tests.gitbutler.helpers')
local test, assert_eq, assert_truthy = h.test, h.assert_eq, h.assert_truthy

print('\n=== commit_diff (open a commit in a diff tool) tests ===')

test('plan: nil and false fall back to the built-in git show', function()
  assert_eq('builtin', commit_diff.plan(nil, 'abc123').kind)
  assert_eq('builtin', commit_diff.plan(false, 'abc123').kind)
end)

test('plan: tool presets resolve to their command templates', function()
  assert_eq('CodeDiff abc123^ abc123', commit_diff.plan('codediff', 'abc123').cmd)
  assert_eq('DiffviewOpen abc123^!', commit_diff.plan('diffview', 'abc123').cmd)
  assert_eq('Git show abc123', commit_diff.plan('fugitive', 'abc123').cmd)
end)

test('plan: a raw string template is formatted with the sha (twice)', function()
  assert_eq('MyDiff abc^ abc', commit_diff.plan('MyDiff %s^ %s', 'abc').cmd)
  assert_eq('OneShot abc', commit_diff.plan('OneShot %s', 'abc').cmd)
end)

test('plan: a function is wrapped and receives the sha when called', function()
  local got
  local p = commit_diff.plan(function(sha)
    got = sha
  end, 'deadbeef')
  assert_eq('fn', p.kind)
  p.fn()
  assert_eq('deadbeef', got)
end)

test('open: a preset runs the resolved command', function()
  local prev = config.values.commit_diff
  config.values.commit_diff = 'diffview'
  local ran
  local orig = vim.cmd
  vim.cmd = function(c)
    ran = c
  end
  commit_diff.open('cafe')
  vim.cmd = orig
  config.values.commit_diff = prev
  assert_eq('DiffviewOpen cafe^!', ran)
end)

test('open: a function setting is invoked with the sha', function()
  local prev = config.values.commit_diff
  local got
  config.values.commit_diff = function(sha)
    got = sha
  end
  commit_diff.open('abcdef')
  config.values.commit_diff = prev
  assert_eq('abcdef', got)
end)

test('open: an empty sha warns and does nothing', function()
  local prev = config.values.commit_diff
  local ran = false
  config.values.commit_diff = function()
    ran = true
  end
  commit_diff.open('')
  config.values.commit_diff = prev
  assert_truthy(not ran, 'no action on an empty sha')
end)

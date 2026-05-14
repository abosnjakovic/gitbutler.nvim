local actions = require('gitbutler.actions')
local h = require('tests.gitbutler.helpers')
local test, assert_eq, assert_truthy = h.test, h.assert_eq, h.assert_truthy

print('\n=== direct_to_main helper tests ===')

test('ephemeral_branch_name builds the expected pattern', function()
  assert_eq('direct-to-main-1234', actions.ephemeral_branch_name(1234))
end)

test('ephemeral_branch_name accepts the actual os.time() return shape', function()
  local name = actions.ephemeral_branch_name(os.time())
  assert_truthy(name:match('^direct%-to%-main%-%d+$'))
end)

test('format_step_error wraps step + body in the bracketed prefix', function()
  assert_eq('[gitbutler push] remote rejected', actions.format_step_error('push', 'remote rejected'))
end)

test('format_step_error handles empty body', function()
  assert_eq('[gitbutler preflight] ', actions.format_step_error('preflight', ''))
end)

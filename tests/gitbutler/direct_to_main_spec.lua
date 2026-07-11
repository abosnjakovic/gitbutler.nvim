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

-- The CLI moved the commit SHA from a flat {commit_id} to a nested
-- {result={commit_id}} shape; commit_id_of must read both so `M` survives either.
test('commit_id_of reads the nested {result={commit_id}} shape', function()
  assert_eq('abc123', actions.commit_id_of({ result = { commit_id = 'abc123' }, status = {} }))
end)

test('commit_id_of falls back to the flat {commit_id} shape', function()
  assert_eq('def456', actions.commit_id_of({ commit_id = 'def456' }))
end)

test('commit_id_of returns nil on missing/empty/non-table input', function()
  assert_eq(nil, actions.commit_id_of({ result = {} }))
  assert_eq(nil, actions.commit_id_of({ commit_id = '' }))
  assert_eq(nil, actions.commit_id_of('nope'))
end)

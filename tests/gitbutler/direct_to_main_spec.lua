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

-- `but commit --json` on 0.22 returns a flat camelCase {commitId}; the earlier
-- snake_case and nested {result={commit_id}} shapes are not supported, and
-- reading them again would silently resurrect the pre-0.22 surface.
test('commit_id_of reads the flat {commitId} shape', function()
  assert_eq('def456', actions.commit_id_of({ commitId = 'def456', changeId = 'x', branch = 'feat' }))
end)

test('commit_id_of returns nil on the retired snake_case and nested shapes', function()
  assert_eq(nil, actions.commit_id_of({ commit_id = 'abc123' }))
  assert_eq(nil, actions.commit_id_of({ result = { commit_id = 'abc123' }, status = {} }))
end)

test('commit_id_of returns nil on missing/empty/non-table input', function()
  assert_eq(nil, actions.commit_id_of({}))
  assert_eq(nil, actions.commit_id_of({ commitId = '' }))
  assert_eq(nil, actions.commit_id_of('nope'))
end)

-- L on branch/commit rows lands their branches. A commit row resolves to its
-- owning branch, a branch row to itself, and each branch lands only once even
-- when several of its rows are selected.
test('_land_targets resolves branch and commit rows to unique branch names', function()
  local rows = {
    { type = 'branch', data = { name = 'fix/rename', cli_id = 'fi' } },
    { type = 'commit', data = { branch_name = 'chore/hero', cli_id = 'b2' } },
  }
  local names = actions._land_targets(rows)
  assert_eq(2, #names)
  assert_eq('fix/rename', names[1])
  assert_eq('chore/hero', names[2])
end)

test('_land_targets de-dupes when branch and its commit are both selected', function()
  local rows = {
    { type = 'branch', data = { name = 'feat/x', cli_id = 'fx' } },
    { type = 'commit', data = { branch_name = 'feat/x', cli_id = 'c1' } },
  }
  local names = actions._land_targets(rows)
  assert_eq(1, #names)
  assert_eq('feat/x', names[1])
end)

test('_land_targets skips rows without a resolvable branch', function()
  local rows = {
    { type = 'commit', data = {} },
    { type = 'branch', data = { name = 'only-one' } },
  }
  local names = actions._land_targets(rows)
  assert_eq(1, #names)
  assert_eq('only-one', names[1])
end)

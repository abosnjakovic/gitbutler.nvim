local fixtures = require('tests.gitbutler.fixtures')
local gh = require('gitbutler.forge.gh')
local h = require('tests.gitbutler.helpers')
local test, assert_eq, assert_truthy = h.test, h.assert_eq, h.assert_truthy

print('\n=== GitHub forge adapter tests ===')

test('detect matches https github', function()
  assert_truthy(gh.detect('https://github.com/foo/bar.git'))
end)

test('detect matches ssh github', function()
  assert_truthy(gh.detect('git@github.com:foo/bar.git'))
end)

test('detect rejects gitlab', function()
  assert_eq(false, gh.detect('https://gitlab.com/foo/bar.git') and true or false)
end)

test('parse_checks maps three runs', function()
  local checks = gh.parse_checks(fixtures.gh_run_list_json)
  assert_eq(3, #checks)
  assert_eq('12345', checks[1].id)
  assert_eq('build', checks[1].name)
  assert_eq('completed', checks[1].status)
  assert_eq('success', checks[1].conclusion)
  assert_eq('https://github.com/foo/bar/actions/runs/12345', checks[1].url)
end)

test('parse_checks passes through nil conclusion for in_progress', function()
  local checks = gh.parse_checks(fixtures.gh_run_list_json)
  assert_eq('in_progress', checks[3].status)
  -- Note: vim.json.decode may yield vim.NIL rather than nil for JSON null.
  -- Either is acceptable for an in-progress run; check it's "not a real value".
  local c = checks[3].conclusion
  assert_truthy(c == nil or c == vim.NIL)
end)

test('parse_checks on empty array returns empty list', function()
  local checks = gh.parse_checks('[]')
  assert_eq(0, #checks)
end)

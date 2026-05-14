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

test('parse_checks maps three jobs from gh pr checks output', function()
  local checks = gh.parse_checks(fixtures.gh_pr_checks_json)
  assert_eq(3, #checks)
  assert_eq('9001', checks[1].id)
  assert_eq('CI / Format (stylua)', checks[1].name)
  assert_eq('completed', checks[1].status)
  assert_eq('success', checks[1].conclusion)
  assert_eq('https://github.com/foo/bar/actions/runs/12345/job/9001', checks[1].url)
end)

test('parse_checks maps fail bucket to completed+failure', function()
  local checks = gh.parse_checks(fixtures.gh_pr_checks_json)
  assert_eq('completed', checks[2].status)
  assert_eq('failure', checks[2].conclusion)
  assert_eq('CI / Test (ubuntu-latest / nvim nightly)', checks[2].name)
end)

test('parse_checks maps pending bucket to in_progress', function()
  local checks = gh.parse_checks(fixtures.gh_pr_checks_json)
  assert_eq('in_progress', checks[3].status)
  local c = checks[3].conclusion
  assert_truthy(c == nil or c == vim.NIL)
  assert_eq('Release / Deploy', checks[3].name)
end)

test('parse_checks on empty array returns empty list', function()
  local checks = gh.parse_checks('[]')
  assert_eq(0, #checks)
end)

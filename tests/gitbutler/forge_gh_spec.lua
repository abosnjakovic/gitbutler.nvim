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

-- The details pane prints PR and branch links as plain text so Neovim's `gx`
-- opens them; the base comes from the origin remote, in either form git takes.
test('web_url turns ssh and https remotes into the repo page', function()
  assert_eq('https://github.com/foo/bar', gh.web_url('git@github.com:foo/bar.git'))
  assert_eq('https://github.com/foo/bar', gh.web_url('https://github.com/foo/bar.git'))
  assert_eq('https://github.com/foo/bar', gh.web_url('https://github.com/foo/bar'))
  assert_eq('https://github.com/foo/bar', gh.web_url('https://github.com/foo/bar/'))
  assert_eq('https://github.com/foo/bar', gh.web_url('ssh://git@github.com/foo/bar.git'))
end)

test('web_url is nil for other hosts and empty remotes', function()
  assert_eq(nil, gh.web_url('git@gitlab.com:foo/bar.git'))
  assert_eq(nil, gh.web_url(''))
  assert_eq(nil, gh.web_url(nil))
end)

---Stub vim.system for one `gh pr view` run; restores it when the test ends.
---@return string[][] cmds
local function stub_gh_run(result)
  local cmds = {}
  local orig_system, orig_exec = vim.system, vim.fn.executable
  h.after(function()
    vim.system, vim.fn.executable = orig_system, orig_exec
  end)
  vim.fn.executable = function()
    return 1
  end
  vim.system = function(cmd, _, on_exit)
    table.insert(cmds, cmd)
    on_exit(result)
  end
  return cmds
end

test('view_pr asks gh for the title, body and state and decodes them', function()
  local cmds = stub_gh_run({
    code = 0,
    stdout = '{"title":"Keep pace","body":"## Summary\\n\\nText","isDraft":true,"state":"OPEN"}',
  })
  local got
  gh.view_pr(31, function(err, pr)
    got = { err = err, pr = pr }
  end)
  vim.wait(200, function()
    return got ~= nil
  end)
  assert_eq('gh pr view 31 --json title,body,isDraft,state', table.concat(cmds[1], ' '))
  assert_eq(nil, got.err)
  assert_eq('Keep pace', got.pr.title)
  assert_eq('## Summary\n\nText', got.pr.body)
  assert_eq(true, got.pr.draft)
  assert_eq('OPEN', got.pr.state)
end)

test('view_pr reports gh failing', function()
  stub_gh_run({ code = 1, stderr = 'HTTP 401: Bad credentials' })
  local got
  gh.view_pr(31, function(err)
    got = err
  end)
  vim.wait(200, function()
    return got ~= nil
  end)
  assert_eq('HTTP 401: Bad credentials', got)
end)

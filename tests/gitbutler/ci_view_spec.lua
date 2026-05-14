local ci = require('gitbutler.ui.ci')
local h = require('tests.gitbutler.helpers')
local test, assert_eq, assert_truthy = h.test, h.assert_eq, h.assert_truthy

print('\n=== CI view tests ===')

test('build_lines renders header + one line per check', function()
  local checks = {
    { id = '1', name = 'build', status = 'completed', conclusion = 'success', url = 'u1' },
    { id = '2', name = 'test', status = 'completed', conclusion = 'failure', url = 'u2' },
    { id = '3', name = 'deploy', status = 'in_progress', url = 'u3' },
  }
  local lines = ci.build_lines('feat/x', checks)
  -- Expect: 1 header + 1 blank + 3 check lines
  assert_eq(5, #lines)
  assert_eq('section_header', lines[1].type)
  assert_truthy(lines[1].text:find('feat/x', 1, true))
  assert_eq('ci_check', lines[3].type)
  assert_eq('1', lines[3].data.id)
  assert_truthy(lines[3].text:find('build', 1, true))
  assert_truthy(lines[3].text:find('✓', 1, true))
  assert_truthy(lines[4].text:find('✗', 1, true))
  assert_truthy(lines[5].text:find('◐', 1, true))
end)

test('build_lines handles empty check list', function()
  local lines = ci.build_lines('feat/x', {})
  -- Header + blank + 'no checks' info line
  assert_eq(3, #lines)
  assert_truthy(lines[3].text:lower():find('no checks', 1, true))
end)

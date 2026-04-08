local h = require('tests.gitbutler.helpers')
local fixtures = require('tests.gitbutler.fixtures')
local test, assert_eq, assert_truthy = h.test, h.assert_eq, h.assert_truthy

print('\n=== Change type display tests ===')

test('added files get A prefix and add highlight', function()
  local lines = h.capture_lines(fixtures.status_full)
  local added
  for _, l in ipairs(lines) do
    if l.type == 'committed_file' and l.data.change_type == 'added' then
      added = l; break
    end
  end
  assert_truthy(added)
  assert_truthy(added.text:find('^%s*A  '), 'starts with A prefix')
  assert_eq('GitButlerFileAdd', added.hl)
end)

test('modified files get M prefix and mod highlight', function()
  local lines = h.capture_lines(fixtures.status_full)
  local modified
  for _, l in ipairs(lines) do
    if l.type == 'file' and l.data and l.data.change_type == 'modified' then
      modified = l; break
    end
  end
  assert_truthy(modified)
  assert_truthy(modified.text:find('M  '), 'has M prefix')
  assert_eq('GitButlerFileMod', modified.hl)
end)

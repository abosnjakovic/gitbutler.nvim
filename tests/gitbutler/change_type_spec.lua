local fixtures = require('tests.gitbutler.fixtures')
local h = require('tests.gitbutler.helpers')
local test, assert_truthy = h.test, h.assert_truthy

print('\n=== Change type display tests ===')

---True when any span on the line uses the given highlight group.
local function has_span_hl(line, hl)
  for _, s in ipairs(line.spans or {}) do
    if s[3] == hl then
      return true
    end
  end
  return false
end

test('added files get A prefix and add highlight', function()
  local lines = h.capture_lines(fixtures.status_full)
  local added
  for _, l in ipairs(lines) do
    if l.type == 'committed_file' and l.data.change_type == 'added' then
      added = l
      break
    end
  end
  assert_truthy(added)
  assert_truthy(added.text:find(' A ', 1, true), 'has A prefix before path')
  assert_truthy(has_span_hl(added, 'GitButlerFileAdd'), 'add highlight span')
end)

test('modified files get M prefix and mod highlight', function()
  local lines = h.capture_lines(fixtures.status_full)
  local modified
  for _, l in ipairs(lines) do
    if l.type == 'file' and l.data and l.data.change_type == 'modified' then
      modified = l
      break
    end
  end
  assert_truthy(modified)
  assert_truthy(modified.text:find(' M ', 1, true), 'has M prefix before path')
  assert_truthy(has_span_hl(modified, 'GitButlerFileMod'), 'mod highlight span')
end)

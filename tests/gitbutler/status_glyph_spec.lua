local fixtures = require('tests.gitbutler.fixtures')
local h = require('tests.gitbutler.helpers')
local status = require('gitbutler.ui.status')
local test, assert_eq, assert_truthy = h.test, h.assert_eq, h.assert_truthy

print('\n=== Status glyph tests ===')

test('ci_glyph returns blank for nil', function()
  local g, hl = status.ci_glyph(nil)
  assert_eq('', g)
  assert_eq(nil, hl)
end)

test('ci_glyph maps queued', function()
  local g, hl = status.ci_glyph({ status = 'queued' })
  assert_eq('○', g)
  assert_eq('GitButlerCIQueued', hl)
end)

test('ci_glyph maps in_progress', function()
  local g, hl = status.ci_glyph({ status = 'in_progress' })
  assert_eq('◐', g)
  assert_eq('GitButlerCIRunning', hl)
end)

test('ci_glyph maps completed success', function()
  local g, hl = status.ci_glyph({ status = 'completed', conclusion = 'success' })
  assert_eq('✓', g)
  assert_eq('GitButlerCIPass', hl)
end)

test('ci_glyph maps completed failure as fail', function()
  local g, hl = status.ci_glyph({ status = 'completed', conclusion = 'failure' })
  assert_eq('✗', g)
  assert_eq('GitButlerCIFail', hl)
end)

test('ci_glyph maps completed cancelled as fail', function()
  local g, hl = status.ci_glyph({ status = 'completed', conclusion = 'cancelled' })
  assert_eq('✗', g)
  assert_eq('GitButlerCIFail', hl)
end)

test('ci_glyph maps completed timed_out as fail', function()
  local g, hl = status.ci_glyph({ status = 'completed', conclusion = 'timed_out' })
  assert_eq('✗', g)
  assert_eq('GitButlerCIFail', hl)
end)

test('ci_glyph returns ? on unknown', function()
  local g, hl = status.ci_glyph({ status = 'martian' })
  assert_eq('?', g)
  assert_eq('GitButlerCIUnknown', hl)
end)

---Rerender a fixture through the graph pipeline and return the branch row.
local function branch_row_for(data)
  local buf = h.mock_buffer()
  local captured
  ---@diagnostic disable-next-line: duplicate-set-field
  buf.render = function(_, lines)
    captured = lines
  end
  status.instance = buf
  status.data = data
  status.rerender()
  status.instance = nil
  status.data = nil
  assert_truthy(captured, 'rerender produced rows')
  for _, l in ipairs(captured) do
    if l.type == 'branch' then
      return l
    end
  end
end

test('branch row text carries CI glyph and review id suffix', function()
  local data = vim.deepcopy(fixtures.status_full)
  data.stacks[1].branches[1].ci = { status = 'completed', conclusion = 'success' }
  data.stacks[1].branches[1].reviewId = 42
  local br = branch_row_for(data)
  assert_truthy(br)
  assert_eq('┊╭┄br [feature-auth] ✓ #42', br.text)
end)

test('branch row text carries stack aggregate CI glyph from cache', function()
  status._ci_cache['feature-auth'] = { state = 'fail', sha = 'c4d75dfd95bf28d3ce1b6dc1a99bb96338aae8fa' }
  -- pcall so the cache entry is cleaned up even if branch_row_for throws.
  local ok, br = pcall(branch_row_for, vim.deepcopy(fixtures.status_full))
  status._ci_cache['feature-auth'] = nil
  if not ok then
    error(br, 0)
  end
  assert_truthy(br)
  assert_eq('┊╭┄br [feature-auth]  ✗', br.text)
  local fail_span = false
  for _, s in ipairs(br.spans or {}) do
    if s[3] == 'GitButlerCIFail' then
      fail_span = true
    end
  end
  assert_truthy(fail_span, 'aggregate glyph keeps its highlight')
end)

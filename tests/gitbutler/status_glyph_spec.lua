local h = require('tests.gitbutler.helpers')
local status = require('gitbutler.ui.status')
local test, assert_eq = h.test, h.assert_eq

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

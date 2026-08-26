local h = require('tests.gitbutler.helpers')
local spinner = require('gitbutler.ui.spinner')

print('\n=== Spinner tests ===')

local function float_lines()
  if not spinner.buf or not vim.api.nvim_buf_is_valid(spinner.buf) then
    return {}
  end
  return vim.api.nvim_buf_get_lines(spinner.buf, 0, -1, false)
end

-- The bug this replaced: every start opened its own float at the same fixed
-- bottom-right position, so two concurrent operations (two lands, or a land
-- plus a CI fetch) drew on top of each other and the older label was clipped.
h.test('spinner: concurrent operations share one float, one line each', function()
  local a = spinner.start('landing alpha (1/2)')
  local b = spinner.start('fetching CI for beta')

  h.assert_eq(2, #spinner.active, 'both operations are tracked')
  h.assert_truthy(spinner.win and vim.api.nvim_win_is_valid(spinner.win), 'one shared window is open')
  h.assert_eq(2, vim.api.nvim_win_get_height(spinner.win), 'the window is as tall as the operation count')

  local lines = float_lines()
  h.assert_eq(2, #lines, 'each operation gets its own line')
  h.assert_truthy(lines[1]:find('landing alpha (1/2)', 1, true), 'first label is intact, not overdrawn')
  h.assert_truthy(lines[2]:find('fetching CI for beta', 1, true), 'second label is intact')

  a:stop()
  b:stop()
end)

-- Stopping one of two must reflow rather than leave a hole or tear the window down.
h.test('spinner: stopping one operation leaves the other visible', function()
  local a = spinner.start('landing alpha')
  local b = spinner.start('landing beta')

  a:stop()

  h.assert_eq(1, #spinner.active)
  h.assert_eq(1, vim.api.nvim_win_get_height(spinner.win), 'the window shrank to the remaining operation')
  h.assert_truthy(float_lines()[1]:find('landing beta', 1, true), 'the survivor is the one still running')

  b:stop()
  h.assert_eq(0, #spinner.active)
  h.assert_falsy(spinner.win, 'the last stop closes the window')
end)

-- Multi-step pipelines relabel in place (`sp:update('landing onto target')`).
h.test('spinner: update relabels its own line only', function()
  local a = spinner.start('committing 3 file(s)')
  local b = spinner.start('creating PR for feat/x')

  a:update('landing onto target')

  local lines = float_lines()
  h.assert_truthy(lines[1]:find('landing onto target', 1, true), 'the updated line changed')
  h.assert_truthy(lines[2]:find('creating PR for feat/x', 1, true), 'the sibling line did not')

  a:stop()
  b:stop()
end)

-- The land chain stops on the error path and again from a chained callback.
h.test('spinner: a double stop is a no-op', function()
  local notifies = 0
  local orig = vim.notify
  h.after(function()
    vim.notify = orig
  end)
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.notify = function()
    notifies = notifies + 1
  end

  local a = spinner.start('landing alpha')
  a:stop('done')
  a:stop('done')

  h.assert_eq(1, notifies, 'the second stop must not re-notify')
  h.assert_eq(0, #spinner.active)
end)

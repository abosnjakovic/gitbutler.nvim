local editor = require('gitbutler.ui.editor')
local fixtures = require('tests.gitbutler.fixtures')
local h = require('tests.gitbutler.helpers')
local test, assert_eq, assert_truthy = h.test, h.assert_eq, h.assert_truthy

print('\n=== editor (jump-to-code) tests ===')

test('first_hunk_line: returns the first hunk newStart', function()
  assert_eq(1, editor.first_hunk_line(fixtures.diff_json))
end)

test('first_hunk_line: skips a leading change that has no hunks', function()
  local data = {
    changes = {
      { path = 'a', diff = { type = 'binary' } },
      { path = 'b', diff = { type = 'patch', hunks = { { newStart = 42 } } } },
    },
  }
  assert_eq(42, editor.first_hunk_line(data))
end)

test('first_hunk_line: nil for empty, binary, or malformed payloads', function()
  assert_eq(nil, editor.first_hunk_line(fixtures.diff_json_empty))
  assert_eq(nil, editor.first_hunk_line(fixtures.diff_json_binary))
  assert_eq(nil, editor.first_hunk_line(nil))
  assert_eq(nil, editor.first_hunk_line({ changes = 'nope' }))
end)

test('open: reuses one editor window across repeated jumps', function()
  editor.win = nil
  local starting = #vim.api.nvim_tabpage_list_wins(0)

  editor.open('README.md', 3)
  local win1 = editor.win
  assert_truthy(win1 and vim.api.nvim_win_is_valid(win1), 'first open created a window')
  assert_eq(3, vim.api.nvim_win_get_cursor(win1)[1])

  editor.open('Makefile', 2)
  assert_eq(win1, editor.win, 'second open reused the same window')
  assert_eq(starting + 1, #vim.api.nvim_tabpage_list_wins(0), 'no extra split stacked')
  assert_eq(2, vim.api.nvim_win_get_cursor(editor.win)[1])

  vim.api.nvim_win_close(editor.win, true)
  editor.win = nil
end)

test('open: clamps the target line to the file length', function()
  editor.win = nil
  editor.open('version.txt', 99999)
  local count = vim.api.nvim_buf_line_count(0)
  assert_eq(count, vim.api.nvim_win_get_cursor(editor.win)[1])
  vim.api.nvim_win_close(editor.win, true)
  editor.win = nil
end)

test('open: no-op on an empty path (creates no window)', function()
  editor.win = nil
  local before = #vim.api.nvim_tabpage_list_wins(0)
  editor.open('')
  editor.open(nil)
  assert_eq(before, #vim.api.nvim_tabpage_list_wins(0))
  assert_eq(nil, editor.win)
end)

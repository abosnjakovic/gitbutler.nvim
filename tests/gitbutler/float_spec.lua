local float = require('gitbutler.ui.float')
local h = require('tests.gitbutler.helpers')

print('\n=== Float tests ===')

---Fire the float's submit mapping the way the user's `<C-c><C-c>` would.
---Neovim normalises the reported `lhs` case, so match case-insensitively.
local function submit(buf)
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
    if map.lhs and map.lhs:lower() == '<c-c><c-c>' and map.callback then
      map.callback()
      return true
    end
  end
  return false
end

-- Callers that treat empty as "no input" (a commit message, a branch name) must
-- keep discarding it. Only a caller that asks for it sees the empty string.
h.test('float: an empty submit is discarded by default', function()
  local called = false
  local buf = float.input({
    title = 'Test',
    on_submit = function()
      called = true
    end,
  })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '' })
  h.assert_truthy(submit(buf), 'the submit mapping exists')
  h.assert_falsy(called, 'on_submit did not fire for empty text')
end)

-- Clearing a comment popup is how a comment gets deleted, so the empty string
-- has to reach the caller as a real value.
h.test('float: allow_empty passes the empty string through', function()
  local seen
  local buf = float.input({
    title = 'Test',
    allow_empty = true,
    on_submit = function(text)
      seen = text
    end,
  })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '' })
  h.assert_truthy(submit(buf), 'the submit mapping exists')
  h.assert_eq('', seen)
end)

h.test('float: allow_empty does not change a non-empty submit', function()
  local seen
  local buf = float.input({
    title = 'Test',
    allow_empty = true,
    on_submit = function(text)
      seen = text
    end,
  })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'a comment' })
  submit(buf)
  h.assert_eq('a comment', seen)
end)

---Fire a buffer-local normal-mode mapping by lhs, as the user pressing it would.
local function press(buf, lhs)
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
    if map.lhs and map.lhs:lower() == lhs:lower() and map.callback then
      map.callback()
      return true
    end
  end
  return false
end

-- <C-c><C-c> is an awkward reach. Normal-mode <CR> is free in a float this
-- small, so it saves everywhere — including multi-line, where insert-mode <CR>
-- still has to mean newline.
h.test('float: <CR> in normal mode saves a multi-line float', function()
  local seen
  local buf = float.input({
    title = 'Test',
    on_submit = function(text)
      seen = text
    end,
  })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'first line', 'second line' })
  h.assert_truthy(press(buf, '<CR>'), 'the mapping exists in normal mode')
  h.assert_eq('first line\nsecond line', seen)
end)

h.test('float: <CR> in normal mode saves a single-line float too', function()
  local seen
  local buf = float.input({
    title = 'Test',
    single_line = true,
    on_submit = function(text)
      seen = text
    end,
  })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'a branch name' })
  h.assert_truthy(press(buf, '<CR>'), 'the mapping exists in normal mode')
  h.assert_eq('a branch name', seen)
end)

-- The float opens in insert mode, so Esc is the way to reach normal mode and
-- press <CR>. Vim users double-tap Esc reflexively; if the second tap aborted,
-- it would discard the text they were about to save.
h.test('float: <Esc> does not abort, so a double-tap cannot discard the text', function()
  local aborted = false
  local buf = float.input({
    title = 'Test',
    on_submit = function() end,
    on_abort = function()
      aborted = true
    end,
  })
  h.assert_falsy(press(buf, '<Esc>'), '<Esc> is not mapped in normal mode')
  h.assert_falsy(aborted, 'nothing aborted')
  -- q still cancels.
  h.assert_truthy(press(buf, 'q'), 'q is mapped')
  h.assert_truthy(aborted, 'q aborts')
end)

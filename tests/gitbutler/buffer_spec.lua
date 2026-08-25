local buffer_mod = require('gitbutler.ui.buffer')
local h = require('tests.gitbutler.helpers')

print('\n=== Buffer tests ===')

-- The details pane needs everything `open` does EXCEPT the window, which it
-- makes itself (a vsplit beside the status view, with its own width and a
-- fullscreen toggle). Splitting the two lets it reuse the rest.
h.test('buffer: attach adopts a window the caller already made', function()
  local buf = buffer_mod.Buffer.new()
  buf.view = 'status'
  buf.buf = vim.api.nvim_create_buf(false, true)
  vim.cmd('vsplit')
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf.buf)
  h.after(function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    buf:close()
  end)

  buf:attach(win)

  h.assert_eq(win, buf.win, 'attach records the window it was given')
  h.assert_truthy(buf.hint_buf and vim.api.nvim_buf_is_valid(buf.hint_buf), 'the hint buffer exists')
  h.assert_truthy(buf.hint_win and vim.api.nvim_win_is_valid(buf.hint_win), 'the hint window exists')
  h.assert_falsy(vim.wo[win].wrap, 'window options were applied')
  h.assert_truthy(vim.wo[win].cursorline, 'window options were applied')
end)

-- `open` must keep behaving exactly as it did; every existing view calls it.
h.test('buffer: open still creates its own window and attaches', function()
  local config = require('gitbutler.config')
  local original = config.values.kind
  h.after(function()
    config.values.kind = original
  end)
  config.values.kind = 'vsplit'

  local buf = buffer_mod.Buffer.new()
  buf.view = 'status'
  h.after(function()
    buf:close()
  end)

  buf:open()

  h.assert_truthy(buf.win and vim.api.nvim_win_is_valid(buf.win), 'open made a window')
  h.assert_truthy(buf.hint_win and vim.api.nvim_win_is_valid(buf.hint_win), 'open attached the hint window')
end)

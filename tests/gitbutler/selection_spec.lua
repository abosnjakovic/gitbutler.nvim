local h = require('tests.gitbutler.helpers')
local buffer_mod = require('gitbutler.ui.buffer')
local test, assert_eq, assert_truthy, assert_falsy = h.test, h.assert_eq, h.assert_truthy, h.assert_falsy

print('\n=== Selection tests ===')

test('select_key returns cli_id for file lines', function()
  local buf = h.mock_buffer()
  local line = { type = 'file', data = { cli_id = 'up', path = 'foo.lua' } }
  assert_eq('up', buf:select_key(line))
end)

test('select_key returns sha for commit lines', function()
  local buf = h.mock_buffer()
  local line = { type = 'commit', data = { sha = 'abc123' } }
  assert_eq('abc123', buf:select_key(line))
end)

test('select_key returns cli_id for committed_file lines', function()
  local buf = h.mock_buffer()
  local line = { type = 'committed_file', data = { cli_id = 'c4:xw' } }
  assert_eq('c4:xw', buf:select_key(line))
end)

test('select_key returns nil for non-selectable lines', function()
  local buf = h.mock_buffer()
  assert_eq(nil, buf:select_key({ type = 'blank', data = nil }))
  assert_eq(nil, buf:select_key({ type = 'section_header', data = {} }))
  assert_eq(nil, buf:select_key({ type = 'branch', data = { name = 'main' } }))
  assert_eq(nil, buf:select_key({ type = 'help', data = nil }))
  assert_eq(nil, buf:select_key({ type = 'recent_commit', data = { sha = 'abc' } }))
end)

test('toggle_select adds and removes from selection', function()
  local buf = h.mock_buffer()
  buf.lines = {
    { type = 'file', data = { cli_id = 'up', path = 'foo.lua' }, text = 'M  foo.lua' },
    { type = 'file', data = { cli_id = 'qu', path = 'bar.lua' }, text = 'M  bar.lua' },
  }
  buf.win = true
  buf._cursor_row = 1

  buf:toggle_select()
  assert_truthy(buf:is_selected(buf.lines[1]))
  assert_falsy(buf:is_selected(buf.lines[2]))

  buf:toggle_select()
  assert_falsy(buf:is_selected(buf.lines[1]))
end)

test('get_selected_lines returns selected lines in order', function()
  local buf = h.mock_buffer()
  buf.lines = {
    { type = 'file', data = { cli_id = 'a1' }, text = 'first' },
    { type = 'file', data = { cli_id = 'b2' }, text = 'second' },
    { type = 'file', data = { cli_id = 'c3' }, text = 'third' },
  }
  buf.selected = { a1 = true, c3 = true }

  local selected = buf:get_selected_lines()
  assert_eq(2, #selected)
  assert_eq('a1', selected[1].data.cli_id)
  assert_eq('c3', selected[2].data.cli_id)
end)

test('get_selected_lines can filter by type', function()
  local buf = h.mock_buffer()
  buf.lines = {
    { type = 'file', data = { cli_id = 'a1' }, text = 'file' },
    { type = 'commit', data = { sha = 'abc' }, text = 'commit' },
  }
  buf.selected = { a1 = true, abc = true }

  local files = buf:get_selected_lines({ 'file' })
  assert_eq(1, #files)
  assert_eq('file', files[1].type)

  local commits = buf:get_selected_lines({ 'commit' })
  assert_eq(1, #commits)
  assert_eq('commit', commits[1].type)
end)

test('clear_selection empties the set', function()
  local buf = h.mock_buffer()
  buf.selected = { a1 = true, b2 = true }
  buf:clear_selection()
  assert_eq(0, vim.tbl_count(buf.selected))
end)

test('toggle_select on non-selectable line is a no-op', function()
  local buf = h.mock_buffer()
  buf.lines = {
    { type = 'blank', data = nil, text = '' },
  }
  buf.win = true
  buf._cursor_row = 1
  buf:toggle_select()
  assert_eq(0, vim.tbl_count(buf.selected))
end)

test('render adds selection marker to selected lines', function()
  local buf = buffer_mod.Buffer.new()
  buf.buf = vim.api.nvim_create_buf(false, true)
  buf.ns = vim.api.nvim_create_namespace('gitbutler-test-render')
  buf.selected = { up = true }

  buf:render({
    { type = 'file', data = { cli_id = 'up' }, text = 'M  foo.lua', indent = 1 },
    { type = 'file', data = { cli_id = 'qu' }, text = 'M  bar.lua', indent = 1 },
  })

  local rendered = vim.api.nvim_buf_get_lines(buf.buf, 0, -1, false)
  assert_truthy(rendered[1]:find('●'), 'selected line has marker')
  assert_falsy(rendered[2]:find('●'), 'unselected line has no marker')

  vim.api.nvim_buf_delete(buf.buf, { force = true })
end)

test('render applies GitButlerSelected highlight to selected lines', function()
  local buf = buffer_mod.Buffer.new()
  buf.buf = vim.api.nvim_create_buf(false, true)
  buf.ns = vim.api.nvim_create_namespace('gitbutler-test-hl')
  buf.selected = { up = true }

  require('gitbutler.ui.highlights').setup()

  buf:render({
    { type = 'file', data = { cli_id = 'up' }, hl = 'GitButlerFileMod', text = 'M  foo.lua', indent = 1 },
  })

  local extmarks = vim.api.nvim_buf_get_extmarks(buf.buf, buf.ns, 0, -1, { details = true })
  local found_selected_hl = false
  for _, mark in ipairs(extmarks) do
    if mark[4] and mark[4].hl_group == 'GitButlerSelected' then
      found_selected_hl = true
      break
    end
  end
  assert_truthy(found_selected_hl, 'selected line has GitButlerSelected highlight')

  vim.api.nvim_buf_delete(buf.buf, { force = true })
end)

test('get_selected_lines falls back to cursor line when no selection', function()
  local buf = h.mock_buffer()
  buf.lines = {
    { type = 'file', data = { cli_id = 'a1', path = 'foo.lua' }, text = 'M  foo.lua' },
    { type = 'file', data = { cli_id = 'b2', path = 'bar.lua' }, text = 'M  bar.lua' },
  }
  buf._cursor_row = 2

  local selected = buf:get_selected_lines()
  assert_eq(0, #selected)

  -- The action pattern: fall back to cursor line
  local targets = #selected > 0 and selected or { buf.lines[buf._cursor_row] }
  assert_eq(1, #targets)
  assert_eq('b2', targets[1].data.cli_id)
end)

test('selection survives re-render', function()
  local buf = buffer_mod.Buffer.new()
  buf.buf = vim.api.nvim_create_buf(false, true)
  buf.ns = vim.api.nvim_create_namespace('gitbutler-test-persist')
  buf.selected = { up = true }

  local lines = {
    { type = 'file', data = { cli_id = 'up' }, text = 'M  foo.lua', indent = 1 },
    { type = 'file', data = { cli_id = 'qu' }, text = 'M  bar.lua', indent = 1 },
  }

  buf:render(lines)
  assert_truthy(buf:is_selected(lines[1]))

  buf:render(lines)
  assert_truthy(buf:is_selected(lines[1]), 'selection preserved after re-render')

  local rendered = vim.api.nvim_buf_get_lines(buf.buf, 0, -1, false)
  assert_truthy(rendered[1]:find('●'), 'marker still shown after re-render')

  vim.api.nvim_buf_delete(buf.buf, { force = true })
end)

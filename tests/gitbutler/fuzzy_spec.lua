local float = require('gitbutler.ui.float')
local h = require('tests.gitbutler.helpers')

h.test('fuzzy: empty query passes items through unchanged', function()
  local items = { 'feature-auth', 'main', 'old-experiment' }
  local out = float._fuzzy_filter(items, '')
  h.assert_eq(3, #out)
  h.assert_eq('feature-auth', out[1])
  h.assert_eq('main', out[2])
  h.assert_eq('old-experiment', out[3])
end)

h.test('fuzzy: subsequence query matches', function()
  local out = float._fuzzy_filter({ 'feature-auth', 'main', 'old-experiment' }, 'fa')
  h.assert_eq(1, #out)
  h.assert_eq('feature-auth', out[1])
end)

h.test('fuzzy: no match returns empty list', function()
  local out = float._fuzzy_filter({ 'feature-auth', 'main' }, 'zzz')
  h.assert_eq(0, #out)
end)

h.test('fuzzy picker filters on refilter, selects, and closes both windows', function()
  local picked
  local p = float.fuzzy_picker({
    title = 'Test',
    items = { 'feature-auth', 'main', 'old-experiment' },
    on_select = function(item)
      picked = item
    end,
  })
  vim.api.nvim_buf_set_lines(p.prompt_buf, 0, -1, false, { 'fa' })
  p.refilter()
  local lines = vim.api.nvim_buf_get_lines(p.list_buf, 0, -1, false)
  h.assert_eq(1, #lines)
  h.assert_eq('  feature-auth', lines[1])
  p.confirm()
  h.assert_eq('feature-auth', picked)
  h.assert_falsy(vim.api.nvim_win_is_valid(p.prompt_win), 'prompt window closed')
  h.assert_falsy(vim.api.nvim_win_is_valid(p.list_win), 'list window closed')
end)

h.test('fuzzy picker moves the selection with wrap-around', function()
  local picked
  local p = float.fuzzy_picker({
    title = 'Test',
    items = { 'aaa', 'bbb', 'ccc' },
    on_select = function(item)
      picked = item
    end,
  })
  p.move(1)
  p.move(1)
  p.move(1) -- wraps back to the first item
  p.move(1)
  p.confirm()
  h.assert_eq('bbb', picked)
end)

h.test('fuzzy picker confirm no-ops on an empty filtered list; abort closes', function()
  local picked, aborted
  local p = float.fuzzy_picker({
    title = 'Test',
    items = { 'aaa' },
    on_select = function(item)
      picked = item
    end,
    on_abort = function()
      aborted = true
    end,
  })
  vim.api.nvim_buf_set_lines(p.prompt_buf, 0, -1, false, { 'zzz' })
  p.refilter()
  p.confirm()
  h.assert_falsy(picked, 'confirm with no match selects nothing')
  h.assert_truthy(vim.api.nvim_win_is_valid(p.prompt_win), 'windows stay open after empty confirm')
  p.abort()
  h.assert_truthy(aborted, 'on_abort called')
  h.assert_falsy(vim.api.nvim_win_is_valid(p.prompt_win))
  h.assert_falsy(vim.api.nvim_win_is_valid(p.list_win))
end)

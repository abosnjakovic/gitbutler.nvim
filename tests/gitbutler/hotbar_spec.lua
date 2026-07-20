local h = require('tests.gitbutler.helpers')
local hotbar = require('gitbutler.ui.hotbar')

h.test('hotbar: pill first, separator-joined items', function()
  local built = hotbar.build('normal', {
    { 'j', 'down' },
    { 'k', 'up' },
    { '?', 'help', keep = true },
    { 'q', 'quit', keep = true },
  }, 200)
  h.assert_eq(' normal  j down • k up • ? help • q quit', built.text)
  h.assert_eq('GitButlerModeNormal', built.spans[1][3])
end)

h.test('hotbar: narrow width drops middle items, keeps help and quit', function()
  local built = hotbar.build('normal', {
    { 'j', 'down' },
    { 'k', 'up' },
    { 'x', 'discard' },
    { '?', 'help', keep = true },
    { 'q', 'quit', keep = true },
  }, 30)
  h.assert_truthy(built.text:find('%? help'), 'help must survive truncation')
  h.assert_truthy(built.text:find('q quit'), 'quit must survive truncation')
  h.assert_falsy(built.text:find('x discard'), 'middle items drop first')
end)

h.test('hotbar: normal_items exist and end with help/quit', function()
  local items = hotbar.normal_items
  h.assert_truthy(#items > 5)
  h.assert_eq('?', items[#items - 1][1])
  h.assert_eq('q', items[#items][1])
end)

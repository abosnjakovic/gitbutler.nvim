local actions = require('gitbutler.actions')
local h = require('tests.gitbutler.helpers')

local lines = {
  { selectable = true, type = 'uncommitted_header' }, -- 1
  { selectable = true, type = 'file' }, -- 2
  { selectable = false, type = 'blank' }, -- 3
  { selectable = true, type = 'branch' }, -- 4
  { selectable = true, type = 'commit' }, -- 5
  { selectable = false, type = 'connector' }, -- 6
  { selectable = true, type = 'merge_base' }, -- 7
}

h.test('nav: skips non-selectable rows', function()
  h.assert_eq(4, actions._next_selectable(lines, 2, 1, 1))
  h.assert_eq(2, actions._next_selectable(lines, 4, -1, 1))
end)

h.test('nav: clamps at edges', function()
  h.assert_eq(7, actions._next_selectable(lines, 7, 1, 1))
  h.assert_eq(1, actions._next_selectable(lines, 1, -1, 1))
end)

h.test('nav: count moves N selectable rows', function()
  h.assert_eq(7, actions._next_selectable(lines, 1, 1, 10))
end)

h.test('nav: section jump targets branch and uncommitted headers', function()
  h.assert_eq(4, actions._next_section(lines, 1, 1))
  h.assert_eq(1, actions._next_section(lines, 4, -1))
  h.assert_eq(4, actions._next_section(lines, 7, -1))
end)

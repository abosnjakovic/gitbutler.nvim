local h = require('tests.gitbutler.helpers')
local test, assert_eq = h.test, h.assert_eq

print('\n=== Cursor restore tests ===')

test('_cursor_key returns the stable identity of the row under the cursor', function()
  local buf = h.mock_buffer()
  buf.lines = {
    { type = 'commit', data = { sha = 'aaa' } },
    { type = 'file', data = { cli_id = 'up' } },
  }
  buf._cursor_row = 2
  assert_eq('up', buf:_cursor_key())
end)

test('_cursor_key returns nil on a row with no stable identity', function()
  local buf = h.mock_buffer()
  buf.lines = { { type = 'blank' } }
  buf._cursor_row = 1
  assert_eq(nil, buf:_cursor_key())
end)

test('_seek_key follows a commit that shifted down when a newer one landed', function()
  local buf = h.mock_buffer()
  buf.lines = {
    { type = 'commit', data = { sha = 'ccc' } },
    { type = 'commit', data = { sha = 'aaa' } },
    { type = 'commit', data = { sha = 'bbb' } },
  }
  local moved
  ---@diagnostic disable-next-line: duplicate-set-field
  buf._move_cursor = function(_, row)
    moved = row
  end
  buf:_seek_key('bbb')
  assert_eq(3, moved, 'bbb was row 2 before the new commit, row 3 after')
end)

test('_seek_key leaves the cursor alone when the row is gone', function()
  local buf = h.mock_buffer()
  buf.lines = { { type = 'commit', data = { sha = 'ccc' } } }
  local moved
  ---@diagnostic disable-next-line: duplicate-set-field
  buf._move_cursor = function(_, row)
    moved = row
  end
  -- A squash can delete the commit the cursor was on; that must not jump or throw.
  buf:_seek_key('bbb')
  assert_eq(nil, moved)
end)

test('_seek_key is a no-op when the previous row had no identity', function()
  local buf = h.mock_buffer()
  buf.lines = { { type = 'commit', data = { sha = 'ccc' } } }
  local moved
  ---@diagnostic disable-next-line: duplicate-set-field
  buf._move_cursor = function(_, row)
    moved = row
  end
  buf:_seek_key(nil)
  assert_eq(nil, moved)
end)

test('render captures the identity before replacing lines and seeks it after', function()
  local buf = h.mock_buffer()
  buf.lines = {
    { type = 'commit', data = { sha = 'aaa' }, text = 'aaa' },
    { type = 'commit', data = { sha = 'bbb' }, text = 'bbb' },
  }
  buf._cursor_row = 2
  local sought
  ---@diagnostic disable-next-line: duplicate-set-field
  buf._seek_key = function(_, key)
    sought = key
  end

  buf:render({
    { type = 'commit', data = { sha = 'ccc' }, text = 'ccc' },
    { type = 'commit', data = { sha = 'aaa' }, text = 'aaa' },
    { type = 'commit', data = { sha = 'bbb' }, text = 'bbb' },
  })
  -- The key must come from the OLD lines; reading after assignment would
  -- return 'aaa', the row that merely inherited the number.
  assert_eq('bbb', sought)
end)

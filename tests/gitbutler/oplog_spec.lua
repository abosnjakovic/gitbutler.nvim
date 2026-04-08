local h = require('tests.gitbutler.helpers')
local fixtures = require('tests.gitbutler.fixtures')
local test, assert_eq, assert_truthy, assert_falsy, assert_type = h.test, h.assert_eq, h.assert_truthy, h.assert_falsy, h.assert_type

print('\n=== Oplog tests ===')

test('oplog fixture has correct structure', function()
  local data = fixtures.oplog
  assert_eq(2, #data)
  assert_eq('06cdde9f3a78f01ddbda140d9e7d4660d3a4fbe9', data[1].id)
  assert_eq('CreateCommit', data[1].details.title)
  assert_type('number', data[1].createdAt)
end)

test('oplog entry with nil body does not crash', function()
  local entry = fixtures.oplog[1]
  assert_falsy(type(entry.details.body) == 'string')
end)

test('oplog entry with string body is preserved', function()
  local entry = fixtures.oplog[2]
  assert_type('string', entry.details.body)
  assert_truthy(entry.details.body:find('moved'))
end)

test('oplog empty list', function()
  assert_eq(0, #fixtures.oplog_empty)
end)

test('oplog timestamp formatting', function()
  local ts = fixtures.oplog[1].createdAt
  assert_type('number', ts)
  local formatted = os.date('%Y-%m-%d %H:%M', ts)
  assert_truthy(formatted:find('%d%d%d%d%-%d%d%-%d%d'), 'has date format')
end)

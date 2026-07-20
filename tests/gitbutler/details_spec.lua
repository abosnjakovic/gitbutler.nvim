local details = require('gitbutler.ui.details')
local fixtures = require('tests.gitbutler.fixtures')
local h = require('tests.gitbutler.helpers')

h.test('details: file header row per path, closing row after hunks', function()
  local rows = details.build(fixtures.diff_json, {})
  h.assert_eq('detail_file', rows[1].type)
  -- `─+` cannot express "one or more ─" in a byte-wise Lua pattern, so the
  -- padding run is matched with `.*` instead. Intent is unchanged.
  h.assert_truthy(rows[1].text:match('^── src/auth%.lua modified ─.*╮$'), rows[1].text)
  -- ...and a closing row follows this file's hunks, before the next file header.
  local closer
  for i, r in ipairs(rows) do
    if r.type == 'detail_file' and i > 1 then
      closer = r
      break
    end
  end
  h.assert_truthy(closer.text:match('╯$'), closer.text)
end)

h.test('details: hunk headers are selectable and carry hunk cli ids', function()
  local rows, hunks = details.build(fixtures.diff_json, {})
  h.assert_eq(3, #hunks)
  local first
  for _, r in ipairs(rows) do
    if r.type == 'detail_hunk' then
      first = r
      break
    end
  end
  h.assert_truthy(first.selectable)
  h.assert_eq(hunks[1].id, first.data.cli_id)
  h.assert_truthy(first.text:match('@@'))
end)

h.test('details: gutter advances old and new counters correctly', function()
  local rows = details.build(fixtures.diff_json, {})
  local body = {}
  for _, r in ipairs(rows) do
    if r.type == 'detail_line' then
      table.insert(body, r.text)
    end
  end
  -- context line: both counters; add: new only; delete: old only
  h.assert_truthy(body[1]:match('^%s+1%s+1 │ '), body[1])
  h.assert_truthy(body[2]:match('^%s+2 │ %+'), body[2])
  -- delete: old advances past the mixed hunk's context line, new column blank
  local deleted
  for _, text in ipairs(body) do
    if text:match('│ %-') then
      deleted = text
      break
    end
  end
  h.assert_truthy(deleted and deleted:match('^%s+21%s+│ %-'), tostring(deleted))
end)

h.test('details: vim.NIL path, status and hunk diff do not crash the build', function()
  local rows = details.build({
    changes = {
      {
        id = 'nn:1',
        path = vim.NIL,
        status = vim.NIL,
        diff = { type = 'patch', hunks = { { oldStart = 1, newStart = 1, diff = vim.NIL } } },
      },
    },
  }, {})
  h.assert_truthy(rows[1].text:match('unknown'), rows[1].text)
  for _, r in ipairs(rows) do
    h.assert_falsy(r.text:match('NIL'), r.text)
  end
end)

h.test('details: selected hunk rows carry the ▌ bar', function()
  local rows = details.build(fixtures.diff_json, { selected_hunk = 1 })
  local marked = 0
  for _, r in ipairs(rows) do
    if r.text:match('^▌') then
      marked = marked + 1
    end
  end
  h.assert_truthy(marked > 0, 'no rows carried the selection bar')
end)

h.test('details: marked hunk header shows ✔︎', function()
  local _, hunks = details.build(fixtures.diff_json, {})
  local rows = details.build(fixtures.diff_json, { marked = { [hunks[1].id] = true } })
  local found = false
  for _, r in ipairs(rows) do
    if r.type == 'detail_hunk' and r.text:match('✔︎') then
      found = true
    end
  end
  h.assert_truthy(found)
end)

h.test('details: binary diff renders a placeholder, registers no hunk', function()
  local rows, hunks = details.build(fixtures.diff_json_binary, {})
  h.assert_eq(0, #hunks)
  local info = false
  for _, r in ipairs(rows) do
    if r.type == 'detail_info' then
      info = true
    end
  end
  h.assert_truthy(info)
end)

h.test('details: empty changes renders a no-changes row', function()
  local rows, hunks = details.build(fixtures.diff_json_empty, {})
  h.assert_eq(0, #hunks)
  h.assert_truthy(rows[1].text:match('no changes'))
end)

h.test('details: spans stay within line byte length', function()
  local rows = details.build(fixtures.diff_json, { selected_hunk = 2 })
  for _, r in ipairs(rows) do
    for _, s in ipairs(r.spans or {}) do
      h.assert_truthy(s[1] >= 0 and s[2] <= #r.text and s[1] < s[2], 'bad span: ' .. r.text)
    end
  end
end)

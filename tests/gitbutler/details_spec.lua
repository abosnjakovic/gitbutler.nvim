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

--- Window controller -------------------------------------------------------

local cli = require('gitbutler.cli')

---Use the controller's own reset so the spec can never drift from it.
local function reset()
  details._reset_state()
end

---A status-view stand-in owning a real window, as modes_spec/fuzzy_spec do.
local function mock_status_buf()
  local sb = require('gitbutler.ui.buffer').Buffer.new()
  sb.view = 'status'
  sb.buf = vim.api.nvim_create_buf(false, true)
  sb.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(sb.win, sb.buf)
  return sb
end

h.test('cli.diff_json builds but diff <id> --json, omitting a nil id', function()
  local captured
  local orig_run = cli.run
  cli.run = function(args, cb)
    captured = args
    cb(nil, {})
  end
  cli.diff_json('rl:8', function() end)
  h.assert_eq('diff', captured[1])
  h.assert_eq('rl:8', captured[2])
  h.assert_eq('--json', captured[3])
  cli.diff_json(nil, function() end)
  h.assert_eq('diff', captured[1])
  h.assert_eq('--json', captured[2])
  cli.run = orig_run
end)

h.test('details: resize clamps width_pct to 30..90', function()
  reset()
  details.win_state.width_pct = 50 -- width survives reset by design
  details.resize(-50)
  h.assert_eq(30, details.win_state.width_pct)
  details.resize(100)
  h.assert_eq(90, details.win_state.width_pct)
  details.resize(-5)
  h.assert_eq(85, details.win_state.width_pct)
end)

h.test('details: show no-ops when the entity is unchanged', function()
  reset()
  local calls = 0
  local orig = cli.diff_json
  cli.diff_json = function(_, cb)
    calls = calls + 1
    cb(nil, fixtures.diff_json)
  end
  details.show({ cli_id = 'aa', kind = 'file' })
  details.show({ cli_id = 'aa', kind = 'file' })
  cli.diff_json = orig
  h.assert_eq(1, calls)
  h.assert_eq('aa', details.win_state.entity.cli_id)
end)

h.test('details: a stale diff response never overwrites a newer entity', function()
  reset()
  local pending = {}
  local orig = cli.diff_json
  cli.diff_json = function(id, cb)
    table.insert(pending, { id = id, cb = cb })
  end
  details.show({ cli_id = 'aa', kind = 'file' })
  details.show({ cli_id = 'bb', kind = 'file' })
  cli.diff_json = orig

  -- Resolve out of order: the newer request first, the stale one after.
  pending[2].cb(nil, fixtures.diff_json)
  local fresh = #details.win_state.hunks
  h.assert_truthy(fresh > 0, 'newer response was not applied')
  pending[1].cb(nil, fixtures.diff_json_empty)

  h.assert_eq('bb', details.win_state.entity.cli_id)
  h.assert_eq(fresh, #details.win_state.hunks)
end)

h.test('details: show_for_line maps entity rows and ignores the rest', function()
  reset()
  local seen = {}
  local orig = cli.diff_json
  cli.diff_json = function(id, _)
    table.insert(seen, id)
  end
  for _, t in ipairs({ 'file', 'committed_file', 'commit', 'branch' }) do
    details.win_state.entity = nil
    details.show_for_line({ type = t, data = { cli_id = t .. '1' } })
  end
  details.win_state.entity = nil
  details.show_for_line({ type = 'uncommitted_header', data = { cli_id = 'zz' } })
  details.win_state.entity = nil
  details.show_for_line({ type = 'blank' })
  details.show_for_line({ type = 'merge_base', data = { cli_id = 'mb' } })
  details.show_for_line(nil)
  cli.diff_json = orig

  h.assert_eq(5, #seen)
  h.assert_eq('file1', seen[1])
  h.assert_eq('zz', seen[5])
  h.assert_falsy(details.win_state.entity, 'ignored rows changed the pane')
end)

h.test('details: a diff in flight across a close/reopen is still dropped', function()
  reset()
  local pending
  local orig = cli.diff_json
  cli.diff_json = function(_, cb)
    pending = cb
  end
  details.show({ cli_id = 'aa', kind = 'file' })
  local stale = pending
  -- Close and reopen: the generation counter must not rewind, or `aa`'s reply
  -- would land under `bb` and stick there (`show` no-ops on the same entity).
  details.close()
  details.show({ cli_id = 'bb', kind = 'file' })
  cli.diff_json = orig

  stale(nil, fixtures.diff_json)
  h.assert_eq('bb', details.win_state.entity.cli_id)
  h.assert_eq(0, #details.win_state.hunks, 'stale payload rendered after reopen')
end)

h.test('details: follow_cursor debounces a burst into one diff request', function()
  reset()
  local sb = mock_status_buf()
  details.open(sb)

  local calls = 0
  local orig = cli.diff_json
  cli.diff_json = function(_, _)
    calls = calls + 1
  end
  sb.lines = { { type = 'file', data = { cli_id = 'aa' } } }
  vim.api.nvim_win_set_cursor(sb.win, { 1, 0 })
  for _ = 1, 10 do
    details.follow_cursor(sb)
  end
  h.assert_eq(0, calls, 'follow_cursor fired synchronously')
  vim.wait(300, function()
    return calls > 0
  end)
  cli.diff_json = orig

  h.assert_eq(1, calls)
  details.close()
  pcall(vim.api.nvim_buf_delete, sb.buf, { force = true })
end)

h.test('details: open splits beside the status window and close tears it down', function()
  reset()
  local sb = mock_status_buf()
  local before = #vim.api.nvim_list_wins()

  details.open(sb)
  h.assert_truthy(details.is_open())
  h.assert_eq(before + 1, #vim.api.nvim_list_wins())
  h.assert_eq(sb.win, vim.api.nvim_get_current_win(), 'focus did not return to status')

  details.open(sb) -- idempotent
  h.assert_eq(before + 1, #vim.api.nvim_list_wins())

  details.close()
  h.assert_falsy(details.is_open())
  h.assert_eq(before, #vim.api.nvim_list_wins())
  pcall(vim.api.nvim_buf_delete, sb.buf, { force = true })
end)

h.test('details: toggle_full hides the status window and restores it', function()
  reset()
  local sb = mock_status_buf()
  details.open(sb)
  local with_pane = #vim.api.nvim_list_wins()

  details.toggle_full(sb)
  h.assert_truthy(details.win_state.full)
  h.assert_falsy(sb.win and vim.api.nvim_win_is_valid(sb.win), 'status window survived fullscreen')
  h.assert_eq(with_pane - 1, #vim.api.nvim_list_wins())
  h.assert_truthy(vim.api.nvim_buf_is_valid(sb.buf), 'status buffer was wiped')

  details.toggle_full(sb)
  h.assert_falsy(details.win_state.full)
  h.assert_truthy(sb.win and vim.api.nvim_win_is_valid(sb.win), 'status window was not restored')
  h.assert_eq(with_pane, #vim.api.nvim_list_wins())

  details.close()
  pcall(vim.api.nvim_buf_delete, sb.buf, { force = true })
end)

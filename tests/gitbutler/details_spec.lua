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

-- Landed commits (below the base) can't be addressed by `but diff`, so `d`
-- renders `git show` output. The rows are read-only and classify message,
-- meta, and +/- diff lines for highlighting.
h.test('details: _show_line_hl classifies git show lines', function()
  -- File markers must win over the bare +/- diff-line rules.
  h.assert_eq('GitButlerDetailFile', details._show_line_hl('--- a/foo.lua'))
  h.assert_eq('GitButlerDetailFile', details._show_line_hl('+++ b/foo.lua'))
  h.assert_eq('GitButlerDetailFile', details._show_line_hl('diff --git a/foo.lua b/foo.lua'))
  h.assert_eq('DiffAdd', details._show_line_hl('+added line'))
  h.assert_eq('DiffDelete', details._show_line_hl('-removed line'))
  h.assert_eq('GitButlerDetailHunk', details._show_line_hl('@@ -1,2 +1,3 @@'))
  h.assert_eq('GitButlerHelp', details._show_line_hl('Author: Adam <a@b.c>'))
  -- Message body and context lines carry no highlight.
  h.assert_eq(nil, details._show_line_hl('    a commit subject'))
  h.assert_eq(nil, details._show_line_hl(' unchanged context'))
end)

-- A whole-commit details view prepends the same commit/Author/Date/message
-- header the landed-history git-show view uses, so the two read consistently.
h.test('details: build prepends commit meta header before the diff', function()
  local meta = {
    sha = 'deadbeef',
    author = 'Adam Bosnjakovic',
    email = 'adam@adimension.io',
    date = '2026-03-24T02:31:23+00:00',
    message = 'add login endpoint\n\nwith a body line',
  }
  local rows = details.build(fixtures.diff_json, { meta = meta })
  h.assert_eq('detail_meta', rows[1].type)
  h.assert_eq('commit deadbeef', rows[1].text)
  h.assert_eq('Author: Adam Bosnjakovic <adam@adimension.io>', rows[2].text)
  h.assert_eq('Date:   2026-03-24 02:31:23+00:00', rows[3].text)
  h.assert_eq('    add login endpoint', rows[5].text)
  h.assert_eq('    with a body line', rows[7].text)
  -- The structured diff still follows, and hunk row indices account for the header.
  local _, hunks = details.build(fixtures.diff_json, { meta = meta })
  local _, hunks_no_meta = details.build(fixtures.diff_json, {})
  h.assert_truthy(hunks[1].row > hunks_no_meta[1].row, 'hunk rows shift down by the header height')
  -- Meta rows are read-only.
  h.assert_truthy(not rows[1].selectable)
end)

h.test('details: build without meta is unchanged (no header rows)', function()
  local rows = details.build(fixtures.diff_json, {})
  h.assert_eq('detail_file', rows[1].type)
end)

h.test('details: build prepends meta even when the commit has no changes', function()
  local rows = details.build({ changes = {} }, { meta = { sha = 'abc', message = 'empty' } })
  h.assert_eq('detail_meta', rows[1].type)
  local saw_no_changes = false
  for _, r in ipairs(rows) do
    if r.text:match('%(no changes%)') then
      saw_no_changes = true
    end
  end
  h.assert_truthy(saw_no_changes, 'still shows (no changes) after the header')
end)

h.test('details: _commit_rows is read-only and spans every classified line', function()
  local raw = table.concat({
    'commit deadbeef',
    'Author: Adam <a@b.c>',
    '',
    '    subject line',
    '',
    'diff --git a/f.lua b/f.lua',
    '@@ -1 +1 @@',
    '-old',
    '+new',
  }, '\n')
  local rows = details._commit_rows(raw)
  h.assert_eq(9, #rows)
  for _, r in ipairs(rows) do
    h.assert_truthy(not r.selectable, 'landed commit rows are read-only')
    h.assert_eq('commit_show', r.type)
  end
  h.assert_eq('-old', rows[8].text)
  h.assert_eq('DiffDelete', rows[8].spans[1][3])
  h.assert_eq('DiffAdd', rows[9].spans[1][3])
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

h.test('details: _next_hunk steps and clamps at both ends', function()
  local hunks = { { row = 2 }, { row = 6 }, { row = 9 } }
  h.assert_eq(2, details._next_hunk(hunks, 1, 1))
  h.assert_eq(1, details._next_hunk(hunks, 2, -1))
  h.assert_eq(1, details._next_hunk(hunks, 1, -1), 'clamped at the first hunk')
  h.assert_eq(3, details._next_hunk(hunks, 3, 1), 'clamped at the last hunk')
  h.assert_eq(1, details._next_hunk({}, 1, 1), 'empty list stays at 1')
end)

h.test('details: _hunk_row maps an index to its header row', function()
  local hunks = { { row = 2, end_row = 5 }, { row = 6, end_row = 8 } }
  h.assert_eq(2, details._hunk_row(hunks, 1))
  h.assert_eq(6, details._hunk_row(hunks, 2))
  h.assert_falsy(details._hunk_row(hunks, 3))
  h.assert_falsy(details._hunk_row({}, 1))
end)

h.test('details: _hunk_at resolves a row to its owning hunk', function()
  local hunks = { { row = 2, end_row = 5 }, { row = 7, end_row = 9 } }
  h.assert_eq(1, details._hunk_at(hunks, 2), 'header row')
  h.assert_eq(1, details._hunk_at(hunks, 4), 'mid-body row')
  h.assert_eq(1, details._hunk_at(hunks, 5), 'last body row is still inside')
  h.assert_eq(2, details._hunk_at(hunks, 7), 'next hunk header')
  h.assert_falsy(details._hunk_at(hunks, 1), 'file header row owns no hunk')
  h.assert_falsy(details._hunk_at(hunks, 6), 'gap between hunks owns no hunk')
  h.assert_falsy(details._hunk_at(hunks, 99), 'past the end owns no hunk')
end)

h.test('details: j/k move the selection bar and the details cursor', function()
  reset()
  local sb = mock_status_buf()
  details.open(sb)
  local st = details.win_state
  st.data = fixtures.diff_json
  st.marked = { keep = true }
  details._rebuild()
  h.assert_eq(3, #st.hunks)

  details._select_hunk(details._next_hunk(st.hunks, st.selected, 1))
  h.assert_eq(2, st.selected)
  h.assert_eq(st.hunks[2].row, vim.api.nvim_win_get_cursor(st.win)[1])
  h.assert_truthy(st.rows[st.hunks[2].row].text:match('^▌'), st.rows[st.hunks[2].row].text)
  h.assert_truthy(st.marked.keep, 'marked set was dropped by the re-render')

  details._select_hunk(details._next_hunk(st.hunks, st.selected, -1))
  h.assert_eq(1, st.selected)
  h.assert_eq(st.hunks[1].row, vim.api.nvim_win_get_cursor(st.win)[1])

  details.close()
  pcall(vim.api.nvim_buf_delete, sb.buf, { force = true })
end)

h.test('details: moving the cursor onto a body line snaps to its hunk', function()
  reset()
  local sb = mock_status_buf()
  details.open(sb)
  local st = details.win_state
  st.data = fixtures.diff_json
  details._rebuild()

  -- Drive the real CursorMoved autocmd rather than _sync_cursor directly, so
  -- the test also covers the registration in `open`, and count renders: one
  -- per genuine selection change and none for the events our own render fires.
  local renders = 0
  local orig_render = details._render
  details._render = function(rows)
    renders = renders + 1
    orig_render(rows)
  end
  local function cursor_moved(row)
    vim.api.nvim_win_set_cursor(st.win, { row, 0 })
    vim.api.nvim_exec_autocmds('CursorMoved', { buffer = st.buf })
  end

  -- A body line of the second hunk, not its header.
  cursor_moved(st.hunks[2].row + 1)
  h.assert_eq(2, st.selected)
  h.assert_eq(1, renders, 're-render loop: the sync rendered more than once')

  -- Re-firing on the same hunk is a no-op: the cursor still sits inside hunk 2.
  cursor_moved(st.hunks[2].row + 1)
  h.assert_eq(1, renders, 'sync rendered again with no change')

  -- A row owned by no hunk leaves the selection alone.
  cursor_moved(1)
  h.assert_eq(2, st.selected)
  h.assert_eq(1, renders, 'a hunkless row triggered a render')
  details._render = orig_render

  details.close()
  pcall(vim.api.nvim_buf_delete, sb.buf, { force = true })
end)

---Invoke the pane's buffer-local mapping for `lhs`.
local function press(buf, lhs)
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
    if map.lhs == lhs and map.callback then
      map.callback()
      return true
    end
  end
  return false
end

h.test('details: q and d in the pane close only the pane', function()
  for _, key in ipairs({ 'q', 'd' }) do
    reset()
    local sb = mock_status_buf()
    details.open(sb)
    h.assert_truthy(press(details.win_state.buf, key), 'no mapping for ' .. key)

    h.assert_falsy(details.is_open(), key .. ' left the pane open')
    h.assert_truthy(vim.api.nvim_buf_is_valid(sb.buf), key .. ' wiped the status buffer')
    h.assert_truthy(vim.api.nvim_win_is_valid(sb.win), key .. ' closed the status window')
    h.assert_eq(sb.win, vim.api.nvim_get_current_win(), key .. ' did not return focus to status')
    pcall(vim.api.nvim_buf_delete, sb.buf, { force = true })
  end
end)

h.test('details: h, <Left> and <Esc> focus the status window', function()
  for _, key in ipairs({ 'h', '<Left>', '<Esc>' }) do
    reset()
    local sb = mock_status_buf()
    details.open(sb)
    vim.api.nvim_set_current_win(details.win_state.win)
    h.assert_truthy(press(details.win_state.buf, key), 'no mapping for ' .. key)

    h.assert_eq(sb.win, vim.api.nvim_get_current_win(), key .. ' did not focus status')
    h.assert_truthy(details.is_open(), key .. ' closed the pane')
    details.close()
    pcall(vim.api.nvim_buf_delete, sb.buf, { force = true })
  end
end)

--- Hunk operations ----------------------------------------------------------

---Open the pane with the fixture diff already loaded and hunk 1 selected.
local function open_with_diff()
  reset()
  local sb = mock_status_buf()
  details.open(sb)
  local st = details.win_state
  st.entity = { cli_id = 'aa', kind = 'file' }
  st.data = fixtures.diff_json
  details._rebuild()
  details._select_hunk(1)
  return sb, st
end

h.test('details: <Space> toggles the mark and the header shows an aligned ✔︎', function()
  local sb, st = open_with_diff()
  details._toggle_mark()
  h.assert_truthy(st.marked[st.hunks[1].id], 'hunk was not marked')

  local header = st.rows[st.hunks[1].row].text
  h.assert_truthy(header:match('^✔︎ @@'), header)
  -- Two display columns, exactly like the '  ' and '▌ ' leads.
  h.assert_eq(2, vim.fn.strdisplaywidth(header:sub(1, #'✔︎ ')))

  details._toggle_mark()
  h.assert_falsy(st.marked[st.hunks[1].id], 'mark did not toggle off')
  h.assert_truthy(st.rows[st.hunks[1].row].text:match('^▌'), 'selection bar did not come back')

  details.close()
  pcall(vim.api.nvim_buf_delete, sb.buf, { force = true })
end)

h.test('details: hunk entries carry the new-file line for jump-to-code', function()
  local _, hunks = details.build(fixtures.diff_json, {})
  h.assert_eq(1, hunks[1].line) -- src/auth.lua first hunk, newStart = 1
  h.assert_eq(22, hunks[2].line) -- second hunk, newStart = 22
  h.assert_eq(5, hunks[3].line) -- src/config.lua, newStart = 5
end)

h.test('details: <CR>/o opens the selected hunk file at its line', function()
  local sb, st = open_with_diff()
  st.selected = 2

  local opened
  local editor = require('gitbutler.ui.editor')
  local orig = editor.open
  editor.open = function(path, line)
    opened = { path = path, line = line }
  end
  details._open_hunk()
  editor.open = orig

  h.assert_eq('src/auth.lua', opened.path)
  h.assert_eq(22, opened.line, 'landed on the selected hunk line')

  details.close()
  pcall(vim.api.nvim_buf_delete, sb.buf, { force = true })
end)

h.test('details: _targets prefers marked hunks over the selection', function()
  local sb, st = open_with_diff()
  local ids = details._targets()
  h.assert_eq(1, #ids)
  h.assert_eq(st.hunks[1].id, ids[1], 'selected hunk is the fallback target')

  st.marked = { [st.hunks[2].id] = true, [st.hunks[3].id] = true }
  ids = details._targets()
  h.assert_eq(2, #ids)
  h.assert_eq(st.hunks[2].id, ids[1])

  -- Ids left over from another entity must not leak into a command.
  st.marked = { ['gone:9'] = true }
  ids = details._targets()
  h.assert_eq(1, #ids)
  h.assert_eq(st.hunks[1].id, ids[1])

  details.close()
  pcall(vim.api.nvim_buf_delete, sb.buf, { force = true })
end)

h.test('details: x discards every marked hunk, then clears marks and refreshes', function()
  local sb, st = open_with_diff()
  st.marked = { [st.hunks[1].id] = true, [st.hunks[2].id] = true }

  local discarded, refreshed, reloaded = {}, 0, 0
  local orig_discard, orig_select = cli.discard, vim.ui.select
  local orig_refresh = require('gitbutler.ui.status').refresh
  local orig_diff, orig_notify = cli.diff_json, vim.notify
  cli.discard = function(id, cb)
    table.insert(discarded, id)
    cb(nil, {})
  end
  vim.ui.select = function(_, _, cb)
    cb('Yes')
  end
  require('gitbutler.ui.status').refresh = function()
    refreshed = refreshed + 1
  end
  cli.diff_json = function(_, _)
    reloaded = reloaded + 1
  end
  vim.notify = function() end

  details._hunk_discard()

  cli.discard, vim.ui.select, cli.diff_json, vim.notify = orig_discard, orig_select, orig_diff, orig_notify
  require('gitbutler.ui.status').refresh = orig_refresh

  h.assert_eq(2, #discarded)
  h.assert_eq(1, refreshed)
  h.assert_eq(1, reloaded, 'the changed diff was not re-requested')
  h.assert_falsy(next(details.win_state.marked), 'marks survived the discard')

  details.close()
  pcall(vim.api.nvim_buf_delete, sb.buf, { force = true })
end)

h.test('details: x stops at the first discard error and still refreshes', function()
  local sb, st = open_with_diff()
  st.marked = { [st.hunks[1].id] = true, [st.hunks[2].id] = true, [st.hunks[3].id] = true }

  local calls, refreshed, err_msg = 0, 0, nil
  local orig_discard, orig_select = cli.discard, vim.ui.select
  local orig_refresh = require('gitbutler.ui.status').refresh
  local orig_diff, orig_notify = cli.diff_json, vim.notify
  cli.discard = function(_, cb)
    calls = calls + 1
    cb(calls == 2 and 'boom' or nil, {})
  end
  vim.ui.select = function(_, _, cb)
    cb('Yes')
  end
  require('gitbutler.ui.status').refresh = function()
    refreshed = refreshed + 1
  end
  cli.diff_json = function(_, _) end
  vim.notify = function(msg, level)
    if level == vim.log.levels.ERROR then
      err_msg = msg
    end
  end

  details._hunk_discard()

  cli.discard, vim.ui.select, cli.diff_json, vim.notify = orig_discard, orig_select, orig_diff, orig_notify
  require('gitbutler.ui.status').refresh = orig_refresh

  h.assert_eq(2, calls, 'the chain did not stop at the failing hunk')
  h.assert_eq(1, refreshed, 'a failed chain skipped the refresh')
  h.assert_truthy(err_msg and err_msg:match('boom'), tostring(err_msg))

  details.close()
  pcall(vim.api.nvim_buf_delete, sb.buf, { force = true })
end)

h.test('details: a committed diff (no hunk ids) navigates but cannot be operated on', function()
  reset()
  local sb = mock_status_buf()
  details.open(sb)
  local st = details.win_state
  st.entity = { cli_id = 'cc', kind = 'commit' }
  st.data = fixtures.diff_json_committed
  details._rebuild()

  -- Hunks are still registered, so j/k navigation works on committed diffs.
  h.assert_eq(3, #st.hunks)
  h.assert_falsy(st.hunks[1].id, 'committed hunks must carry no id')
  details._select_hunk(2)
  h.assert_eq(2, st.selected)

  -- <Space> must not throw ("table index is nil") and must not mark.
  local ok, err = pcall(details._toggle_mark)
  h.assert_truthy(ok, tostring(err))
  h.assert_falsy(next(st.marked), 'an id-less hunk was marked')

  -- x and r warn instead of silently doing nothing, and touch no CLI.
  local warns, discards, rubs = 0, 0, 0
  local orig_notify, orig_discard, orig_select = vim.notify, cli.discard, vim.ui.select
  local modes = require('gitbutler.ui.modes')
  local orig_rub = modes.enter_rub
  vim.notify = function(_, level)
    if level == vim.log.levels.WARN then
      warns = warns + 1
    end
  end
  cli.discard = function(_, cb)
    discards = discards + 1
    cb(nil, {})
  end
  vim.ui.select = function(_, _, cb)
    cb('Yes')
  end
  modes.enter_rub = function()
    rubs = rubs + 1
  end

  details._hunk_discard()
  details._hunk_rub()

  vim.notify, cli.discard, vim.ui.select = orig_notify, orig_discard, orig_select
  modes.enter_rub = orig_rub

  h.assert_eq(2, warns, 'x and r did not both warn')
  h.assert_eq(0, discards)
  h.assert_eq(0, rubs)

  details.close()
  pcall(vim.api.nvim_buf_delete, sb.buf, { force = true })
end)

h.test('details: a failed discard keeps the marks so the rest can be retried', function()
  local sb, st = open_with_diff()
  st.marked = { [st.hunks[1].id] = true, [st.hunks[2].id] = true }

  local orig_discard, orig_select = cli.discard, vim.ui.select
  local orig_refresh = require('gitbutler.ui.status').refresh
  local orig_diff, orig_notify = cli.diff_json, vim.notify
  cli.discard = function(_, cb)
    cb('boom', {})
  end
  vim.ui.select = function(_, _, cb)
    cb('Yes')
  end
  require('gitbutler.ui.status').refresh = function() end
  cli.diff_json = function(_, _) end
  vim.notify = function() end

  details._hunk_discard()

  cli.discard, vim.ui.select, cli.diff_json, vim.notify = orig_discard, orig_select, orig_diff, orig_notify
  require('gitbutler.ui.status').refresh = orig_refresh

  -- The re-show clears marks as a per-diff reset; a failed chain restores them.
  h.assert_truthy(next(details.win_state.marked), 'marks were wiped by a failed discard')

  details.close()
  pcall(vim.api.nvim_buf_delete, sb.buf, { force = true })
end)

h.test('details: showing a different entity clears the marks', function()
  reset()
  local orig = cli.diff_json
  cli.diff_json = function(_, _) end
  details.show({ cli_id = 'aa', kind = 'file' })
  details.win_state.marked = { ['xw:1'] = true }
  details.show({ cli_id = 'bb', kind = 'file' })
  cli.diff_json = orig
  h.assert_falsy(next(details.win_state.marked), 'marks survived an entity change')
end)

h.test('details: x does nothing when the confirmation is declined', function()
  local sb = open_with_diff()
  local calls = 0
  local orig_discard, orig_select = cli.discard, vim.ui.select
  cli.discard = function(_, cb)
    calls = calls + 1
    cb(nil, {})
  end
  vim.ui.select = function(_, _, cb)
    cb('No')
  end
  details._hunk_discard()
  cli.discard, vim.ui.select = orig_discard, orig_select
  h.assert_eq(0, calls)

  details.close()
  pcall(vim.api.nvim_buf_delete, sb.buf, { force = true })
end)

h.test('details: _hunk_copy_text strips the gutter and keeps diff markers', function()
  local rows, hunks = details.build(fixtures.diff_json, { selected_hunk = 1 })
  local text = details._hunk_copy_text(rows, hunks[1])
  local lines = vim.split(text, '\n')

  h.assert_eq(hunks[1].end_row - hunks[1].row, #lines, 'body line count')
  for _, line in ipairs(lines) do
    h.assert_falsy(line:match('│'), 'gutter survived: ' .. line)
    h.assert_truthy(line:match('^[%+%- ]'), 'diff marker was stripped: ' .. line)
  end
  -- The header itself is not part of the copied body.
  h.assert_falsy(text:match('@@'), text)
  h.assert_falsy(details._hunk_copy_text(rows, nil), 'no hunk yields no text')
end)

h.test('details: y sets both registers from the selected hunk', function()
  local sb = open_with_diff()
  local orig_notify = vim.notify
  vim.notify = function() end
  details._hunk_copy()
  vim.notify = orig_notify

  local copied = vim.fn.getreg('"')
  h.assert_truthy(#copied > 0, 'unnamed register is empty')
  h.assert_falsy(copied:match('│'), copied)

  details.close()
  pcall(vim.api.nvim_buf_delete, sb.buf, { force = true })
end)

h.test('details: r enters rub mode with a kind=file source carrying the hunk ids', function()
  local sb, st = open_with_diff()
  st.marked = { [st.hunks[2].id] = true, [st.hunks[3].id] = true }

  local captured_buf, captured
  local modes = require('gitbutler.ui.modes')
  local orig = modes.enter_rub
  modes.enter_rub = function(buf, source)
    captured_buf, captured = buf, source
  end
  vim.api.nvim_set_current_win(details.win_state.win)
  details._hunk_rub()
  modes.enter_rub = orig

  h.assert_eq(sb, captured_buf, 'rub was entered on the wrong buffer')
  h.assert_eq(sb.win, vim.api.nvim_get_current_win(), 'focus stayed in the details pane')
  h.assert_eq('file', captured.kind)
  h.assert_eq(2, #captured.ids)
  h.assert_eq(st.hunks[2].id, captured.ids[1])
  h.assert_eq(0, #captured.rows, 'source rows must be empty: the source is in the other window')
  -- is_rub_target iterates source.rows, so an empty list is simply no exclusion.
  h.assert_truthy(
    modes.is_rub_target({ source = captured }, { selectable = true, type = 'branch' }, 1),
    'empty source rows broke the target guard'
  )

  details.close()
  pcall(vim.api.nvim_buf_delete, sb.buf, { force = true })
end)

h.test('details: details_focus focuses the pane, warns when closed', function()
  reset()
  local sb = mock_status_buf()
  local actions = require('gitbutler.actions')
  local warned
  local orig = vim.notify
  vim.notify = function(msg, level)
    warned = { msg = msg, level = level }
  end

  actions.details_focus(sb)
  h.assert_truthy(warned, 'closed pane did not notify')
  h.assert_eq(vim.log.levels.WARN, warned.level)

  details.open(sb)
  h.assert_eq(sb.win, vim.api.nvim_get_current_win())
  actions.details_focus(sb)
  h.assert_eq(details.win_state.win, vim.api.nvim_get_current_win())

  vim.notify = orig
  details.close()
  pcall(vim.api.nvim_buf_delete, sb.buf, { force = true })
end)

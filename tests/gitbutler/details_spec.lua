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
  details.show_for_line({ type = 'connector' })
  details.show_for_line(nil)
  cli.diff_json = orig

  h.assert_eq(5, #seen)
  h.assert_eq('file1', seen[1])
  h.assert_eq('zz', seen[5])
  h.assert_falsy(details.win_state.entity, 'ignored rows changed the pane')
end)

-- The common base carries a sha but no cli_id, so `but diff` can't address it.
-- It used to fall through and leave the pane on whatever was there before.
h.test('details: the common base opens through git show, like landed history', function()
  reset()
  local seen = {}
  local orig = details.show_commit
  ---@diagnostic disable-next-line: duplicate-set-field
  details.show_commit = function(sha)
    table.insert(seen, sha)
  end
  details.show_for_line({ type = 'merge_base', data = { sha = 'mb1' } })
  details.show_for_line({ type = 'base_commit', data = { sha = 'bc1' } })
  details.show_commit = orig

  h.assert_eq(2, #seen)
  h.assert_eq('mb1', seen[1])
  h.assert_eq('bc1', seen[2])
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

  -- +2: the vsplit itself, plus the pinned hint float that `Buffer:attach`
  -- opens now the pane is a Buffer.
  details.open(sb)
  h.assert_truthy(details.is_open())
  h.assert_eq(before + 2, #vim.api.nvim_list_wins())
  h.assert_eq(sb.win, vim.api.nvim_get_current_win(), 'focus did not return to status')

  details.open(sb) -- idempotent
  h.assert_eq(before + 2, #vim.api.nvim_list_wins())

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

h.test('details: x discards every marked hunk in one call, then clears marks and refreshes', function()
  local sb, st = open_with_diff()
  st.marked = { [st.hunks[1].id] = true, [st.hunks[2].id] = true }
  -- The re-show wipes st.hunks, so pin the expected ids before discarding.
  local expected = { st.hunks[1].id, st.hunks[2].id }

  local calls, refreshed, reloaded = {}, 0, 0
  local orig_discard, orig_select = cli.discard, vim.ui.select
  local orig_refresh = require('gitbutler.ui.status').refresh
  local orig_diff, orig_notify = cli.diff_json, vim.notify
  cli.discard = function(ids, cb)
    table.insert(calls, ids)
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

  h.assert_eq(1, #calls, 'discard must be one batched call, not a per-hunk chain')
  h.assert_eq(2, #calls[1], 'both marked hunks belong to the single call')
  h.assert_eq(expected[1], calls[1][1])
  h.assert_eq(expected[2], calls[1][2])
  h.assert_eq(1, refreshed)
  h.assert_eq(1, reloaded, 'the changed diff was not re-requested')
  h.assert_falsy(next(details.win_state.marked), 'marks survived the discard')

  details.close()
  pcall(vim.api.nvim_buf_delete, sb.buf, { force = true })
end)

h.test('details: a failed discard surfaces the error, still refreshes and keeps the marks', function()
  local sb, st = open_with_diff()
  st.marked = { [st.hunks[1].id] = true, [st.hunks[2].id] = true, [st.hunks[3].id] = true }

  local calls, refreshed, err_msg = {}, 0, nil
  local orig_discard, orig_select = cli.discard, vim.ui.select
  local orig_refresh = require('gitbutler.ui.status').refresh
  local orig_diff, orig_notify = cli.diff_json, vim.notify
  cli.discard = function(ids, cb)
    table.insert(calls, ids)
    cb('boom', {})
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

  h.assert_eq(1, #calls, 'a failure must not fan out: discard is one call for the whole selection')
  h.assert_eq(3, #calls[1], 'all three marked hunks belong to the single call')
  h.assert_eq(1, refreshed, 'a failed discard skipped the refresh')
  h.assert_truthy(err_msg and err_msg:match('boom'), tostring(err_msg))
  h.assert_truthy(next(details.win_state.marked), 'a failed discard must keep the marks so it can be retried')

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

  -- x and a warn instead of silently doing nothing, and touch no CLI.
  local warns, discards, amends = 0, 0, 0
  local orig_notify, orig_discard, orig_select = vim.notify, cli.discard, vim.ui.select
  local modes = require('gitbutler.ui.modes')
  local orig_enter_verb = modes.enter_verb
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
  modes.enter_verb = function()
    amends = amends + 1
  end

  details._hunk_discard()
  details._hunk_amend()

  vim.notify, cli.discard, vim.ui.select = orig_notify, orig_discard, orig_select
  modes.enter_verb = orig_enter_verb

  h.assert_eq(2, warns, 'x and a did not both warn')
  h.assert_eq(0, discards)
  h.assert_eq(0, amends)

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
  -- `+` is the system clipboard: leaving the hunk in it would make `make test`
  -- overwrite whatever the developer had copied.
  local orig_unnamed = vim.fn.getreg('"')
  local orig_plus = vim.fn.getreg('+')
  h.after(function()
    vim.fn.setreg('"', orig_unnamed)
    vim.fn.setreg('+', orig_plus)
  end)
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

h.test('details: a enters amend mode with a kind=file source carrying the hunk ids', function()
  local sb, st = open_with_diff()
  st.marked = { [st.hunks[2].id] = true, [st.hunks[3].id] = true }

  local captured_buf, captured_verb, captured
  local modes = require('gitbutler.ui.modes')
  local orig = modes.enter_verb
  modes.enter_verb = function(buf, verb, source)
    captured_buf, captured_verb, captured = buf, verb, source
  end
  vim.api.nvim_set_current_win(details.win_state.win)
  details._hunk_amend()
  modes.enter_verb = orig

  h.assert_eq(sb, captured_buf, 'amend was entered on the wrong buffer')
  h.assert_eq('amend', captured_verb, 'the hunk pane amends rather than any other verb')
  h.assert_eq(sb.win, vim.api.nvim_get_current_win(), 'focus stayed in the details pane')
  h.assert_eq('file', captured.kind)
  h.assert_eq(2, #captured.ids)
  h.assert_eq(st.hunks[2].id, captured.ids[1])
  h.assert_eq(0, #captured.rows, 'source rows must be empty: the source is in the other window')
  -- is_verb_target iterates source.rows, so an empty list is simply no exclusion.
  h.assert_truthy(
    modes.is_verb_target({ source = captured }, { selectable = true, type = 'branch' }, 1),
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

-- The gutter has always computed these numbers and thrown them away. A comment
-- needs to name the line it is attached to, so the row keeps them.
h.test('details: a diff line records its side, line number and raw text', function()
  local rows = details.build(fixtures.diff_json, {})
  local first_added, first_removed, first_context
  for _, r in ipairs(rows) do
    if r.type == 'detail_line' then
      local marker = (r.data.raw or ''):sub(1, 1)
      if marker == '+' and not first_added then
        first_added = r
      elseif marker == '-' and not first_removed then
        first_removed = r
      elseif marker ~= '+' and marker ~= '-' and not first_context then
        first_context = r
      end
    end
  end

  -- Hunk 1 is `@@ -1,2 +1,4 @@`: context ` local M = {}` at 1/1, then the two
  -- additions at new 2 and 3.
  h.assert_eq('new', first_added.data.side)
  h.assert_eq(2, first_added.data.line)
  h.assert_eq("+local jwt = require('jwt')", first_added.data.raw)
  h.assert_eq('src/auth.lua', first_added.data.path)

  h.assert_eq('new', first_context.data.side)
  h.assert_eq(1, first_context.data.line)

  -- Hunk 2 removes ` return false` at old line 21.
  h.assert_eq('old', first_removed.data.side)
  h.assert_eq(21, first_removed.data.line)
  h.assert_eq('-  return false', first_removed.data.raw)
end)

-- Each line owns its data now. Sharing one table across a hunk would give every
-- line the same line number.
h.test('details: diff lines do not share one data table', function()
  local rows = details.build(fixtures.diff_json, {})
  local lines = {}
  for _, r in ipairs(rows) do
    if r.type == 'detail_line' then
      table.insert(lines, r)
    end
  end
  h.assert_truthy(#lines > 1, 'fixture has several diff lines')
  h.assert_truthy(lines[1].data ~= lines[2].data, 'each row carries its own data table')
end)

-- A comment is a row like any other row. That is the whole design: one rows
-- model, asserted as text, cursor-addressable, no second rendering path.
h.test('details: a comment renders under the line it belongs to', function()
  local comment = {
    scope = 'commit',
    ref = 'abc',
    path = 'src/auth.lua',
    side = 'new',
    line = 2,
    captured = "+local jwt = require('jwt')",
    text = 'Pull this to the top of the file.',
  }
  local rows = details.build(fixtures.diff_json, {
    comments = { ['src/auth.lua:new:2'] = comment },
    width = 80,
  })

  local anchor_index, comment_row
  for i, r in ipairs(rows) do
    if r.type == 'detail_line' and r.data.path == 'src/auth.lua' and r.data.side == 'new' and r.data.line == 2 then
      anchor_index = i
    elseif r.type == 'detail_comment' and not comment_row then
      comment_row = { index = i, row = r }
    end
  end

  h.assert_truthy(anchor_index, 'the anchored line is in the rows')
  h.assert_eq(anchor_index + 1, comment_row.index, 'the comment follows its line immediately')
  -- 14 columns of indent: two for the lead, twelve for the gutter, so the elbow
  -- sits directly under the code rather than under the line numbers.
  h.assert_eq(string.rep(' ', 14) .. '╰ Pull this to the top of the file.', comment_row.row.text)
  h.assert_falsy(comment_row.row.selectable, 'comment rows are not hunk targets')
  h.assert_eq(2, comment_row.row.data.line)
end)

-- The marker is the only thing that says "you already commented here" while
-- scrolling. It sits in the lead column's second slot, which has always been a
-- pad space, so nothing else on the row moves.
h.test('details: a commented line carries the marker in the lead column', function()
  local rows = details.build(fixtures.diff_json, {
    comments = {
      ['src/auth.lua:new:2'] = {
        path = 'src/auth.lua',
        side = 'new',
        line = 2,
        captured = "+local jwt = require('jwt')",
        text = 'x',
      },
    },
    width = 80,
  })
  local commented, plain
  for _, r in ipairs(rows) do
    if r.type == 'detail_line' and r.data.line == 2 and r.data.side == 'new' then
      commented = r
    elseif r.type == 'detail_line' and r.data.line == 1 then
      plain = r
    end
  end
  h.assert_eq(' ●', commented.text:sub(1, #' ●'))
  h.assert_eq('  ', plain.text:sub(1, 2))
end)

-- Uncommitted diffs move under the reviewer. A note must never silently point
-- at code that has changed since it was written.
h.test('details: a comment goes stale when its line no longer matches', function()
  local moved = {
    path = 'src/auth.lua',
    side = 'new',
    line = 2,
    captured = '+local jwt = require("something else")',
    text = 'still relevant?',
  }
  local fresh = {
    path = 'src/auth.lua',
    side = 'new',
    line = 3,
    captured = "+local secret = 'shh'",
    text = 'inline this',
  }
  local rows = details.build(fixtures.diff_json, {
    comments = { ['src/auth.lua:new:2'] = moved, ['src/auth.lua:new:3'] = fresh },
    width = 80,
  })

  h.assert_truthy(moved.stale, 'build marks the drifted comment')
  h.assert_falsy(fresh.stale, 'build leaves the matching comment alone')

  local stale_row
  for _, r in ipairs(rows) do
    if r.type == 'detail_comment' and r.data.line == 2 then
      stale_row = r
    end
  end
  h.assert_truthy(stale_row.text:match('stale'), 'the stale marker is visible in the pane: ' .. stale_row.text)
end)

-- The pane does not wrap, so an unwrapped paragraph would run off the right
-- edge and be unreadable — which defeats the point of showing it inline.
h.test('details: a long comment wraps to the pane width', function()
  local rows = details.build(fixtures.diff_json, {
    comments = {
      ['src/auth.lua:new:2'] = {
        path = 'src/auth.lua',
        side = 'new',
        line = 2,
        captured = "+local jwt = require('jwt')",
        text = 'one two three four five six seven eight nine ten eleven twelve',
      },
    },
    width = 40,
  })
  local body = {}
  for _, r in ipairs(rows) do
    if r.type == 'detail_comment' then
      table.insert(body, r.text)
    end
  end
  h.assert_truthy(#body > 1, 'the comment wrapped onto more than one row')
  for _, text in ipairs(body) do
    -- Display columns, not bytes: `╰` is three bytes and one column, and a
    -- comment body may hold multibyte characters of its own.
    h.assert_truthy(vim.fn.strdisplaywidth(text) <= 40, 'no comment row exceeds the pane width: ' .. text)
  end
end)

-- `y` copies a hunk's body. Comment rows now live inside a hunk's row range, so
-- without a skip the reviewer's own notes end up in the copied patch.
h.test('details: copying a hunk skips the comment rows inside it', function()
  local rows, hunks = details.build(fixtures.diff_json, {
    comments = {
      ['src/auth.lua:new:2'] = {
        path = 'src/auth.lua',
        side = 'new',
        line = 2,
        captured = "+local jwt = require('jwt')",
        text = 'do not copy me',
      },
    },
    width = 80,
  })
  local text = details._hunk_copy_text(rows, hunks[1])
  h.assert_falsy(text:match('do not copy me'), 'the comment is not part of the hunk body')
  h.assert_truthy(text:match("local jwt = require%('jwt'%)"), 'the diff line still is')
end)

-- Comment rows sit between the hunk header and the hunk's last line, so the
-- range has to grow with them or `y` and the `▌` bar both truncate.
h.test('details: hunk end_row accounts for comment rows', function()
  local _, without = details.build(fixtures.diff_json, { width = 80 })
  local _, with = details.build(fixtures.diff_json, {
    comments = {
      ['src/auth.lua:new:2'] = {
        path = 'src/auth.lua',
        side = 'new',
        line = 2,
        captured = "+local jwt = require('jwt')",
        text = 'a note',
      },
    },
    width = 80,
  })
  h.assert_eq(without[1].end_row + 1, with[1].end_row, 'one comment row extends the hunk by one')
end)

-- The stale suffix is appended after wrapping, so a stale comment has to be
-- wrapped narrower or its first row runs off a pane that does not wrap.
h.test('details: a long stale comment still fits the pane width', function()
  local rows = details.build(fixtures.diff_json, {
    comments = {
      ['src/auth.lua:new:2'] = {
        path = 'src/auth.lua',
        side = 'new',
        line = 2,
        captured = '+local jwt = require("something else")',
        text = 'one two three four five six seven eight nine ten eleven twelve',
      },
    },
    width = 40,
  })
  local body = {}
  for _, r in ipairs(rows) do
    if r.type == 'detail_comment' then
      table.insert(body, r.text)
    end
  end
  h.assert_truthy(#body > 1, 'the comment wrapped onto more than one row')
  h.assert_truthy(body[1]:match('stale'), 'the first row carries the stale tag: ' .. body[1])
  for _, text in ipairs(body) do
    h.assert_truthy(vim.fn.strdisplaywidth(text) <= 40, 'no comment row exceeds the pane width: ' .. text)
  end
end)

-- A comment records what it is attached to. That has to be resolved where the
-- status row is still in hand — by the time the diff arrives, the row is gone.
h.test('details: show_for_line resolves the scope and ref of each row kind', function()
  reset()
  local seen = {}
  local orig = details.show
  ---@diagnostic disable-next-line: duplicate-set-field
  details.show = function(entity)
    table.insert(seen, entity)
  end

  details.show_for_line({
    type = 'commit',
    data = { cli_id = 'aa', sha = 'deadbeef', commit = { message = 'fix: a thing\n\nbody' } },
  })
  details.show_for_line({ type = 'committed_file', data = { cli_id = 'bb', commit_id = 'cafebabe' } })
  -- Shaped like a real graph row: `name` is the display string, `branch` the
  -- payload it was derived from.
  details.show_for_line({
    type = 'branch',
    data = {
      cli_id = 'cc',
      name = 'fix/graph-tab-details',
      branch = { name = 'fix/graph-tab-details' },
    },
  })
  details.show_for_line({ type = 'file', data = { cli_id = 'dd' } })
  details.show_for_line({ type = 'uncommitted_header', data = { cli_id = 'zz' } })

  details.show = orig

  h.assert_eq(5, #seen)
  h.assert_eq('commit', seen[1].scope)
  h.assert_eq('deadbeef', seen[1].ref)
  h.assert_eq('fix: a thing', seen[1].subject)

  h.assert_eq('commit', seen[2].scope)
  h.assert_eq('cafebabe', seen[2].ref)
  h.assert_falsy(seen[2].subject, 'a committed-file row carries no message')

  -- A branch diff spans several commits, so no single sha describes a line in
  -- it. The branch name is what is actually known.
  h.assert_eq('branch', seen[3].scope)
  h.assert_eq('fix/graph-tab-details', seen[3].ref)

  h.assert_eq('uncommitted', seen[4].scope)
  h.assert_falsy(seen[4].ref, 'uncommitted changes have no ref')
  h.assert_eq('uncommitted', seen[5].scope)
end)

-- The graph labels a nameless branch `(unnamed)`. Anchoring comments to that
-- label makes every nameless lane the same lane, so one lane's notes render on
-- another. The cli id is what still tells them apart.
h.test('details: two nameless branches resolve to different refs', function()
  reset()
  local seen = {}
  local orig = details.show
  ---@diagnostic disable-next-line: duplicate-set-field
  details.show = function(entity)
    table.insert(seen, entity)
  end

  -- `branch.name` absent, and present as JSON null — `vim.NIL` is truthy, so a
  -- bare `or` would take it as a real name.
  details.show_for_line({
    type = 'branch',
    data = { cli_id = 'aa', name = '(unnamed)', branch = {} },
  })
  details.show_for_line({
    type = 'branch',
    data = { cli_id = 'bb', name = '(unnamed)', branch = { name = vim.NIL } },
  })

  details.show = orig

  h.assert_eq(2, #seen)
  h.assert_eq('aa', seen[1].ref)
  h.assert_eq('bb', seen[2].ref)
end)

-- `vim.json.decode` maps JSON null to `vim.NIL`, which is truthy — a bare
-- `meta.message and` guard doesn't catch it and `vim.split` throws. This is on
-- the cursor-move path, so it would fire while just scrolling the status view.
h.test('details: show_for_line survives a commit whose message is vim.NIL', function()
  reset()
  local seen = {}
  local orig = details.show
  ---@diagnostic disable-next-line: duplicate-set-field
  details.show = function(entity)
    table.insert(seen, entity)
  end

  h.assert_truthy(
    pcall(function()
      details.show_for_line({
        type = 'commit',
        data = { cli_id = 'aa', sha = 'deadbeef', commit = { message = vim.NIL } },
      })
    end),
    'show_for_line threw on a NIL commit message'
  )

  details.show = orig

  h.assert_eq(1, #seen)
  h.assert_falsy(seen[1].subject, 'a NIL message yields no subject')
end)

-- Without this the store is written but never read back, and comments vanish on
-- the next hunk selection.
h.test('details: _rebuild feeds the open diff its comments', function()
  reset()
  local review = require('gitbutler.review')
  review.clear()
  review.set({
    scope = 'commit',
    ref = 'deadbeef',
    path = 'src/auth.lua',
    side = 'new',
    line = 2,
    captured = "+local jwt = require('jwt')",
  }, 'from the store')

  details.win_state.entity = { cli_id = 'aa', kind = 'commit', scope = 'commit', ref = 'deadbeef' }
  details.win_state.data = fixtures.diff_json
  details._rebuild()

  local found
  for _, r in ipairs(details.win_state.rows or {}) do
    if r.type == 'detail_comment' then
      found = r
    end
  end
  h.assert_truthy(found, 'the stored comment reached the rendered rows')
  h.assert_truthy(found.text:match('from the store'), found.text)
  review.clear()
end)

-- The popup is stubbed: this test is about which anchor gets built from the row
-- under the cursor, not about Neovim's floating windows.
h.test('details: C anchors a comment to the row under the cursor', function()
  reset()
  local review = require('gitbutler.review')
  review.clear()
  h.after(function()
    review.clear()
  end)

  local float = require('gitbutler.ui.float')
  local orig_input, opts_seen = float.input, nil
  h.after(function()
    float.input = orig_input
  end)
  ---@diagnostic disable-next-line: duplicate-set-field
  float.input = function(opts)
    opts_seen = opts
    return 0, 0
  end

  local orig_cursor = details._cursor_row
  h.after(function()
    details._cursor_row = orig_cursor
  end)
  details.win_state.entity = { cli_id = 'aa', scope = 'commit', ref = 'deadbeef', subject = 'fix: a thing' }
  details.win_state.rows = {
    { type = 'detail_hunk', data = {} },
    {
      type = 'detail_line',
      data = { path = 'src/auth.lua', side = 'new', line = 2, raw = "+local jwt = require('jwt')" },
    },
  }
  ---@diagnostic disable-next-line: duplicate-set-field
  details._cursor_row = function()
    return 2
  end

  details._comment_line()
  h.assert_truthy(opts_seen, 'the popup opened')
  h.assert_truthy(opts_seen.allow_empty, 'an empty submit has to reach on_submit to delete')

  opts_seen.on_submit('needs a guard')
  h.assert_eq(1, #review.comments)
  local c = review.comments[1]
  h.assert_eq('commit', c.scope)
  h.assert_eq('deadbeef', c.ref)
  h.assert_eq('fix: a thing', c.subject)
  h.assert_eq('src/auth.lua', c.path)
  h.assert_eq('new', c.side)
  h.assert_eq(2, c.line)
  h.assert_eq("+local jwt = require('jwt')", c.captured)
  h.assert_eq('needs a guard', c.text)
end)

-- Clearing the popup is how a comment is deleted; there is no second key for it.
h.test('details: an empty submit deletes the comment', function()
  reset()
  local review = require('gitbutler.review')
  review.clear()
  h.after(function()
    review.clear()
  end)
  local anchor = {
    scope = 'commit',
    ref = 'deadbeef',
    path = 'src/auth.lua',
    side = 'new',
    line = 2,
    captured = "+local jwt = require('jwt')",
  }
  review.set(anchor, 'a note')

  local float = require('gitbutler.ui.float')
  local orig_input, opts_seen = float.input, nil
  h.after(function()
    float.input = orig_input
  end)
  ---@diagnostic disable-next-line: duplicate-set-field
  float.input = function(opts)
    opts_seen = opts
    return 0, 0
  end

  local orig_cursor = details._cursor_row
  h.after(function()
    details._cursor_row = orig_cursor
  end)
  details.win_state.entity = { cli_id = 'aa', scope = 'commit', ref = 'deadbeef' }
  details.win_state.rows = {
    {
      type = 'detail_line',
      data = { path = 'src/auth.lua', side = 'new', line = 2, raw = "+local jwt = require('jwt')" },
    },
  }
  ---@diagnostic disable-next-line: duplicate-set-field
  details._cursor_row = function()
    return 1
  end

  details._comment_line()
  h.assert_eq('a note', table.concat(opts_seen.content or {}, '\n'), 'the popup opens pre-filled for an edit')
  opts_seen.on_submit('')
  h.assert_eq(0, #review.comments)
end)

-- Hunk headers, file headers, closing rows and landed-history `git show` rows
-- all name no line, so C has nothing to attach to.
h.test('details: C on a row that is not a diff line warns and stores nothing', function()
  reset()
  local review = require('gitbutler.review')
  review.clear()
  local float = require('gitbutler.ui.float')
  local orig_input, opened = float.input, false
  h.after(function()
    float.input = orig_input
  end)
  ---@diagnostic disable-next-line: duplicate-set-field
  float.input = function()
    opened = true
    return 0, 0
  end

  local orig_cursor = details._cursor_row
  h.after(function()
    details._cursor_row = orig_cursor
  end)
  details.win_state.entity = { cli_id = 'aa', scope = 'commit', ref = 'deadbeef' }
  details.win_state.rows = {
    { type = 'detail_hunk', data = { path = 'src/auth.lua' } },
    { type = 'commit_show' },
  }
  for _, at in ipairs({ 1, 2 }) do
    ---@diagnostic disable-next-line: duplicate-set-field
    details._cursor_row = function()
      return at
    end
    details._comment_line()
  end

  h.assert_falsy(opened, 'the popup never opened')
  h.assert_eq(0, #review.comments)
end)

-- The whole point of the feature: one keypress produces the text that gets
-- pasted, and the store is empty afterwards so the next review starts clean.
h.test('details: Y writes the blob to both registers and empties the store', function()
  reset()
  local review = require('gitbutler.review')
  h.after(review.clear)
  h.after(function()
    details.win_state.status_buf = nil
  end)
  local orig_unnamed = vim.fn.getreg('"')
  local orig_plus = vim.fn.getreg('+')
  h.after(function()
    vim.fn.setreg('"', orig_unnamed)
    vim.fn.setreg('+', orig_plus)
  end)

  -- `+` is the system clipboard, and headless Linux CI has no provider for it:
  -- `setreg('+', …)` is a no-op there and `getreg('+')` reads back empty. What
  -- the pane is responsible for is writing both registers — whether the OS can
  -- hold the second one is not this test's business. So record the writes.
  local wrote = {}
  local orig_setreg = vim.fn.setreg
  h.after(function()
    vim.fn.setreg = orig_setreg
  end)
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.fn.setreg = function(name, value)
    wrote[name] = value
    return orig_setreg(name, value)
  end

  review.clear()
  review.set({
    scope = 'commit',
    ref = 'deadbeef',
    subject = 'fix: a thing',
    path = 'src/auth.lua',
    side = 'new',
    line = 2,
    captured = "+local jwt = require('jwt')",
  }, 'needs a guard')

  details.win_state.status_buf = {
    get_cursor_branch = function()
      return { name = 'fix/graph-tab-details' }
    end,
  }

  details._yank_comments()

  local expected = table.concat({
    'Review — 1 comment on fix/graph-tab-details',
    '',
    'src/auth.lua:2  (deadbee · fix: a thing · added)',
    "  +local jwt = require('jwt')",
    '  > needs a guard',
  }, '\n')
  h.assert_eq(expected, vim.fn.getreg('"'))
  h.assert_eq(expected, wrote['+'])
  h.assert_eq(expected, wrote['"'])
  h.assert_eq(0, #review.comments, 'the store is drained')
end)

-- Yanking nothing must not clobber whatever the user already had in their
-- registers.
h.test('details: Y with no comments warns and leaves the registers alone', function()
  reset()
  local review = require('gitbutler.review')
  h.after(review.clear)
  h.after(function()
    details.win_state.status_buf = nil
  end)
  local orig_unnamed = vim.fn.getreg('"')
  local orig_plus = vim.fn.getreg('+')
  h.after(function()
    vim.fn.setreg('"', orig_unnamed)
    vim.fn.setreg('+', orig_plus)
  end)

  review.clear()
  vim.fn.setreg('"', 'previous clipboard contents')

  details.win_state.status_buf = nil
  details._yank_comments()

  h.assert_eq('previous clipboard contents', vim.fn.getreg('"'))
end)

-- The pane may be showing a diff with no lane under the status cursor. The blob
-- still has to be well-formed.
h.test('details: Y without a branch under the cursor drops the branch clause', function()
  reset()
  local review = require('gitbutler.review')
  h.after(review.clear)
  h.after(function()
    details.win_state.status_buf = nil
  end)
  local orig_unnamed = vim.fn.getreg('"')
  local orig_plus = vim.fn.getreg('+')
  h.after(function()
    vim.fn.setreg('"', orig_unnamed)
    vim.fn.setreg('+', orig_plus)
  end)

  review.clear()
  review.set({
    scope = 'uncommitted',
    ref = nil,
    path = 'src/app.rs',
    side = 'new',
    line = 4,
    captured = '+    let x = 1;',
  }, 'name this')

  details.win_state.status_buf = nil
  details._yank_comments()

  h.assert_truthy(vim.fn.getreg('"'):match('^Review — 1 comment\n'), vim.fn.getreg('"'))
end)

-- The pane was a raw scratch buffer, so it had no hint line and `?` in it
-- showed the status view's help. Making it a Buffer with its own view name is
-- what fixes both. `_buffer()` is nil until the pane is open, so this needs a
-- real window like every other window-dependent test in this file.
h.test('details: the pane is a Buffer with its own view name', function()
  reset()
  local sb = mock_status_buf()
  details.open(sb)
  local buf = details._buffer()
  h.assert_truthy(buf, 'the pane owns a Buffer')
  h.assert_eq('details', buf.view)
  details.close()
  pcall(vim.api.nvim_buf_delete, sb.buf, { force = true })
end)

-- Every key the pane binds must resolve through the registry, or the hint line
-- and the help float describe a different set of keys from the ones that work.
-- Native entries (j/k/g/G) carry no action and are deliberately unbound, so
-- they are skipped here rather than asserted on.
h.test('details: every registry action for the pane has a handler', function()
  reset()
  local sb = mock_status_buf()
  details.open(sb)
  local keys = require('gitbutler.keys')
  local buf = details._buffer()
  for _, spec in ipairs(keys.resolved('details')) do
    if spec.action then
      h.assert_truthy(type(buf.keymaps[spec.action]) == 'function', 'details action has a handler: ' .. spec.action)
    end
  end
  details.close()
  pcall(vim.api.nvim_buf_delete, sb.buf, { force = true })
end)

-- The pane had no hint line at all. This is the user-visible half of the fix.
--
-- `text:match('C')` (a bare letter) would pass even against the buggy
-- `hints.status` fallback, since its own default entry is `<C-r> Refresh` —
-- both contain a capital C/R. Matching the desc word itself is what actually
-- discriminates the registry-derived line from the status one.
h.test('details: the pane renders a hint line of its own keys', function()
  reset()
  local hints = require('gitbutler.ui.hints')
  local text = hints.for_context('details', nil, false)
  h.assert_truthy(text:match('comment'), 'the comment key is advertised: ' .. text)
  h.assert_falsy(text:match('amend mode'), 'status-view entries do not leak in: ' .. text)
end)

-- The CI view has no entry in `hints`, so it silently showed status hints —
-- the same bug as the pane, in a second place.
h.test('details: a view with no hint table falls back to its own registry keys', function()
  local hints = require('gitbutler.ui.hints')
  local text = hints.for_context('ci', nil, false)
  h.assert_truthy(text:match('rerun'), 'CI keys, not status keys: ' .. text)
end)

-- `hints.for_context`'s plain text is unclipped by design — fine for a unit
-- test, but `details` alone has 27 registry entries, and at the pane's real
-- (narrower) width that text just gets cut off wherever the window ends. A
-- naive cut left only navigation keys visible and dropped `?` and every verb
-- past the first few, which defeats the point of this whole fix. So
-- `update_hint` routes a registry-derived line through the same width-aware
-- hotbar `status` already uses, with `?` and the pane's own less-obvious
-- verbs (registry entries carrying their own `help` string) prioritised to
-- survive truncation. This asserts the outcome at a realistic pane width,
-- not just that the underlying text contains the word somewhere.
h.test('details: at a pane-typical width the hint line keeps ? and a verb', function()
  reset()
  local buffer_mod = require('gitbutler.ui.buffer')
  local buf = buffer_mod.Buffer.new()
  buf.view = 'details'
  buf.buf = vim.api.nvim_create_buf(false, true)
  local orig_columns = vim.o.columns
  vim.o.columns = 240 -- headroom so the split can actually be narrowed to 60
  vim.cmd('vsplit')
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf.buf)
  h.after(function()
    vim.o.columns = orig_columns
    buf:close()
  end)
  buf:attach(win)
  vim.api.nvim_win_set_width(win, 60)

  buf:update_hint()

  local text = vim.api.nvim_buf_get_lines(buf.hint_buf, 0, -1, false)[1]
  -- `nvim_buf_get_lines` reads buffer data, not the visually clipped
  -- display — `wrap = false` only hides the overflow on screen, it does not
  -- shorten the line's own text. So this line alone would pass even against
  -- the untruncated `hints.for_context` route (300 chars, contains every
  -- word regardless of width) and would not actually prove truncation
  -- happened. The length check below is what proves it: the untruncated
  -- registry text is 300 bytes, so a genuinely width-bounded line must be
  -- far shorter.
  local untruncated = require('gitbutler.ui.hints').for_context('details', nil, false)
  h.assert_truthy(#text < #untruncated / 2, 'the line is data-truncated, not just visually clipped: ' .. text)
  h.assert_truthy(text:match('%?'), 'help survives truncation: ' .. text)
  h.assert_truthy(text:match('comment') or text:match('yank'), 'a pane verb survives truncation: ' .. text)
end)

-- The routing decision must not change what `status` renders. It already
-- used the mode hotbar unconditionally, on every row type, both before and
-- after this change — `hints.status`'s curated per-row-type table (`commit`,
-- `merge_base`, …) is for other `hints.for_context` callers, not the live
-- status buffer. This pins that the refactor did not quietly move status
-- onto the registry-hotbar path or the plain-text path.
h.test('status: the hint line is still exactly the mode hotbar, unaffected by the routing change', function()
  reset()
  local buffer_mod = require('gitbutler.ui.buffer')
  local hotbar = require('gitbutler.ui.hotbar')
  local modes = require('gitbutler.ui.modes')
  local buf = buffer_mod.Buffer.new()
  buf.view = 'status'
  buf.buf = vim.api.nvim_create_buf(false, true)
  buf.lines = { { type = 'commit', text = 'commit row' } } -- a row hints.status.commit has a curated entry for
  vim.cmd('vsplit')
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf.buf)
  h.after(function()
    buf:close()
  end)
  buf:attach(win)
  vim.api.nvim_win_set_cursor(win, { 1, 0 })

  buf:update_hint()

  local mode = modes.current()
  local expected =
    hotbar.build(mode, hotbar.items_for(mode), vim.api.nvim_win_get_width(win), hotbar.pill_hl(mode)).text
  local actual = vim.api.nvim_buf_get_lines(buf.hint_buf, 0, -1, false)[1]
  h.assert_eq(expected, actual, 'status hint line byte-for-byte unchanged')
end)

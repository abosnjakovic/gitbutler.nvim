-- Simple test runner. Run with:
--   nvim --clean --headless -u tests/minimal_init.lua -l tests/run.lua

local pass = 0
local fail = 0
local errors = {}

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    pass = pass + 1
    print('  PASS  ' .. name)
  else
    fail = fail + 1
    table.insert(errors, { name = name, err = err })
    print('  FAIL  ' .. name)
    print('        ' .. tostring(err))
  end
end

local function assert_eq(expected, actual, msg)
  if expected ~= actual then
    error((msg or '') .. ' expected: ' .. vim.inspect(expected) .. ' got: ' .. vim.inspect(actual), 2)
  end
end

local function assert_truthy(val, msg)
  if not val then
    error((msg or 'expected truthy') .. ' got: ' .. vim.inspect(val), 2)
  end
end

local function assert_falsy(val, msg)
  if val then
    error((msg or 'expected falsy') .. ' got: ' .. vim.inspect(val), 2)
  end
end

local function assert_type(expected_type, val, msg)
  if type(val) ~= expected_type then
    error((msg or '') .. ' expected type ' .. expected_type .. ' got ' .. type(val), 2)
  end
end

-- ── Fixtures ──────────────────────────────────────────────

local fixtures = require('tests.gitbutler.fixtures')

-- ── Status line building ──────────────────────────────────

print('\n=== Status view tests ===')

local status = require('gitbutler.ui.status')
local cli = require('gitbutler.cli')
local buffer_mod = require('gitbutler.ui.buffer')

local function mock_buffer()
  local buf = buffer_mod.Buffer.new()
  buf.is_folded = function(_, _) return false end
  buf._cursor_row = nil
  return buf
end

local function capture_lines(fixture_data)
  local captured
  local original = cli.status
  cli.status = function(callback) callback(nil, fixture_data) end

  local buf = mock_buffer()
  status.instance = buf
  buf.render = function(_, lines) captured = lines end
  status.refresh()

  cli.status = original
  status.instance = nil
  return captured
end

test('renders branch from stacks', function()
  local lines = capture_lines(fixtures.status_full)
  assert_truthy(lines)

  local branch_line
  for _, l in ipairs(lines) do
    if l.type == 'branch' then branch_line = l; break end
  end

  assert_truthy(branch_line)
  assert_eq('feature-auth', branch_line.data.name)
  assert_eq('GitButlerBranchApplied', branch_line.hl)
end)

test('renders commits with sha and message', function()
  local lines = capture_lines(fixtures.status_full)

  local commit
  for _, l in ipairs(lines) do
    if l.type == 'commit' then commit = l; break end
  end

  assert_truthy(commit)
  assert_eq('c4d75dfd95bf28d3ce1b6dc1a99bb96338aae8fa', commit.data.sha)
  assert_eq('feature-auth', commit.data.branch_name)
  assert_truthy(commit.text:find('c4d75df'), 'short sha in text')
  assert_truthy(commit.text:find('add login endpoint'), 'message in text')
end)

test('renders committed files with cli_id', function()
  local lines = capture_lines(fixtures.status_full)

  local files = {}
  for _, l in ipairs(lines) do
    if l.type == 'committed_file' then table.insert(files, l) end
  end

  assert_eq(2, #files)
  assert_eq('src/auth.lua', files[1].data.path)
  assert_eq('c4:xw', files[1].data.cli_id)
  assert_eq('GitButlerFileAdd', files[1].hl)
end)

test('renders assigned uncommitted changes', function()
  local lines = capture_lines(fixtures.status_full)

  local assigned = {}
  for _, l in ipairs(lines) do
    if l.type == 'file' and l.data and l.data.branch_name then
      table.insert(assigned, l)
    end
  end

  assert_eq(1, #assigned)
  assert_eq('src/pending.lua', assigned[1].data.path)
  assert_eq('ac', assigned[1].data.cli_id)
end)

test('renders unassigned changes with cli_id', function()
  local lines = capture_lines(fixtures.status_full)

  local unassigned = {}
  for _, l in ipairs(lines) do
    if l.type == 'file' and l.data and l.data.unassigned then
      table.insert(unassigned, l)
    end
  end

  assert_eq(2, #unassigned)
  assert_eq('neovim/.config/nvim/plugin/git.lua', unassigned[1].data.path)
  assert_eq('up', unassigned[1].data.cli_id)
  assert_eq('plan.md', unassigned[2].data.path)
end)

test('shows upstream behind count in header', function()
  local lines = capture_lines(fixtures.status_behind)
  assert_truthy(lines[1].text:find('3 behind'), 'behind in header')
end)

test('handles empty workspace', function()
  local lines = capture_lines(fixtures.status_empty)
  assert_truthy(lines)
  assert_truthy(#lines >= 2, 'at least header + help')
end)

test('truncates multiline commit messages', function()
  local lines = capture_lines(fixtures.status_full)

  local commits = {}
  for _, l in ipairs(lines) do
    if l.type == 'commit' then table.insert(commits, l) end
  end

  assert_truthy(#commits >= 2)
  assert_truthy(commits[2].text:find('initial auth setup'))
  assert_falsy(commits[2].text:find('multiline'))
end)

-- ── Branch data tests ─────────────────────────────────────

print('\n=== Branch data tests ===')

test('branch list fixture has correct structure', function()
  local data = fixtures.branch_list
  assert_eq(1, #data.appliedStacks)
  assert_eq('feature-auth', data.appliedStacks[1].heads[1].name)
  assert_eq(1, #data.branches)
  assert_eq('old-experiment', data.branches[1].name)
end)

test('nil commitsAhead is not a number (vim.NIL)', function()
  local head = fixtures.branch_list.appliedStacks[1].heads[1]
  assert_falsy(type(head.commitsAhead) == 'number')
end)

test('numeric commitsAhead is preserved', function()
  local branch = fixtures.branch_list.branches[1]
  assert_type('number', branch.commitsAhead)
  assert_eq(83, branch.commitsAhead)
end)

test('empty branch list has correct structure', function()
  local data = fixtures.branch_list_empty
  assert_eq(0, #data.appliedStacks)
  assert_eq(0, #data.branches)
end)

-- ── Change type display ───────────────────────────────────

print('\n=== Change type display tests ===')

test('added files get A prefix and add highlight', function()
  local lines = capture_lines(fixtures.status_full)
  local added
  for _, l in ipairs(lines) do
    if l.type == 'committed_file' and l.data.change_type == 'added' then
      added = l; break
    end
  end
  assert_truthy(added)
  assert_truthy(added.text:find('^%s*A  '), 'starts with A prefix')
  assert_eq('GitButlerFileAdd', added.hl)
end)

test('modified files get M prefix and mod highlight', function()
  local lines = capture_lines(fixtures.status_full)
  local modified
  for _, l in ipairs(lines) do
    if l.type == 'file' and l.data and l.data.change_type == 'modified' then
      modified = l; break
    end
  end
  assert_truthy(modified)
  assert_truthy(modified.text:find('M  '), 'has M prefix')
  assert_eq('GitButlerFileMod', modified.hl)
end)

-- ── Log view tests ────────────────────────────────────────

print('\n=== Log view tests ===')

local log_mod = require('gitbutler.ui.log')

-- We can't easily test the full open() flow without a window,
-- but we can test the build_lines logic by extracting it.
-- Since build_lines is local, we test through the module's data handling.

test('show_branch fixture has correct structure', function()
  local data = fixtures.show_branch
  assert_eq('feature-auth', data.branch)
  assert_eq(2, #data.commits)
  assert_eq('9331c55fb5b4f279474e60e07f106a9b354f8cad', data.commits[1].sha)
  assert_eq('9331c55fb', data.commits[1].short_sha)
  assert_eq(3, data.commits[1].files_changed)
  assert_eq(3, #data.commits[1].files)
end)

test('show_branch files have stats', function()
  local file = fixtures.show_branch.commits[1].files[1]
  assert_eq('src/auth.lua', file.path)
  assert_eq('added', file.status)
  assert_eq(80, file.insertions)
  assert_eq(0, file.deletions)
end)

test('show_branch_empty has no commits', function()
  assert_eq(0, #fixtures.show_branch_empty.commits)
  assert_eq('empty-branch', fixtures.show_branch_empty.branch)
end)

test('show_branch full_message preserves multiline', function()
  local msg = fixtures.show_branch.commits[1].full_message
  assert_truthy(msg:find('\n'), 'full_message has newline')
  assert_truthy(msg:find('JWT'), 'full_message has body')
end)

-- ── Oplog tests ───────────────────────────────────────────

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
  -- body is vim.NIL — should not be treated as string
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
  -- Test the format_time equivalent logic
  local ts = fixtures.oplog[1].createdAt
  assert_type('number', ts)
  local formatted = os.date('%Y-%m-%d %H:%M', ts)
  assert_truthy(formatted:find('%d%d%d%d%-%d%d%-%d%d'), 'has date format')
end)

-- ── Selection tests ─────────────────────────────────────

print('\n=== Selection tests ===')

test('select_key returns cli_id for file lines', function()
  local buf = mock_buffer()
  local line = { type = 'file', data = { cli_id = 'up', path = 'foo.lua' } }
  assert_eq('up', buf:select_key(line))
end)

test('select_key returns sha for commit lines', function()
  local buf = mock_buffer()
  local line = { type = 'commit', data = { sha = 'abc123' } }
  assert_eq('abc123', buf:select_key(line))
end)

test('select_key returns cli_id for committed_file lines', function()
  local buf = mock_buffer()
  local line = { type = 'committed_file', data = { cli_id = 'c4:xw' } }
  assert_eq('c4:xw', buf:select_key(line))
end)

test('select_key returns nil for non-selectable lines', function()
  local buf = mock_buffer()
  assert_eq(nil, buf:select_key({ type = 'blank', data = nil }))
  assert_eq(nil, buf:select_key({ type = 'section_header', data = {} }))
  assert_eq(nil, buf:select_key({ type = 'branch', data = { name = 'main' } }))
  assert_eq(nil, buf:select_key({ type = 'help', data = nil }))
  assert_eq(nil, buf:select_key({ type = 'recent_commit', data = { sha = 'abc' } }))
end)

test('toggle_select adds and removes from selection', function()
  local buf = mock_buffer()
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
  local buf = mock_buffer()
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
  local buf = mock_buffer()
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
  local buf = mock_buffer()
  buf.selected = { a1 = true, b2 = true }
  buf:clear_selection()
  assert_eq(0, vim.tbl_count(buf.selected))
end)

test('toggle_select on non-selectable line is a no-op', function()
  local buf = mock_buffer()
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

-- ── Action multi-select tests ───────────────────────────

print('\n=== Action multi-select tests ===')

test('get_selected_lines falls back to cursor line when no selection', function()
  local buf = mock_buffer()
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

  -- First render
  buf:render(lines)
  assert_truthy(buf:is_selected(lines[1]))

  -- Second render (simulates refresh)
  buf:render(lines)
  assert_truthy(buf:is_selected(lines[1]), 'selection preserved after re-render')

  local rendered = vim.api.nvim_buf_get_lines(buf.buf, 0, -1, false)
  assert_truthy(rendered[1]:find('●'), 'marker still shown after re-render')

  vim.api.nvim_buf_delete(buf.buf, { force = true })
end)

print('\n=== Action tests ===')

local actions = require('gitbutler.actions')

test('actions.toggle_select moves cursor down if successful', function()
  local buf = mock_buffer()
  buf.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf.buf, 0, -1, false, { "line 1", "line 2", "line 3" })
  
  buf.win = vim.api.nvim_open_win(buf.buf, true, {
    relative = 'editor', width = 10, height = 10, row = 0, col = 0
  })
  
  vim.api.nvim_win_set_cursor(buf.win, { 1, 0 })
  
  buf.toggle_select = function() return true end
  buf.render = function() end
  buf.lines = { "dummy" }
  
  actions.toggle_select(buf)
  
  local cursor = vim.api.nvim_win_get_cursor(buf.win)
  assert_eq(2, cursor[1], 'cursor should move to line 2')
  
  vim.api.nvim_win_close(buf.win, true)
  vim.api.nvim_buf_delete(buf.buf, { force = true })
end)

test('actions.push does a pull first', function()
  local pull_called = false
  local push_called = false
  
  local original_pull = cli.pull
  local original_push = cli.push
  
  cli.pull = function(cb)
    pull_called = true
    cb(nil, "pulled")
  end
  
  cli.push = function(branch_name, cb)
    assert_truthy(pull_called, 'pull must be called before push')
    push_called = true
    assert_eq("test-branch", branch_name)
    cb(nil, "pushed")
  end
  
  local buf = mock_buffer()
  buf.get_cursor_branch = function() return { name = "test-branch" } end
  
  local notify_called = false
  local original_notify = vim.notify
  vim.notify = function() notify_called = true end
  
  actions.push(buf)
  
  assert_truthy(pull_called)
  assert_truthy(push_called)
  
  cli.pull = original_pull
  cli.push = original_push
  vim.notify = original_notify
end)

test('actions.push_all does a pull first', function()
  local pull_called = false
  local push_called = false
  
  local original_pull = cli.pull
  local original_push = cli.push
  
  cli.pull = function(cb)
    pull_called = true
    cb(nil, "pulled")
  end
  
  cli.push = function(branch_name, cb)
    assert_truthy(pull_called, 'pull must be called before push_all')
    push_called = true
    assert_eq(nil, branch_name)
    cb(nil, "pushed")
  end
  
  local buf = mock_buffer()
  
  local original_notify = vim.notify
  vim.notify = function() end
  
  actions.push_all(buf)
  
  assert_truthy(pull_called)
  assert_truthy(push_called)
  
  cli.pull = original_pull
  cli.push = original_push
  vim.notify = original_notify
end)

-- ── Timeline view tests ─────────────────────────────────

print('\n=== Timeline view tests ===')

local timeline = require('gitbutler.ui.timeline')

test('parse_git_log parses structured git log output', function()
  local raw = table.concat({
    'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2|a1b2c3d|adam|2026-04-08|origin/main, main|Fix auth bug',
    'f4e5d6c7a8b9f4e5d6c7a8b9f4e5d6c7a8b9f4e5|f4e5d6c|sarah|2026-04-08|feat/ui|Update sidebar',
    '8c9d0e1f2a3b8c9d0e1f2a3b8c9d0e1f2a3b8c9d|8c9d0e1|adam|2026-04-07||Add endpoint',
  }, '\n')

  local commits = timeline.parse_git_log(raw)
  assert_eq(3, #commits)
  assert_eq('a1b2c3d', commits[1].short_sha)
  assert_eq('adam', commits[1].author)
  assert_eq('2026-04-08', commits[1].date)
  assert_eq('origin/main, main', commits[1].refs)
  assert_eq('Fix auth bug', commits[1].message)
  assert_eq('', commits[3].refs)
end)

test('parse_git_log handles empty input', function()
  local commits = timeline.parse_git_log('')
  assert_eq(0, #commits)
end)

test('parse_git_log handles message with pipe characters', function()
  local raw = 'abc123abc123abc123abc123abc123abc123abc12345|abc1234|adam|2026-04-08|main|Fix foo|bar baz'
  local commits = timeline.parse_git_log(raw)
  assert_eq(1, #commits)
  assert_eq('Fix foo|bar baz', commits[1].message)
end)

test('parse_diff_tree parses stat output', function()
  local raw = table.concat({
    ' src/auth.lua | 15 ++++++++++++---',
    ' src/token.lua | 45 +++++++++++++++++++++++++++++++++++++++++++++',
    ' 2 files changed, 57 insertions(+), 3 deletions(-)',
  }, '\n')

  local files = timeline.parse_diff_tree(raw)
  assert_eq(2, #files)
  assert_eq('src/auth.lua', files[1].path)
  assert_eq('src/token.lua', files[2].path)
end)

test('parse_diff_tree handles empty output', function()
  local files = timeline.parse_diff_tree('')
  assert_eq(0, #files)
end)

-- ── Summary ───────────────────────────────────────────────

print(string.format('\n%d passed, %d failed\n', pass, fail))
if fail > 0 then
  vim.cmd('cquit 1')
else
  vim.cmd('qall')
end

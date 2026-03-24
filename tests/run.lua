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

-- ── Summary ───────────────────────────────────────────────

print(string.format('\n%d passed, %d failed\n', pass, fail))
if fail > 0 then
  vim.cmd('cquit 1')
else
  vim.cmd('qall')
end

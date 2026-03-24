local fixtures = require('tests.gitbutler.fixtures')

-- We need to test build_lines without opening a real buffer.
-- Extract the build_lines logic by requiring status and using a mock buffer.
local buffer_mod = require('gitbutler.ui.buffer')

---Create a mock buffer that tracks fold state without needing a real nvim window.
local function mock_buffer()
  local buf = buffer_mod.Buffer.new()
  -- Override methods that need a window
  buf.is_folded = function(_, fold_id)
    return buf.fold_state[fold_id] or false
  end
  return buf
end

-- We need access to build_lines which is local in status.lua.
-- Instead, test through the public render path by capturing what render() receives.
-- We'll call the module's internal logic by requiring it and using cli mocking.

describe('status view', function()
  local status = require('gitbutler.ui.status')
  local cli = require('gitbutler.cli')

  -- Mock cli.status to return fixture data
  local original_status = cli.status

  after_each(function()
    cli.status = original_status
    status.close()
  end)

  it('renders branches from stacks with correct line types', function()
    local captured_lines

    cli.status = function(callback)
      callback(nil, fixtures.status_full)
    end

    -- Create instance and capture rendered lines
    local buf = mock_buffer()
    status.instance = buf
    buf.render = function(_, lines)
      captured_lines = lines
    end

    status.refresh()

    assert.is_not_nil(captured_lines)
    assert(#captured_lines > 0, 'expected lines to be rendered')

    -- First real content should be branch header
    local branch_line = captured_lines[3] -- after header + blank
    assert.equals('branch', branch_line.type)
    assert.equals('feature-auth', branch_line.data.name)
    assert.equals('GitButlerBranchApplied', branch_line.hl)
  end)

  it('renders commits with correct sha and message', function()
    local captured_lines

    cli.status = function(callback)
      callback(nil, fixtures.status_full)
    end

    local buf = mock_buffer()
    status.instance = buf
    buf.render = function(_, lines)
      captured_lines = lines
    end

    status.refresh()

    -- Find first commit line
    local commit_line
    for _, line in ipairs(captured_lines) do
      if line.type == 'commit' then
        commit_line = line
        break
      end
    end

    assert.is_not_nil(commit_line)
    assert.equals('c4d75dfd95bf28d3ce1b6dc1a99bb96338aae8fa', commit_line.data.sha)
    assert.equals('feature-auth', commit_line.data.branch_name)
    -- Text should contain short sha
    assert.is_truthy(commit_line.text:find('c4d75df'))
    assert.is_truthy(commit_line.text:find('add login endpoint'))
  end)

  it('renders committed file changes with cli_id', function()
    local captured_lines

    cli.status = function(callback)
      callback(nil, fixtures.status_full)
    end

    local buf = mock_buffer()
    status.instance = buf
    buf.render = function(_, lines)
      captured_lines = lines
    end

    status.refresh()

    local committed_files = {}
    for _, line in ipairs(captured_lines) do
      if line.type == 'committed_file' then
        table.insert(committed_files, line)
      end
    end

    assert.equals(2, #committed_files)
    assert.equals('src/auth.lua', committed_files[1].data.path)
    assert.equals('c4:xw', committed_files[1].data.cli_id)
    assert.equals('GitButlerFileAdd', committed_files[1].hl)
  end)

  it('renders assigned uncommitted changes', function()
    local captured_lines

    cli.status = function(callback)
      callback(nil, fixtures.status_full)
    end

    local buf = mock_buffer()
    status.instance = buf
    buf.render = function(_, lines)
      captured_lines = lines
    end

    status.refresh()

    -- Find file lines that belong to a branch (not unassigned)
    local assigned_files = {}
    for _, line in ipairs(captured_lines) do
      if line.type == 'file' and line.data and line.data.branch_name then
        table.insert(assigned_files, line)
      end
    end

    assert.equals(1, #assigned_files)
    assert.equals('src/pending.lua', assigned_files[1].data.path)
    assert.equals('ac', assigned_files[1].data.cli_id)
  end)

  it('renders unassigned changes with cli_id', function()
    local captured_lines

    cli.status = function(callback)
      callback(nil, fixtures.status_full)
    end

    local buf = mock_buffer()
    status.instance = buf
    buf.render = function(_, lines)
      captured_lines = lines
    end

    status.refresh()

    local unassigned = {}
    for _, line in ipairs(captured_lines) do
      if line.type == 'file' and line.data and line.data.unassigned then
        table.insert(unassigned, line)
      end
    end

    assert.equals(2, #unassigned)
    assert.equals('neovim/.config/nvim/plugin/git.lua', unassigned[1].data.path)
    assert.equals('up', unassigned[1].data.cli_id)
    assert.equals('plan.md', unassigned[2].data.path)
  end)

  it('shows upstream behind count in header', function()
    local captured_lines

    cli.status = function(callback)
      callback(nil, fixtures.status_behind)
    end

    local buf = mock_buffer()
    status.instance = buf
    buf.render = function(_, lines)
      captured_lines = lines
    end

    status.refresh()

    local header = captured_lines[1]
    assert.is_truthy(header.text:find('3 behind'))
  end)

  it('handles empty workspace', function()
    local captured_lines

    cli.status = function(callback)
      callback(nil, fixtures.status_empty)
    end

    local buf = mock_buffer()
    status.instance = buf
    buf.render = function(_, lines)
      captured_lines = lines
    end

    status.refresh()

    -- Should still render header and help
    assert.is_not_nil(captured_lines)
    assert(#captured_lines >= 2) -- at least header + help
  end)

  it('truncates multiline commit messages to first line', function()
    local captured_lines

    cli.status = function(callback)
      callback(nil, fixtures.status_full)
    end

    local buf = mock_buffer()
    status.instance = buf
    buf.render = function(_, lines)
      captured_lines = lines
    end

    status.refresh()

    -- Find the second commit (has multiline message)
    local commits = {}
    for _, line in ipairs(captured_lines) do
      if line.type == 'commit' then
        table.insert(commits, line)
      end
    end

    assert(#commits >= 2)
    -- Second commit has "initial auth setup\nwith multiline description"
    assert.is_truthy(commits[2].text:find('initial auth setup'))
    assert.is_falsy(commits[2].text:find('multiline'))
  end)
end)

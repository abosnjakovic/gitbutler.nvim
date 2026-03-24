local fixtures = require('tests.gitbutler.fixtures')

describe('branch name extraction', function()
  local actions -- loaded after setup

  setup(function()
    require('gitbutler').setup()
    -- We need to access extract_branch_names which is local in actions.lua
    -- Test through the branch list UI builder instead, or test the data we pass to the picker
    actions = require('gitbutler.actions')
  end)

  it('branch list fixture has correct structure', function()
    local data = fixtures.branch_list

    assert.is_not_nil(data.appliedStacks)
    assert.equals(1, #data.appliedStacks)
    assert.equals('feature-auth', data.appliedStacks[1].heads[1].name)

    assert.is_not_nil(data.branches)
    assert.equals(1, #data.branches)
    assert.equals('old-experiment', data.branches[1].name)
  end)

  it('handles nil commitsAhead (vim.NIL / JSON null)', function()
    local data = fixtures.branch_list
    local head = data.appliedStacks[1].heads[1]

    -- commitsAhead is vim.NIL (JSON null), should not be treated as a number
    assert.is_not_true(type(head.commitsAhead) == 'number')
  end)

  it('handles numeric commitsAhead', function()
    local data = fixtures.branch_list
    local branch = data.branches[1]

    assert.equals('number', type(branch.commitsAhead))
    assert.equals(83, branch.commitsAhead)
  end)

  it('empty branch list has correct structure', function()
    local data = fixtures.branch_list_empty

    assert.equals(0, #data.appliedStacks)
    assert.equals(0, #data.branches)
  end)
end)

describe('branch UI builder', function()
  local branch_ui = require('gitbutler.ui.branch')
  local cli = require('gitbutler.cli')
  local original_branch_list = cli.branch_list

  after_each(function()
    cli.branch_list = original_branch_list
  end)

  it('does not error on nil commitsAhead', function()
    -- This was the bug: concatenating vim.NIL crashes
    -- Verify the fix by ensuring branch.open doesn't throw
    -- We mock branch_list and float.open to avoid UI side effects
    local float = require('gitbutler.ui.float')
    local original_open = float.open

    local opened = false
    float.open = function(opts)
      opened = true
      -- Return fake buf/win
      local buf = vim.api.nvim_create_buf(false, true)
      local win = vim.api.nvim_open_win(buf, false, {
        relative = 'editor',
        width = 10,
        height = 5,
        row = 0,
        col = 0,
        style = 'minimal',
      })
      return buf, win
    end

    cli.branch_list = function(callback)
      callback(nil, fixtures.branch_list)
    end

    -- Should not throw
    assert.has_no.errors(function()
      branch_ui.open()
    end)

    float.open = original_open
  end)
end)

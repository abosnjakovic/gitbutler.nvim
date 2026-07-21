-- Phase 2: rub mode round-trip, jump, Esc chain, undo gating, commit mode.
-- Branch-dependent steps SKIP when the workspace has no applied branch.
local H = require('tests.smoke.harness')
require('gitbutler').setup({ kind = 'current' })

local actions = require('gitbutler.actions')
local cli = require('gitbutler.cli')
local modes = require('gitbutler.ui.modes')
local status = require('gitbutler.ui.status')

status.open()
H.wait_status(status)
local buf = status.instance

-- Baseline (header carries a fold indicator: `╭┄▾ zz [uncommitted]`).
if not buf.lines[1].text:match('zz %[uncommitted%]') then
  H.fail('no uncommitted header: ' .. buf.lines[1].text)
end
H.ok('baseline: graph + normal mode (' .. modes.current() .. ')')

local scratch = 'SMOKE_SCRATCH.txt'
local file_row = H.find_row(buf, 'file', function(l)
  return l.data.path == scratch
end)
local branch_row = H.find_row(buf, 'branch')

-- Rub assign round-trip: rub the scratch file onto a branch, verify via status.
if file_row and branch_row then
  vim.api.nvim_win_set_cursor(buf.win, { file_row, 0 })
  actions.rub_start(buf)
  if modes.current() ~= 'rub' then
    H.fail('rub mode not entered')
  end
  if #vim.api.nvim_buf_get_extmarks(buf.buf, modes.ns, 0, -1, {}) == 0 then
    H.fail('rub mode drew no overlay extmarks')
  end
  local hint = vim.api.nvim_buf_get_lines(buf.hint_buf, 0, 1, false)[1] or ''
  if not hint:match('rub') then
    H.fail('hotbar pill is not rub: ' .. hint)
  end
  H.ok('rub mode: overlays + pill')

  vim.api.nvim_win_set_cursor(buf.win, { branch_row, 0 })
  modes._mode_keys.rub['<CR>'](buf)
  if modes.current() ~= 'normal' then
    H.fail('rub did not exit after confirm')
  end
  local assigned = vim.wait(15000, function()
    for _, stack in ipairs((status.data or {}).stacks or {}) do
      for _, ch in ipairs(stack.assignedChanges or {}) do
        if ch.filePath == scratch then
          return true
        end
      end
    end
    return false
  end, 100)
  if not assigned then
    H.fail('rub assign did not land in but status')
  end
  H.ok('rub confirm: file assigned to a branch via but rub')

  -- Reverse: rub it back to zz.
  H.wait_status(status)
  local arow = H.find_row(buf, 'file', function(l)
    return l.data.path == scratch and l.data.branch_name
  end)
  if arow then
    vim.api.nvim_win_set_cursor(buf.win, { arow, 0 })
    actions.rub_start(buf)
    vim.api.nvim_win_set_cursor(buf.win, { 1, 0 })
    modes._mode_keys.rub['<CR>'](buf)
    local back = vim.wait(15000, function()
      for _, ch in ipairs((status.data or {}).uncommittedChanges or {}) do
        if ch.filePath == scratch then
          return true
        end
      end
      return false
    end, 100)
    if not back then
      H.fail('unassign rub did not land')
    end
    H.ok('rub reverse: file unassigned back to zz')
  end
else
  H.skip('no scratch file + branch pair for the rub round-trip')
end

-- Jump mode to a real cli_id.
H.wait_status(status)
local target_row, target = H.find_row(buf, 'commit', function(l)
  return l.data.cli_id and l.data.cli_id ~= ''
end)
if target then
  local orig = vim.fn.input
  vim.fn.input = function()
    return target.data.cli_id
  end
  actions.jump_to_id(buf)
  vim.fn.input = orig
  if vim.api.nvim_win_get_cursor(buf.win)[1] ~= target_row then
    H.fail('jump did not move to the target row')
  end
  H.ok('jump: / to ' .. target.data.cli_id)
else
  H.skip('no commit with a cli_id for the jump check')
end

-- Esc chain: mark then back() clears the mark.
local frow = H.find_row(buf, 'file')
if frow then
  vim.api.nvim_win_set_cursor(buf.win, { frow, 0 })
  actions.toggle_select(buf)
  actions.back(buf)
  if next(buf.selected) then
    H.fail('Esc chain did not clear marks')
  end
  H.ok('esc chain: marks cleared')
end

-- Undo confirm gating: choosing No must not call the CLI.
local undo_called = false
local orig_undo, orig_select = cli.undo, vim.ui.select
cli.undo = function()
  undo_called = true
end
vim.ui.select = function(_, _, cb)
  cb('No')
end
actions.undo(buf)
vim.ui.select, cli.undo = orig_select, orig_undo
if undo_called then
  H.fail('undo ran despite a No confirmation')
end
H.ok('undo confirm gates the CLI call')

-- Commit mode enter/exit + pill.
if branch_row then
  vim.api.nvim_win_set_cursor(buf.win, { branch_row, 0 })
  actions.commit_mode_start(buf)
  if modes.current() ~= 'commit' then
    H.fail('commit mode not entered')
  end
  local hint = vim.api.nvim_buf_get_lines(buf.hint_buf, 0, 1, false)[1] or ''
  if not hint:match('commit') then
    H.fail('hotbar pill is not commit: ' .. hint)
  end
  modes.back(buf)
  if modes.current() ~= 'normal' then
    H.fail('Esc did not exit commit mode')
  end
  H.ok('commit mode: enter, pill, esc exit')
else
  H.skip('no branch row for the commit-mode check')
end

H.done('SMOKE phase2')

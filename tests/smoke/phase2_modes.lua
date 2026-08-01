-- Phase 2: amend mode round-trip, jump, Esc chain, undo gating, commit mode.
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

-- Amend round-trip: amend the scratch file into a branch tip, then verify via
-- `but status` that it left the uncommitted area. `but amend -t <branch>` needs
-- a tip to amend into, and it refuses to rewrite history that has landed
-- upstream (the plugin never passes --allow-merged), so the target has to be a
-- non-integrated branch that already carries a commit.
local amend_row = H.find_row(buf, 'branch', function(l)
  local b = l.data.branch or {}
  return b.branchStatus ~= 'integrated' and #(b.commits or {}) > 0
end)
if file_row and amend_row then
  vim.api.nvim_win_set_cursor(buf.win, { file_row, 0 })
  actions.amend_start(buf)
  if modes.current() ~= 'amend' then
    H.fail('amend mode not entered')
  end
  if #vim.api.nvim_buf_get_extmarks(buf.buf, modes.ns, 0, -1, {}) == 0 then
    H.fail('amend mode drew no overlay extmarks')
  end
  local hint = vim.api.nvim_buf_get_lines(buf.hint_buf, 0, 1, false)[1] or ''
  if not hint:match('amend') then
    H.fail('hotbar pill is not amend: ' .. hint)
  end
  H.ok('amend mode: overlays + pill')

  vim.api.nvim_win_set_cursor(buf.win, { amend_row, 0 })
  modes._mode_keys.amend['<CR>'](buf)
  if modes.current() ~= 'normal' then
    H.fail('amend did not exit after confirm')
  end
  -- The file was uncommitted a moment ago, so the amend landing means `but
  -- status` no longer lists it as an uncommitted change.
  local landed = vim.wait(15000, function()
    if not status.data then
      return false
    end
    for _, ch in ipairs(status.data.uncommittedChanges or {}) do
      if ch.filePath == scratch then
        return false
      end
    end
    return true
  end, 100)
  if not landed then
    H.fail('amend did not take ' .. scratch .. ' out of the uncommitted area')
  end
  H.ok('amend confirm: file amended into the branch tip via but amend')

  -- Put the workspace back. Amending rewrites a real commit, so unlike the old
  -- assign/unassign round-trip this leaves a trace; `but undo` reverses exactly
  -- the operation we just made and returns the file to `zz`.
  local undo_err, undone
  cli.undo(function(err)
    undo_err, undone = err, true
  end)
  vim.wait(15000, function()
    return undone
  end, 50)
  H.wait_status(status)
  local back = false
  for _, ch in ipairs((status.data or {}).uncommittedChanges or {}) do
    if ch.filePath == scratch then
      back = true
    end
  end
  if not back then
    local why = undo_err and (': ' .. undo_err) or ''
    H.fail('but undo did not put ' .. scratch .. ' back in zz' .. why .. ' — the smoke amend is still committed')
  end
  H.ok('undo: the smoke amend is reverted, file back in zz')
else
  H.skip('no scratch file + non-integrated branch with commits for the amend round-trip')
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

-- Phase 3: details pane — open, follow-the-cursor diff, hunk cursor, mark,
-- copy, rub-from-hunk, committed-diff safety, pane-only close.
-- SKIPs cleanly when the workspace has no scratch file / commit to inspect.
local H = require('tests.smoke.harness')
require('gitbutler').setup({ kind = 'current' })

local details = require('gitbutler.ui.details')
local modes = require('gitbutler.ui.modes')
local status = require('gitbutler.ui.status')

status.open()
H.wait_status(status)
local buf = status.instance

local scratch = 'SMOKE_SCRATCH.txt'
local file_row = H.find_row(buf, 'file', function(l)
  return l.data.path == scratch
end)
if not file_row then
  H.skip('no scratch file row; details pane checks need a worktree diff')
  H.done('SMOKE phase3')
  return
end
vim.api.nvim_win_set_cursor(buf.win, { file_row, 0 })

-- Open the pane; it should load the diff of the row under the cursor.
H.press(buf.buf, 'd')
if not details.is_open() then
  H.fail('pane did not open')
end
if not vim.wait(15000, function()
  return #details.win_state.hunks > 0
end, 50) then
  H.fail('pane never loaded hunks for the file under the cursor')
end
local dbuf = details.win_state.buf
local has_header = false
for _, l in ipairs(vim.api.nvim_buf_get_lines(dbuf, 0, -1, false)) do
  if l:match('@@') then
    has_header = true
  end
end
if not has_header then
  H.fail('no @@ hunk header rendered')
end
H.ok('pane opens and renders a diff (' .. #details.win_state.hunks .. ' hunks)')

-- Focus.
H.press(buf.buf, 'l')
if vim.api.nvim_get_current_win() ~= details.win_state.win then
  H.fail('l did not focus the pane')
end
H.ok('focus: l -> details window')

-- Hunk cursor + selection bar.
H.press(dbuf, 'j')
local bar = 0
for _, l in ipairs(vim.api.nvim_buf_get_lines(dbuf, 0, -1, false)) do
  if l:match('^▌') then
    bar = bar + 1
  end
end
if bar == 0 then
  H.fail('no ▌ selection bar rendered')
end
H.ok('hunk cursor: ▌ bar on ' .. bar .. ' rows')

-- Mark.
H.press(dbuf, '<Space>')
local marked = 0
for _ in pairs(details.win_state.marked) do
  marked = marked + 1
end
if marked ~= 1 then
  H.fail('space did not mark exactly one hunk (got ' .. marked .. ')')
end
H.ok('mark: ✔︎ on the selected hunk')

-- Copy.
H.press(dbuf, 'y')
if not (vim.fn.getreg('"'):match('smoke scratch')) then
  H.fail('copy register missing hunk content: ' .. vim.inspect(vim.fn.getreg('"')))
end
H.ok('copy: register holds the hunk body')

-- Jump-to-code: <CR> on a hunk opens the file at the hunk's line, in a
-- window beside the pane, with the TUI still alive.
local hunk = details.win_state.hunks[details.win_state.selected]
H.press(dbuf, '<CR>')
local editor = require('gitbutler.ui.editor')
if not (editor.win and vim.api.nvim_win_is_valid(editor.win)) then
  H.fail('<CR> did not open an editor window')
end
if vim.api.nvim_get_current_win() ~= editor.win then
  H.fail('<CR> did not focus the editor window')
end
local ebuf = vim.api.nvim_win_get_buf(editor.win)
if not vim.api.nvim_buf_get_name(ebuf):match(scratch) then
  H.fail('editor window is not showing the scratch file')
end
if vim.api.nvim_win_get_cursor(editor.win)[1] ~= hunk.line then
  H.fail('cursor did not land on the hunk line ' .. hunk.line)
end
if not details.is_open() then
  H.fail('jumping to the file closed the pane')
end
H.ok('jump-to-code: <CR> opened ' .. scratch .. ' at line ' .. hunk.line .. ', pane still open')
vim.api.nvim_set_current_win(details.win_state.win)

-- Rub from the hunk -> status-side rub mode with the hunk id.
H.press(dbuf, '<Space>') -- unmark so the source is the selected hunk
local hunk_id = details.win_state.hunks[details.win_state.selected].id
H.press(dbuf, 'r')
if modes.current() ~= 'rub' then
  H.fail('r did not enter rub mode')
end
if modes.state.source.kind ~= 'file' or modes.state.source.ids[1] ~= hunk_id then
  H.fail('rub source is not the hunk id as kind=file')
end
if vim.api.nvim_get_current_win() ~= buf.win then
  H.fail('rub from hunk did not focus the status window')
end
H.ok('rub from hunk: kind=file id=' .. hunk_id)

-- Esc unwinds the mode; the pane survives.
modes.back(buf)
if modes.current() ~= 'normal' or not details.is_open() then
  H.fail('Esc did not leave the mode with the pane still open')
end
H.ok('esc: mode exits, pane survives')

-- Committed diff: navigation works, ops are a safe no-op (no crash).
local commit_row = H.find_row(buf, 'commit')
if commit_row then
  vim.api.nvim_win_set_cursor(buf.win, { commit_row, 0 })
  details.show_for_line(buf.lines[commit_row])
  vim.wait(15000, function()
    return #details.win_state.hunks > 0
  end, 50)
  if not pcall(function()
    H.press(dbuf, '<Space>')
  end) then
    H.fail('space crashed on a committed diff (the guarded regression)')
  end
  H.ok('committed diff: ' .. #details.win_state.hunks .. ' hunks, mark is a safe no-op')
else
  H.skip('no commit row for the committed-diff check')
end

-- q closes only the pane.
H.press(dbuf, 'q')
if details.is_open() then
  H.fail('q did not close the pane')
end
if not (buf.buf and vim.api.nvim_buf_is_valid(buf.buf)) then
  H.fail('q closed the whole view, not just the pane')
end
H.ok('q closes the pane only; the status view survives')

H.done('SMOKE phase3')

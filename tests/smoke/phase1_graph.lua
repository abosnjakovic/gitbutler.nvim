-- Phase 1: graph render, selectable navigation, marks, hotbar.
-- Needs only a GitButler workspace (no applied branch required).
local H = require('tests.smoke.harness')
require('gitbutler').setup({ kind = 'current' })

local actions = require('gitbutler.actions')
local status = require('gitbutler.ui.status')

status.open()
H.wait_status(status)
local buf = status.instance

-- Graph header + merge base.
if not buf.lines[1].text:match('^╭┄') then
  H.fail('first row is not the graph connector: ' .. buf.lines[1].text)
end
H.ok('graph header: ' .. buf.lines[1].text)

local _, last = H.find_row(buf, 'merge_base')
if last then
  H.ok('merge base: ' .. last.text)
else
  H.skip('no merge-base row (empty workspace)')
end

-- Navigation skips non-selectable rows.
vim.api.nvim_win_set_cursor(buf.win, { 1, 0 })
actions.cursor_down(buf)
local row = vim.api.nvim_win_get_cursor(buf.win)[1]
if not buf.lines[row].selectable then
  H.fail('cursor_down landed on a non-selectable row ' .. row)
end
H.ok('nav: cursor_down -> row ' .. row .. ' (' .. buf.lines[row].type .. ')')

actions.goto_bottom(buf)
if not buf.lines[vim.api.nvim_win_get_cursor(buf.win)[1]].selectable then
  H.fail('goto_bottom landed on a non-selectable row')
end
H.ok('nav: goto_bottom lands on a selectable row')

-- Mark a file row if one exists; verify the ✔︎ glyph and homogeneity.
local file_row = H.find_row(buf, 'file')
if file_row then
  vim.api.nvim_win_set_cursor(buf.win, { file_row, 0 })
  actions.toggle_select(buf)
  if not buf.lines[file_row].text:match('✔') then
    H.fail('mark did not render ✔︎: ' .. buf.lines[file_row].text)
  end
  H.ok('mark: ✔︎ on the file row')

  local commit_row = H.find_row(buf, 'commit')
  if commit_row then
    vim.api.nvim_win_set_cursor(buf.win, { commit_row, 0 })
    local before = vim.deepcopy(buf.selected)
    actions.toggle_select(buf)
    if not vim.deep_equal(before, buf.selected) then
      H.fail('homogeneity: a commit mark was accepted while a file was marked')
    end
    H.ok('homogeneity: commit mark rejected while a file is marked')
  end
  vim.api.nvim_win_set_cursor(buf.win, { file_row, 0 })
  actions.toggle_select(buf)
else
  H.skip('no uncommitted file row to mark')
end

-- Hotbar in normal mode.
local hint = vim.api.nvim_buf_get_lines(buf.hint_buf, 0, 1, false)[1] or ''
if not (hint:match('normal') and hint:match('%? help') and hint:match('q quit')) then
  H.fail('hotbar content wrong: ' .. hint)
end
H.ok('hotbar: ' .. hint)

H.done('SMOKE phase1')

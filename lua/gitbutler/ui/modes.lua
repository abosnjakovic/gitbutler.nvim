local M = {}

---@class ModeState
---@field mode 'rub'|'commit'|'move'|'stack'
---@field source? { kind: string, ids: string[], rows: integer[], label: string }
---@field opts table  -- e.g. { above = false }
M.state = nil -- nil == normal mode

function M.current()
  return M.state and M.state.mode or 'normal'
end

---Verb label for rubbing `source_kind` onto `target_kind`; nil = invalid target.
local VERBS = {
  file = { zz = 'unassign', commit = 'amend', branch = 'assign' },
  cfile = { zz = 'uncommit', commit = 'move file', branch = 'uncommit to' },
  commit = { zz = 'undo commit', commit = 'squash', branch = 'move commit' },
  branch = { zz = 'unassign all', commit = 'amend all', branch = 'reassign' },
  zz = { commit = 'amend all', branch = 'assign all' },
}

local KIND = {
  file = 'file',
  committed_file = 'cfile',
  commit = 'commit',
  branch = 'branch',
  uncommitted_header = 'zz',
}

---Verb label for rubbing a `source_type` row onto a `target_type` row; nil = invalid target.
---@param source_type string
---@param target_type string
---@return string?
function M.rub_verb(source_type, target_type)
  local s, t = KIND[source_type], KIND[target_type]
  return s and t and VERBS[s] and VERBS[s][t] or nil
end

---Keys owned by the mode layer. On every transition ALL of these plus the
---normal-map keys are deleted, then the target mode's set is bound.
---Filled in by later tasks (rub/commit/move/stack).
local MODE_KEYS = { rub = {}, commit = {}, move = {}, stack = {} }
M._mode_keys = MODE_KEYS

local NAV_ACTIONS = {
  ['j'] = 'cursor_down',
  ['k'] = 'cursor_up',
  ['<Down>'] = 'cursor_down',
  ['<Up>'] = 'cursor_up',
  ['J'] = 'section_down',
  ['K'] = 'section_up',
  ['<C-d>'] = 'jump_down',
  ['<C-u>'] = 'jump_up',
  ['g'] = 'goto_top',
  ['G'] = 'goto_bottom',
}

---Full rebind of the buffer's normal-mode keymap for `mode`. Deterministic:
---wipes every config-driven status key plus every key any mode binds, then
---(for `normal`) restores the config map, or (for an operation mode) binds
---nav + the mode's own keys + the always-on Esc/?/q trio.
---@param buf GitButlerBuffer
---@param mode string
function M.apply_keymap(buf, mode)
  -- 1) wipe: every normal-map key + every key any mode binds
  for key in pairs(require('gitbutler.config').values.keymaps.status or {}) do
    pcall(vim.keymap.del, 'n', key, { buffer = buf.buf })
  end
  for _, mode_keys in pairs(MODE_KEYS) do
    for key in pairs(mode_keys) do
      pcall(vim.keymap.del, 'n', key, { buffer = buf.buf })
    end
  end

  -- 2) normal mode: restore the config-driven map and stop
  if mode == 'normal' then
    buf:_set_keymaps()
    return
  end

  -- 3) operation mode: nav + mode keys + always Esc/?/q
  local actions = require('gitbutler.actions')
  for key, action in pairs(NAV_ACTIONS) do
    vim.keymap.set('n', key, function()
      actions[action](buf)
    end, { buffer = buf.buf, nowait = true })
  end
  for key, fn in pairs(MODE_KEYS[mode] or {}) do
    vim.keymap.set('n', key, function()
      fn(buf)
    end, { buffer = buf.buf, nowait = true })
  end
  vim.keymap.set('n', '<Esc>', function()
    M.back(buf)
  end, { buffer = buf.buf, nowait = true })
  vim.keymap.set('n', '?', function()
    actions.help(buf)
  end, { buffer = buf.buf, nowait = true })
  vim.keymap.set('n', 'q', function()
    actions.close(buf)
  end, { buffer = buf.buf, nowait = true })
end

---Extmark namespace for mode overlays (source tags, verb pills, dimming).
M.ns = vim.api.nvim_create_namespace('gitbutler-mode')

---CursorMoved hook for the active mode. No-op for now; overlay-bearing modes
---(Task 2+) fill this in to redraw the verb pill under the cursor.
---@param buf GitButlerBuffer
function M._on_cursor_moved(buf) end

---Enter `mode` with the given source/opts. Exits any active mode first (no
---nested modes).
---@param buf GitButlerBuffer
---@param mode string
---@param source? table
---@param opts? table
function M.enter(buf, mode, source, opts)
  if M.state then
    M.exit(buf)
  end

  M.state = { mode = mode, source = source, opts = opts or {} }
  M.apply_keymap(buf, mode)

  if buf.buf and vim.api.nvim_buf_is_valid(buf.buf) then
    vim.api.nvim_buf_clear_namespace(buf.buf, M.ns, 0, -1)
    local group = vim.api.nvim_create_augroup('GitButlerMode', { clear = true })
    vim.api.nvim_create_autocmd('CursorMoved', {
      group = group,
      buffer = buf.buf,
      callback = function()
        M._on_cursor_moved(buf)
      end,
    })
  end

  buf:update_hint()
end

---Leave the active mode: clear state, overlays, augroup, and restore the
---normal-mode keymap.
---@param buf GitButlerBuffer
function M.exit(buf)
  M.state = nil
  M.apply_keymap(buf, 'normal')

  if buf.buf and vim.api.nvim_buf_is_valid(buf.buf) then
    vim.api.nvim_buf_clear_namespace(buf.buf, M.ns, 0, -1)
  end
  pcall(vim.api.nvim_del_augroup_by_name, 'GitButlerMode')

  buf:update_hint()
end

---Esc chain: exit an active mode, else clear an active selection, else no-op.
---@param buf GitButlerBuffer
function M.back(buf)
  if M.state then
    M.exit(buf) -- leave mode, clear overlays, rebind normal map, update hotbar
    return
  end
  if next(buf.selected) then
    buf:clear_selection()
    require('gitbutler.ui.status').rerender()
  end
end

return M

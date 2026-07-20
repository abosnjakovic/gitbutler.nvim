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

---A row is a valid rub target iff the verb table has an entry and it is not a source row.
---@param state ModeState
---@param line GitButlerLine
---@param row integer
---@return boolean
function M.is_rub_target(state, line, row)
  if not line.selectable then
    return false
  end
  for _, r in ipairs(state.source.rows) do
    if r == row then
      return false
    end
  end
  return M.rub_verb(state.source.kind, line.type) ~= nil
end

---A row is a valid commit-mode target iff it is a branch or commit row.
---@param line GitButlerLine
---@return boolean
function M.is_commit_target(line)
  return line.selectable == true and (line.type == 'branch' or line.type == 'commit')
end

---A row is a valid move target iff it is a commit or branch row that is not a
---source row — plus the merge base, but only for a branch source (unstack).
---@param state ModeState
---@param line GitButlerLine
---@param row integer
---@return boolean
function M.is_move_target(state, line, row)
  if not line.selectable then
    return false
  end
  for _, r in ipairs(state.source.rows) do
    if r == row then
      return false
    end
  end
  if state.source.kind == 'branch' then
    -- Branch sources can only stack onto a branch or unstack at the merge
    -- base; `but move <branch> <commit>` is not a documented operation.
    return line.type == 'branch' or line.type == 'merge_base'
  end
  if line.type == 'merge_base' then
    return false
  end
  return line.type == 'commit' or line.type == 'branch'
end

---Anchor table for `but commit --before/--after`. In but's display, --after
---lands above the target and --before lands below it, so the marker position
---(opts.above) maps to --after and the default (below) to --before.
---@param opts { above?: boolean }
---@param cli_id string
---@return { before?: string, after?: string }
function M._commit_anchor(opts, cli_id)
  if opts.above then
    return { after = cli_id }
  end
  return { before = cli_id }
end

---`but move` argument tuple for the current source and a target row.
---@param state ModeState
---@param line GitButlerLine
---@return string src, string target, { after: boolean }? opts
function M._move_args(state, line)
  local src = table.concat(state.source.ids, ',')
  if line.type == 'merge_base' then
    return src, 'zz', nil
  end
  if line.type == 'commit' and state.source.kind == 'commit' then
    -- but's --after lands the source above the target in the display and the
    -- default (--before) below it, so opts.above maps straight to --after.
    return src, line.data.cli_id, { after = state.opts.above }
  end
  return src, line.data.cli_id, nil
end

---Move-mode pill label for a target row.
---@param state ModeState
---@param line GitButlerLine
---@return string
function M._move_pill(state, line)
  if line.type == 'merge_base' then
    return '<< unstack >>'
  end
  if line.type == 'branch' then
    return '<< move to top >>'
  end
  return state.opts.above and '<< move above >>' or '<< move below >>'
end

---`but rub` target id for a row: literal 'zz' for the uncommitted header,
---else the row's cli id.
---@param line GitButlerLine
---@return string?
function M._rub_target_id(line)
  if line.type == 'uncommitted_header' then
    return 'zz'
  end
  return line.data and line.data.cli_id or nil
end

---CursorMoved hook for the active mode: redraw the verb pill (and, in commit
---mode, the virt_lines insert marker) under the cursor.
---@param buf GitButlerBuffer
function M._on_cursor_moved(buf)
  local state = M.state
  if not state then
    return
  end
  if not (buf.buf and vim.api.nvim_buf_is_valid(buf.buf)) then
    return
  end
  if state.pill_id then
    vim.api.nvim_buf_del_extmark(buf.buf, M.ns, state.pill_id)
    state.pill_id = nil
  end
  if state.marker_id then
    vim.api.nvim_buf_del_extmark(buf.buf, M.ns, state.marker_id)
    state.marker_id = nil
  end
  if not (buf.win and vim.api.nvim_win_is_valid(buf.win)) then
    return
  end
  local row = vim.api.nvim_win_get_cursor(buf.win)[1]
  local line = buf.lines and buf.lines[row]
  if not line then
    return
  end

  local pill
  if state.mode == 'rub' then
    if not M.is_rub_target(state, line, row) then
      return
    end
    pill = '<< ' .. M.rub_verb(state.source.kind, line.type) .. ' >>'
  elseif state.mode == 'commit' then
    if not M.is_commit_target(line) then
      return
    end
    pill = '<< commit here >>' .. (state.opts.empty and ' (empty)' or '')
    state.marker_id = vim.api.nvim_buf_set_extmark(buf.buf, M.ns, row - 1, 0, {
      virt_lines = { { { '┊● ', 'GitButlerGraphConnector' }, { '(new commit)', 'GitButlerModeCommit' } } },
      virt_lines_above = state.opts.above == true,
    })
  elseif state.mode == 'move' then
    if not M.is_move_target(state, line, row) then
      return
    end
    pill = M._move_pill(state, line)
  else
    return
  end

  state.pill_id = vim.api.nvim_buf_set_extmark(buf.buf, M.ns, row - 1, 0, {
    virt_text = { { pill, 'GitButlerVerbPill' } },
    virt_text_pos = 'eol',
  })
end

---Shared mode entry hook: install the target filter, draw `<< source >>` tags
---and dimming overlays, and park the cursor on the first valid target.
---@param buf GitButlerBuffer
---@param is_target fun(line: GitButlerLine, row: integer): boolean
---@param source_rows? integer[]
local function setup_mode(buf, is_target, source_rows)
  buf.mode_filter = is_target

  local src = {}
  for _, r in ipairs(source_rows or {}) do
    src[r] = true
  end

  if buf.buf and vim.api.nvim_buf_is_valid(buf.buf) then
    for row, line in ipairs(buf.lines or {}) do
      if src[row] then
        vim.api.nvim_buf_set_extmark(buf.buf, M.ns, row - 1, 0, {
          virt_text = { { '<< source >>', 'GitButlerModeSource' } },
          virt_text_pos = 'eol',
        })
      elseif not is_target(line, row) then
        vim.api.nvim_buf_set_extmark(buf.buf, M.ns, row - 1, 0, {
          line_hl_group = 'GitButlerDimmed',
        })
      end
    end
  end

  local target = require('gitbutler.actions')._next_selectable(buf.lines or {}, 0, 1, 1, buf.mode_filter)
  if target >= 1 and buf.win and vim.api.nvim_win_is_valid(buf.win) then
    vim.api.nvim_win_set_cursor(buf.win, { target, 0 })
  end
  M._on_cursor_moved(buf)
end

---Per-mode entry hooks run by M.enter after state/keymap/augroup are in place.
local SETUP = {
  rub = function(buf)
    setup_mode(buf, function(line, row)
      return M.is_rub_target(M.state, line, row)
    end, M.state.source.rows)
  end,
  commit = function(buf)
    setup_mode(buf, function(line)
      return M.is_commit_target(line)
    end)
  end,
  move = function(buf)
    setup_mode(buf, function(line, row)
      return M.is_move_target(M.state, line, row)
    end, M.state.source.rows)
  end,
}

---Enter rub mode with a captured source.
---@param buf GitButlerBuffer
---@param source { kind: string, ids: string[], rows: integer[], label: string }
function M.enter_rub(buf, source)
  M.enter(buf, 'rub', source)
end

---Confirm the rub: target = cursor row; rub each source id onto it in
---sequence. The mode is exited BEFORE the CLI chain runs so the refresh
---always re-renders normal mode.
---@param buf GitButlerBuffer
function M._rub_confirm(buf)
  local state = M.state
  if not state or state.busy then
    return
  end
  if not (buf.win and vim.api.nvim_win_is_valid(buf.win)) then
    return
  end
  local row = vim.api.nvim_win_get_cursor(buf.win)[1]
  local line = buf.lines and buf.lines[row]
  if not line or not M.is_rub_target(state, line, row) then
    return
  end
  local target_id = M._rub_target_id(line)
  if not target_id then
    vim.notify('gitbutler: target row has no CLI id', vim.log.levels.WARN)
    return
  end

  state.busy = true
  local ids = state.source.ids
  M.exit(buf)

  local cli = require('gitbutler.cli')
  local status = require('gitbutler.ui.status')
  local i = 0
  local function rub_next()
    i = i + 1
    if i > #ids then
      status.refresh()
      return
    end
    cli.rub(ids[i], target_id, function(err)
      if err then
        vim.notify('gitbutler rub: ' .. err, vim.log.levels.ERROR)
        status.refresh()
        return
      end
      rub_next()
    end)
  end
  rub_next()
end

MODE_KEYS.rub['<CR>'] = M._rub_confirm

---Cursor line when it passes `is_target`; nil (and no-op) otherwise.
---@param buf GitButlerBuffer
---@return GitButlerLine?, integer?
local function target_under_cursor(buf, is_target)
  if not (buf.win and vim.api.nvim_win_is_valid(buf.win)) then
    return nil
  end
  local row = vim.api.nvim_win_get_cursor(buf.win)[1]
  local line = buf.lines and buf.lines[row]
  if not line or not is_target(line, row) then
    return nil
  end
  return line, row
end

---Confirm a commit-mode target: exit the mode, collect the message (input
---float, skipped for empty commits), then run the CLI call and refresh.
---@param buf GitButlerBuffer
function M._commit_confirm(buf)
  local state = M.state
  if not state or state.busy then
    return
  end
  local line = target_under_cursor(buf, M.is_commit_target)
  if not line then
    return
  end

  state.busy = true
  local opts = state.opts
  M.exit(buf)

  local cli = require('gitbutler.cli')
  local status = require('gitbutler.ui.status')
  local function do_commit(message)
    local function done(err)
      if err then
        vim.notify('gitbutler commit: ' .. err, vim.log.levels.ERROR)
      end
      status.refresh()
    end
    if line.type == 'branch' then
      cli.commit(line.data.name, message, done)
    else
      cli.commit_at(line.data.branch_name, message, M._commit_anchor(opts, line.data.cli_id), done)
    end
  end

  if opts.empty then
    -- ponytail: `but commit` rejects a missing -m by opening an editor and
    -- `-m ''` acceptance is unverified; a single-space message is the plan's
    -- documented fallback. Swap to '' if the CLI is confirmed to take it.
    do_commit(' ')
    return
  end

  local branch_name = line.type == 'branch' and line.data.name or line.data.branch_name
  require('gitbutler.ui.float').input({
    title = 'Commit to ' .. (branch_name or '?'),
    on_submit = do_commit,
  })
end

MODE_KEYS.commit['<CR>'] = M._commit_confirm
MODE_KEYS.commit['a'] = function(buf)
  if M.state then
    M.state.opts.above = not M.state.opts.above
    M._on_cursor_moved(buf)
  end
end
MODE_KEYS.commit['e'] = function(buf)
  if M.state then
    M.state.opts.empty = not M.state.opts.empty
    M._on_cursor_moved(buf)
  end
end

---Confirm a move-mode target: exit the mode, then one `but move` call with
---comma-joined sources and refresh.
---@param buf GitButlerBuffer
function M._move_confirm(buf)
  local state = M.state
  if not state or state.busy then
    return
  end
  local line = target_under_cursor(buf, function(l, r)
    return M.is_move_target(state, l, r)
  end)
  if not line then
    return
  end

  state.busy = true
  local src, target, move_opts = M._move_args(state, line)
  M.exit(buf)

  local status = require('gitbutler.ui.status')
  require('gitbutler.cli').move(src, target, function(err)
    if err then
      vim.notify('gitbutler move: ' .. err, vim.log.levels.ERROR)
    end
    status.refresh()
  end, move_opts)
end

MODE_KEYS.move['<CR>'] = M._move_confirm
MODE_KEYS.move['a'] = function(buf)
  if M.state then
    M.state.opts.above = not M.state.opts.above
    M._on_cursor_moved(buf)
  end
end

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

  if SETUP[mode] then
    SETUP[mode](buf)
  end

  buf:update_hint()
end

---Leave the active mode: clear state, overlays, augroup, and restore the
---normal-mode keymap.
---@param buf GitButlerBuffer
function M.exit(buf)
  M.state = nil
  buf.mode_filter = nil
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

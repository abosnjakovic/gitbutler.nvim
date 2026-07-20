local buffer_mod = require('gitbutler.ui.buffer')
local cli = require('gitbutler.cli')

local M = {}

---@type GitButlerBuffer?
M.instance = nil

---Per-session aggregate CI cache keyed by stack head branch name.
---Value: { state = 'pass' | 'fail' | 'pending' | 'unknown', sha = string }
---Invalidated when the cached sha mismatches the current head sha.
M._ci_cache = M._ci_cache or {}

---Map an aggregate state to a single suffix glyph + highlight.
---@param state? string
---@return string glyph
---@return string? highlight
local function aggregate_glyph(state)
  if state == 'pass' then
    return '✓', 'GitButlerCIPass'
  elseif state == 'fail' then
    return '✗', 'GitButlerCIFail'
  elseif state == 'pending' then
    return '◐', 'GitButlerCIRunning'
  end
  return '', nil
end

---Aggregate adapter `check[]` results into a single state.
---fail > pending > pass.
---@param checks table[]
---@return string state
local function aggregate_state(checks)
  local has_fail, has_pending, has_pass = false, false, false
  for _, c in ipairs(checks) do
    if c.status == 'in_progress' or c.status == 'queued' then
      has_pending = true
    elseif c.status == 'completed' then
      if c.conclusion == 'success' then
        has_pass = true
      else
        has_fail = true
      end
    end
  end
  if has_fail then
    return 'fail'
  elseif has_pending then
    return 'pending'
  elseif has_pass then
    return 'pass'
  end
  return 'unknown'
end

---Kick off background CI fetches for any stack head with a PR whose
---aggregate isn't in cache (or whose sha has moved). On completion,
---re-render the status buffer so the new glyph appears.
---@param data table Decoded `but status --json` payload
local function kick_off_ci_fetches(data)
  local forge_ok, forge = pcall(require, 'gitbutler.forge')
  if not forge_ok then
    return
  end
  local adapter = forge.detect_from_remote and forge.detect_from_remote() or nil
  if not adapter or not adapter.list_checks then
    return
  end

  for _, stack in ipairs(data.stacks or {}) do
    local head = stack.branches and stack.branches[1] or nil
    if head and head.name and head.reviewId and head.reviewId ~= vim.NIL then
      local head_sha = (head.commits and head.commits[1] and head.commits[1].commitId) or ''
      local cached = M._ci_cache[head.name]
      if not cached or cached.sha ~= head_sha then
        -- Mark as in-flight (state=pending, sha=head_sha) so concurrent renders don't refetch.
        M._ci_cache[head.name] = { state = 'pending', sha = head_sha, in_flight = true }
        adapter.list_checks(head.name, function(err, checks)
          if err or not checks then
            -- Leave the placeholder so we don't hammer a failing endpoint.
            M._ci_cache[head.name].in_flight = false
            return
          end
          M._ci_cache[head.name] = { state = aggregate_state(checks), sha = head_sha }
          -- Only the cache changed; rebuild rows from cached data so the new
          -- glyph appears without another `but status` subprocess.
          M.rerender()
        end)
      end
    end
  end
end

---Look up the cached CI aggregate glyph for a stack. All branches in a
---stack share the head's PR, so all rows in the stack get the same glyph.
---@param stack table
---@return string glyph
---@return string? highlight
local function stack_ci_suffix(stack)
  local head = stack.branches and stack.branches[1] or nil
  if not head or not head.name then
    return '', nil
  end
  local cached = M._ci_cache[head.name]
  if not cached or not cached.state or cached.state == 'unknown' then
    return '', nil
  end
  return aggregate_glyph(cached.state)
end

---Map a branch.ci object from `but status --json` to a display glyph + highlight group.
---@param ci? { status?: string, conclusion?: string }
---@return string glyph
---@return string? highlight
function M.ci_glyph(ci)
  if ci == nil or ci == vim.NIL then
    return '', nil
  end
  local status_val = ci.status
  if status_val == 'queued' then
    return '○', 'GitButlerCIQueued'
  elseif status_val == 'in_progress' then
    return '◐', 'GitButlerCIRunning'
  elseif status_val == 'completed' then
    local c = ci.conclusion
    if c == 'success' then
      return '✓', 'GitButlerCIPass'
    elseif c == 'failure' or c == 'cancelled' or c == 'timed_out' then
      return '✗', 'GitButlerCIFail'
    end
  end
  return '?', 'GitButlerCIUnknown'
end

local graph = require('gitbutler.ui.graph')

---Last decoded `but status` payload; lets marks/folds re-render without a CLI call.
M.data = nil

---Suffix pieces appended to a branch header row: per-branch CI glyph,
---review id, stack-aggregate CI glyph.
---@return {[1]:string,[2]:string?}[]
local function branch_suffix(stack, branch)
  local out = {}
  local glyph, hl = M.ci_glyph(branch.ci)
  if glyph ~= '' then
    table.insert(out, { ' ' .. glyph, hl })
  end
  if branch.reviewId and branch.reviewId ~= vim.NIL then
    table.insert(out, { ' #' .. tostring(branch.reviewId), 'GitButlerHelp' })
  end
  local agg, agg_hl = stack_ci_suffix(stack)
  if agg ~= '' then
    table.insert(out, { '  ' .. agg, agg_hl })
  end
  return out
end

---Re-render from cached data (marks, folds) without refetching.
function M.rerender()
  if not M.instance or not M.data then
    return
  end
  -- A rerender while an operation mode is active (async CI callback, late
  -- action callback) would wipe the rows the mode's overlays and source rows
  -- point at. The workspace changed under the mode — bail out of it first.
  local modes = require('gitbutler.ui.modes')
  if modes.current() ~= 'normal' then
    modes.exit(M.instance)
  end
  local buf = M.instance
  buf:render(graph.build(M.data, {
    selected = buf.selected,
    fold_state = buf.fold_state,
    file_lists = buf.file_lists,
    show_all_files = buf.show_all_files,
    branch_suffix = branch_suffix,
  }))
end

---Open or refresh the status buffer.
function M.open()
  if M.instance then
    M.refresh()
    return
  end

  local buf = buffer_mod.Buffer.new()
  buf.view = 'status'
  M.instance = buf

  local actions = require('gitbutler.actions')
  buf:on('open_file', actions.open_file)
  buf:on('stack_start', actions.stack_start)
  buf:on('goto_branch', actions.goto_branch)
  buf:on('absorb', actions.absorb)
  buf:on('commit_mode_start', actions.commit_mode_start)
  buf:on('insert_empty_commit', actions.insert_empty_commit)
  buf:on('move_start', actions.move_start)
  buf:on('describe', actions.describe)
  buf:on('reword_editor', actions.reword_editor)
  buf:on('toggle_file_list', actions.toggle_file_list)
  buf:on('toggle_all_file_lists', actions.toggle_all_file_lists)
  buf:on('back', actions.back)
  buf:on('undo', actions.undo)
  buf:on('redo', actions.redo)
  buf:on('jump_to_id', actions.jump_to_id)
  buf:on('but_command', actions.but_command)
  buf:on('shell_command', actions.shell_command)
  buf:on('copy_selection', actions.copy_selection)
  buf:on('push', actions.push)
  buf:on('push_all', actions.push_all)
  buf:on('pr_create', actions.pr_create)
  buf:on('pr_toggle_draft', actions.pr_toggle_draft)
  buf:on('pull', actions.pull)
  buf:on('close', actions.close)
  buf:on('refresh', function()
    M.refresh()
  end)
  buf:on('branch_new', actions.branch_new)
  buf:on('discard', actions.discard)
  buf:on('toggle_fold', actions.toggle_fold)
  buf:on('toggle_select', actions.toggle_select)
  buf:on('help', actions.help)
  buf:on('branches', actions.branches)
  buf:on('log', actions.log)
  buf:on('oplog', actions.oplog)
  buf:on('timeline', actions.timeline)
  buf:on('direct_to_main', actions.direct_to_main)
  buf:on('ci_open', actions.ci_open)
  buf:on('cursor_down', actions.cursor_down)
  buf:on('cursor_up', actions.cursor_up)
  buf:on('jump_down', actions.jump_down)
  buf:on('jump_up', actions.jump_up)
  buf:on('section_down', actions.section_down)
  buf:on('section_up', actions.section_up)
  buf:on('goto_top', actions.goto_top)
  buf:on('goto_bottom', actions.goto_bottom)
  buf:on('rub_start', actions.rub_start)
  buf:on('rub_reverse', actions.rub_reverse)
  buf:on('details_toggle', actions.details_toggle)
  buf:on('details_toggle_full', actions.details_toggle_full)
  buf:on('details_grow', actions.details_grow)
  buf:on('details_shrink', actions.details_shrink)

  buf:open()
  M.refresh()
end

---Refresh the status buffer with fresh data from `but status`.
function M.refresh()
  if not M.instance then
    return
  end
  cli.status(function(err, data)
    if err then
      vim.notify('gitbutler: ' .. err, vim.log.levels.ERROR)
      return
    end
    -- The view may have been closed while the fetch was in flight.
    if not M.instance then
      return
    end
    if type(data) ~= 'table' then
      vim.notify('gitbutler: unexpected status output', vim.log.levels.WARN)
      return
    end
    M.data = data
    M.rerender()
    -- Kick off async CI aggregate fetches for stack heads with PRs.
    -- The callback will trigger another refresh when results arrive; the
    -- cache prevents refetch loops.
    kick_off_ci_fetches(data)
  end)
end

---Close the status buffer.
function M.close()
  local modes = require('gitbutler.ui.modes')
  if M.instance and modes.current() ~= 'normal' then
    -- Leave the mode before teardown so module-level mode state (keymap
    -- ownership, augroup, mode_filter) doesn't leak past the buffer.
    modes.exit(M.instance)
  end
  -- The details pane hangs off this window; it must not outlive the view.
  require('gitbutler.ui.details').close()
  if M.instance then
    M.instance:close()
    M.instance = nil
  end
  M.data = nil
end

---Toggle the status buffer.
function M.toggle()
  if M.instance and M.instance.buf and vim.api.nvim_buf_is_valid(M.instance.buf) then
    M.close()
  else
    M.instance = nil
    M.open()
  end
end

return M

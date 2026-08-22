---Repository watcher. Two trigger sources — filesystem events under `.git/`
---and focus autocmds — feed one debounced tick, which refreshes whichever
---views are open. Everything except `sync`/`stop` is internal and exists as a
---seam so the decision logic can be driven without a real event loop.

local config = require('gitbutler.config')

local M = {}

---A change is pending and has not been refreshed yet.
M._dirty = false
---At least one trigger in the pending tick came from an autocmd, which is the
---only path allowed to refresh the network-bound CI view.
M._focus = false
---A dispatched refresh has not settled. Prevents a slow `but` on a large repo
---from stacking refreshes behind each other.
M._inflight = false
---@type uv.uv_timer_t?
M._timer = nil
---@type uv.uv_fs_event_t[]
M._handles = {}
---@type integer?
M._augroup = nil

---Arm the debounce timer. Idempotent: a burst of events inside one window
---coalesces into the single already-armed tick.
function M._arm()
  if M._timer then
    return
  end
  local timer = vim.uv.new_timer()
  if not timer then
    return
  end
  M._timer = timer
  timer:start(
    config.values.watch_interval,
    0,
    vim.schedule_wrap(function()
      M._disarm()
      M._tick()
    end)
  )
end

function M._disarm()
  if M._timer then
    if not M._timer:is_closing() then
      M._timer:stop()
      M._timer:close()
    end
    M._timer = nil
  end
end

---@param source 'fs'|'focus'
function M._on_event(source)
  if source == 'focus' then
    M._focus = true
  end
  M._dirty = true
  M._arm()
end

---Whether a refresh right now would be wrong. Modes capture their source set
---by row index, so re-rendering under one retargets it.
---@return boolean
function M._blocked()
  if M._inflight then
    return true
  end
  return require('gitbutler.ui.modes').current() ~= 'normal'
end

---Refresh every open view. `focus` gates the CI view: its data lives on
---GitHub's clock, not the filesystem's, so a local commit is the wrong reason
---to spend a `gh` request.
---@param focus boolean
function M._dispatch(focus)
  local status = require('gitbutler.ui.status')
  local log = require('gitbutler.ui.log')
  local ci = require('gitbutler.ui.ci')

  local pending = 0
  local function done()
    pending = pending - 1
    if pending <= 0 then
      M._inflight = false
    end
  end

  local runs = {}
  if status.instance then
    table.insert(runs, function()
      status.refresh({ quiet = true, done = done })
    end)
  end
  if log.instance and log.instance.branch_name then
    table.insert(runs, function()
      log.refresh(log.instance.branch_name, { quiet = true, done = done })
    end)
  end
  if focus and ci.instance and ci.instance.branch and ci.instance.adapter then
    table.insert(runs, function()
      ci.refresh(ci.instance.branch, ci.instance.adapter, { quiet = true, done = done })
    end)
  end

  if #runs == 0 then
    return
  end
  pending = #runs
  M._inflight = true
  for _, run in ipairs(runs) do
    run()
  end
end

---The debounced body. Blocked ticks re-arm and stay dirty, which is what makes
---"refresh once on leaving a mode" fall out without hooking `modes.exit`.
function M._tick()
  if not M._dirty then
    return
  end
  if M._blocked() then
    M._arm()
    return
  end
  M._dirty = false
  local focus = M._focus
  M._focus = false
  M._dispatch(focus)
end

return M

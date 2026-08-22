local ci = require('gitbutler.ui.ci')
local h = require('tests.gitbutler.helpers')
local log = require('gitbutler.ui.log')
local modes = require('gitbutler.ui.modes')
local status = require('gitbutler.ui.status')
local watch = require('gitbutler.watch')
local test, assert_eq, assert_truthy, assert_falsy = h.test, h.assert_eq, h.assert_truthy, h.assert_falsy

print('\n=== Watch tests ===')

---Run `fn(calls)` with all three views stubbed open, the timer stubbed out,
---and normal mode active. Restores everything, including on failure.
---@param fn fun(calls: { arm: integer, status: integer, log: integer, ci: integer })
local function with_watch(fn)
  local saved = {
    arm = watch._arm,
    status_instance = status.instance,
    status_refresh = status.refresh,
    log_instance = log.instance,
    log_refresh = log.refresh,
    ci_instance = ci.instance,
    ci_refresh = ci.refresh,
    modes_state = modes.state,
  }
  local calls = { arm = 0, status = 0, log = 0, ci = 0 }

  ---@diagnostic disable: duplicate-set-field
  watch._arm = function()
    calls.arm = calls.arm + 1
  end
  status.instance = { buf = 1 }
  log.instance = { buf = 2, branch_name = 'feat/x' }
  ci.instance = { buf = 3, branch = 'feat/x', adapter = {} }
  status.refresh = function(o)
    calls.status = calls.status + 1
    if o and o.done then
      o.done()
    end
  end
  log.refresh = function(_, o)
    calls.log = calls.log + 1
    if o and o.done then
      o.done()
    end
  end
  ci.refresh = function(_, _, o)
    calls.ci = calls.ci + 1
    if o and o.done then
      o.done()
    end
  end
  ---@diagnostic enable: duplicate-set-field
  modes.state = nil
  watch._dirty, watch._focus, watch._inflight = false, false, false

  local ok, err = pcall(fn, calls)

  watch._arm = saved.arm
  status.instance, status.refresh = saved.status_instance, saved.status_refresh
  log.instance, log.refresh = saved.log_instance, saved.log_refresh
  ci.instance, ci.refresh = saved.ci_instance, saved.ci_refresh
  modes.state = saved.modes_state
  watch._dirty, watch._focus, watch._inflight = false, false, false
  if not ok then
    error(err, 0)
  end
end

test('a burst of events inside one window becomes a single refresh', function()
  with_watch(function(calls)
    -- One `but commit` writes index.lock, loose objects, and the write-lock.
    watch._on_event('fs')
    watch._on_event('fs')
    watch._on_event('fs')
    assert_eq(0, calls.status, 'nothing runs until the debounce window closes')
    watch._tick()
    assert_eq(1, calls.status, 'three events, one `but status`')
  end)
end)

test('a tick with nothing pending does nothing', function()
  with_watch(function(calls)
    watch._tick()
    assert_eq(0, calls.status)
  end)
end)

test('an active mode blocks the refresh and keeps the change pending', function()
  with_watch(function(calls)
    -- Amend captures its source rows by index; re-rendering under it would
    -- silently retarget the amend at whatever slid into those rows.
    modes.state = { mode = 'amend', source = { rows = { 4 } }, opts = {} }
    watch._on_event('fs')
    watch._tick()
    assert_eq(0, calls.status, 'blocked while a mode is active')
    assert_truthy(watch._dirty, 'the change is held, not dropped')
    assert_truthy(calls.arm > 0, 'the tick re-arms so it will retry')
  end)
end)

test('the held change flushes on the first tick after the mode clears', function()
  with_watch(function(calls)
    modes.state = { mode = 'squash', source = { rows = { 2 } }, opts = {} }
    watch._on_event('fs')
    watch._tick()
    assert_eq(0, calls.status)

    modes.state = nil
    watch._tick()
    assert_eq(1, calls.status, 'fires once on returning to normal mode')
    assert_falsy(watch._dirty)
  end)
end)

test('a refresh still in flight blocks the next tick', function()
  with_watch(function(calls)
    local release
    ---@diagnostic disable-next-line: duplicate-set-field
    status.refresh = function(o)
      calls.status = calls.status + 1
      release = o and o.done -- deliberately not called: still in flight
    end

    watch._on_event('fs')
    watch._tick()
    assert_eq(1, calls.status)

    watch._on_event('fs')
    watch._tick()
    assert_eq(1, calls.status, 'a slow `but` must not stack refreshes')

    release()
    watch._tick()
    assert_eq(2, calls.status, 'the queued change lands once the first returns')
  end)
end)

test('status and log refresh on a filesystem event, CI does not', function()
  with_watch(function(calls)
    watch._on_event('fs')
    watch._tick()
    assert_eq(1, calls.status)
    assert_eq(1, calls.log)
    assert_eq(0, calls.ci, 'a local commit must not spend a gh request')
  end)
end)

test('CI refreshes when the trigger was an autocmd', function()
  with_watch(function(calls)
    watch._on_event('focus')
    watch._tick()
    assert_eq(1, calls.ci, 'coming back to the window is when CI is worth refetching')
  end)
end)

test('a focus event anywhere in the window promotes the whole tick', function()
  with_watch(function(calls)
    watch._on_event('fs')
    watch._on_event('focus')
    watch._tick()
    assert_eq(1, calls.ci, 'the coalesced tick includes the focus trigger')
  end)
end)

test('the focus flag does not survive into the next tick', function()
  with_watch(function(calls)
    watch._on_event('focus')
    watch._tick()
    assert_eq(1, calls.ci)

    watch._on_event('fs')
    watch._tick()
    assert_eq(1, calls.ci, 'a later filesystem event must not inherit focus')
  end)
end)

test('closed views are skipped', function()
  with_watch(function(calls)
    log.instance = nil
    ci.instance = nil
    watch._on_event('focus')
    watch._tick()
    assert_eq(1, calls.status)
    assert_eq(0, calls.log)
    assert_eq(0, calls.ci)
  end)
end)

test('with every view closed the tick clears without deadlocking', function()
  with_watch(function(calls)
    status.instance, log.instance, ci.instance = nil, nil, nil
    watch._on_event('fs')
    watch._tick()
    assert_eq(0, calls.status)
    assert_falsy(watch._dirty, 'the pending flag clears')
    assert_falsy(watch._inflight, 'nothing is in flight, so nothing is held')
  end)
end)

local config = require('gitbutler.config')

---Run `fn` with every view closed and the watcher stopped, then stop it again.
---@param fn fun()
local function with_lifecycle(fn)
  local saved = {
    watch = config.values.watch,
    status_instance = status.instance,
    log_instance = log.instance,
    ci_instance = ci.instance,
  }
  status.instance, log.instance, ci.instance = nil, nil, nil
  watch.stop()

  local ok, err = pcall(fn)

  watch.stop()
  config.values.watch = saved.watch
  status.instance = saved.status_instance
  log.instance = saved.log_instance
  ci.instance = saved.ci_instance
  if not ok then
    error(err, 0)
  end
end

test('watch = false starts nothing', function()
  with_lifecycle(function()
    config.values.watch = false
    status.instance = { buf = vim.api.nvim_create_buf(false, true) }
    watch.sync()
    assert_falsy(watch._augroup, 'no augroup')
    assert_eq(0, #watch._handles, 'no filesystem handles')
    assert_falsy(watch._timer, 'no timer')
    vim.api.nvim_buf_delete(status.instance.buf, { force = true })
  end)
end)

test('sync starts the autocmds when a view is open', function()
  with_lifecycle(function()
    config.values.watch = true
    status.instance = { buf = vim.api.nvim_create_buf(false, true) }
    watch.sync()
    assert_truthy(watch._augroup, 'the augroup owns the focus autocmds')
    vim.api.nvim_buf_delete(status.instance.buf, { force = true })
  end)
end)

test('sync is idempotent — a second call does not double the handles', function()
  with_lifecycle(function()
    config.values.watch = true
    status.instance = { buf = vim.api.nvim_create_buf(false, true) }
    watch.sync()
    local first = #watch._handles
    watch.sync()
    assert_eq(first, #watch._handles)
    vim.api.nvim_buf_delete(status.instance.buf, { force = true })
  end)
end)

test('sync stops the watcher when the last view closes', function()
  with_lifecycle(function()
    config.values.watch = true
    local buf = vim.api.nvim_create_buf(false, true)
    status.instance = { buf = buf }
    watch.sync()
    assert_truthy(watch._augroup)

    status.instance = nil
    watch.sync()
    assert_falsy(watch._augroup, 'nothing left to refresh, so nothing left running')
    assert_eq(0, #watch._handles)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)

test('a stale instance whose buffer is gone does not keep the watcher alive', function()
  with_lifecycle(function()
    config.values.watch = true
    local buf = vim.api.nvim_create_buf(false, true)
    status.instance = { buf = buf }
    watch.sync()
    -- Buffer:close deletes the buffer before the view clears its instance;
    -- sync must not be fooled by the window between the two.
    vim.api.nvim_buf_delete(buf, { force = true })
    watch.sync()
    assert_falsy(watch._augroup)
  end)
end)

test('stop leaves no live handle behind', function()
  with_lifecycle(function()
    config.values.watch = true
    local buf = vim.api.nvim_create_buf(false, true)
    status.instance = { buf = buf }
    watch.sync()
    watch.stop()
    assert_eq(0, #watch._handles)
    assert_falsy(watch._timer)
    assert_falsy(watch._augroup)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)

local cli = require('gitbutler.cli')
local h = require('tests.gitbutler.helpers')
local status = require('gitbutler.ui.status')
local test, assert_eq, assert_truthy = h.test, h.assert_eq, h.assert_truthy

print('\n=== Refresh options tests ===')

---Run `fn` with cli.status and vim.notify stubbed, then restore both.
---@param stub fun(callback: fun(err: string?, data: table?))
---@param fn fun(notes: string[])
local function with_status(stub, fn)
  local orig_cli, orig_notify, orig_instance = cli.status, vim.notify, status.instance
  local notes = {}
  ---@diagnostic disable-next-line: duplicate-set-field
  cli.status = stub
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.notify = function(msg)
    table.insert(notes, msg)
  end
  local buf = h.mock_buffer()
  h.mock_render(buf)
  status.instance = buf

  local ok, err = pcall(fn, notes)

  cli.status, vim.notify, status.instance = orig_cli, orig_notify, orig_instance
  status.data = nil
  if not ok then
    error(err, 0)
  end
end

test('done fires once on a successful refresh', function()
  with_status(function(callback)
    callback(nil, { stacks = {} })
  end, function()
    local calls = 0
    status.refresh({
      done = function()
        calls = calls + 1
      end,
    })
    assert_eq(1, calls)
  end)
end)

test('done fires on a CLI error, so the watcher cannot deadlock', function()
  with_status(function(callback)
    callback('but exploded', nil)
  end, function()
    local calls = 0
    status.refresh({
      quiet = true,
      done = function()
        calls = calls + 1
      end,
    })
    assert_eq(1, calls, 'a failed refresh must still release the in-flight flag')
  end)
end)

test('done fires when the output is not a table', function()
  with_status(function(callback)
    callback(nil, 'nonsense')
  end, function()
    local calls = 0
    status.refresh({
      quiet = true,
      done = function()
        calls = calls + 1
      end,
    })
    assert_eq(1, calls)
  end)
end)

test('quiet suppresses the error toast', function()
  with_status(function(callback)
    callback('but exploded', nil)
  end, function(notes)
    status.refresh({ quiet = true })
    assert_eq(0, #notes, 'an unrequested refresh must not toast')
  end)
end)

test('a manual refresh still reports its errors', function()
  with_status(function(callback)
    callback('but exploded', nil)
  end, function(notes)
    status.refresh()
    assert_eq(1, #notes)
    assert_truthy(notes[1]:find('but exploded', 1, true))
  end)
end)

test('done fires even when no view is open', function()
  local orig = status.instance
  status.instance = nil
  local calls = 0
  status.refresh({
    done = function()
      calls = calls + 1
    end,
  })
  status.instance = orig
  assert_eq(1, calls)
end)

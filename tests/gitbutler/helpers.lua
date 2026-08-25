-- Shared test helpers: assertions, mocks, runners
local buffer_mod = require('gitbutler.ui.buffer')
local cli = require('gitbutler.cli')
local status = require('gitbutler.ui.status')

local M = {}

M.pass = 0
M.fail = 0
M.errors = {}

---Cleanups to run when the current test ends, pass or fail. Registered by
---`M.after`, drained by `M.test`.
M._after = {}

function M.test(name, fn)
  M._after = {}
  local ok, err = pcall(fn)
  for i = #M._after, 1, -1 do
    pcall(M._after[i])
  end
  M._after = {}
  if ok then
    M.pass = M.pass + 1
    print('  PASS  ' .. name)
  else
    M.fail = M.fail + 1
    table.insert(M.errors, { name = name, err = err })
    print('  FAIL  ' .. name)
    print('        ' .. tostring(err))
  end
end

function M.assert_eq(expected, actual, msg)
  if expected ~= actual then
    error((msg or '') .. ' expected: ' .. vim.inspect(expected) .. ' got: ' .. vim.inspect(actual), 2)
  end
end

function M.assert_truthy(val, msg)
  if not val then
    error((msg or 'expected truthy') .. ' got: ' .. vim.inspect(val), 2)
  end
end

function M.assert_falsy(val, msg)
  if val then
    error((msg or 'expected falsy') .. ' got: ' .. vim.inspect(val), 2)
  end
end

function M.assert_type(expected_type, val, msg)
  if type(val) ~= expected_type then
    error((msg or '') .. ' expected type ' .. expected_type .. ' got ' .. type(val), 2)
  end
end

---Register a cleanup for the current test. Restoring a stub this way survives a
---failing assertion, which `error()`s out of the test body — a stub left
---installed leaks into every spec that runs after it in the same headless run.
---@param fn fun()
function M.after(fn)
  table.insert(M._after, fn)
end

function M.mock_buffer()
  local buf = buffer_mod.Buffer.new()
  buf.is_folded = function(_, _)
    return false
  end
  buf._cursor_row = nil
  return buf
end

---Stub `buf:render` and return the capture table; `cap.lines` holds the rows
---from the most recent render.
---@param buf table
---@return { lines: GitButlerLine[]? }
function M.mock_render(buf)
  local cap = {}
  ---@diagnostic disable-next-line: duplicate-set-field
  buf.render = function(_, lines)
    cap.lines = lines
  end
  return cap
end

function M.capture_lines(fixture_data, show_all_files)
  local original = cli.status
  cli.status = function(callback)
    callback(nil, fixture_data)
  end

  local buf = M.mock_buffer()
  buf.show_all_files = show_all_files == true
  status.instance = buf
  local cap = M.mock_render(buf)
  status.refresh()

  cli.status = original
  status.instance = nil
  status.data = nil
  return cap.lines
end

function M.summary()
  return M.pass, M.fail, M.errors
end

return M

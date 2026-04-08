-- Shared test helpers: assertions, mocks, runners
local buffer_mod = require('gitbutler.ui.buffer')
local cli = require('gitbutler.cli')
local status = require('gitbutler.ui.status')

local M = {}

M.pass = 0
M.fail = 0
M.errors = {}

function M.test(name, fn)
  local ok, err = pcall(fn)
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

function M.mock_buffer()
  local buf = buffer_mod.Buffer.new()
  buf.is_folded = function(_, _) return false end
  buf._cursor_row = nil
  return buf
end

function M.capture_lines(fixture_data)
  local captured
  local original = cli.status
  cli.status = function(callback) callback(nil, fixture_data) end

  local buf = M.mock_buffer()
  status.instance = buf
  buf.render = function(_, lines) captured = lines end
  status.refresh()

  cli.status = original
  status.instance = nil
  return captured
end

function M.summary()
  return M.pass, M.fail, M.errors
end

return M

-- Shared harness for the end-to-end smoke checks. These drive the plugin
-- against the REAL `but` CLI in the current workspace, so they live behind
-- `make smoke` rather than in the unit suite (`make test`).
--
-- Design rule: a check either PASSES against real CLI behaviour or SKIPS when
-- the workspace lacks the state it needs (e.g. no applied branch to rub onto).
-- It only FAILS on an actual regression. That keeps `make smoke` green on any
-- valid GitButler workspace while still exercising the full path when the state
-- is present.

vim.opt.rtp:prepend(vim.fn.getcwd())

local M = {}

M.failed = false

function M.ok(msg)
  print('  OK   ' .. msg)
end

function M.skip(msg)
  print('  SKIP ' .. msg)
end

function M.fail(msg)
  print('  FAIL ' .. msg)
  M.failed = true
  -- Abort immediately: later checks assume earlier state.
  vim.cmd('cquit 1')
end

---Refresh the status view and block until `but status` returns.
function M.wait_status(status)
  status.data = nil
  status.refresh()
  if not vim.wait(15000, function()
    return status.data ~= nil
  end, 50) then
    M.fail('but status did not return within 15s')
  end
end

---Invoke a buffer-local normal-mode mapping's callback by its lhs.
---Normalises termcodes so '<Space>'/'<CR>' match how nvim stores them.
function M.press(buf, key)
  local want = vim.api.nvim_replace_termcodes(key, true, true, true)
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
    local lhs = vim.api.nvim_replace_termcodes(m.lhs, true, true, true)
    if (m.lhs == key or lhs == want) and m.callback then
      m.callback()
      return true
    end
  end
  M.fail('no mapping for ' .. key .. ' in buffer ' .. buf)
end

---First row of a given type in the status buffer, or nil.
function M.find_row(buf, kind, pred)
  for i, l in ipairs(buf.lines) do
    if l.type == kind and (not pred or pred(l)) then
      return i, l
    end
  end
  return nil
end

function M.done(name)
  print(name .. ' PASS')
  vim.cmd('qall!')
end

return M

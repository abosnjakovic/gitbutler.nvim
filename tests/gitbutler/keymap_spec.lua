-- Default keymaps must resolve to a registered action handler.
-- Buffer:_set_keymaps silently no-ops on an unknown action name, so a renamed
-- or dropped action turns into a dead key with no error anywhere.
local config = require('gitbutler.config')
local h = require('tests.gitbutler.helpers')
local test, assert_truthy = h.test, h.assert_truthy

print('\n=== Keymap wiring tests ===')

---Action names registered via `buf:on('name', ...)` in a source file.
---@param path string
---@return table<string, boolean>
local function registered(path)
  local names = {}
  for _, line in ipairs(vim.fn.readfile(path)) do
    local name = line:match("buf:on%('([%w_]+)'")
    if name then
      names[name] = true
    end
  end
  assert_truthy(next(names), path .. ': no buf:on registrations found (moved?)')
  return names
end

---@param view string
---@param path string
local function check_view(view, path)
  test('every default ' .. view .. ' keymap has a handler', function()
    local handlers = registered(path)
    for key, action in pairs(config.defaults.keymaps[view]) do
      if action then
        assert_truthy(handlers[action], ('%s: %s -> %s is not registered'):format(view, key, action))
      end
    end
  end)
end

check_view('status', 'lua/gitbutler/ui/status.lua')
check_view('ci', 'lua/gitbutler/ui/ci.lua')

test('status handlers point at real actions functions', function()
  local actions = require('gitbutler.actions')
  for _, line in ipairs(vim.fn.readfile('lua/gitbutler/ui/status.lua')) do
    local name = line:match("buf:on%('[%w_]+',%s*actions%.([%w_]+)%)")
    if name then
      h.assert_type('function', actions[name], 'actions.' .. name)
    end
  end
end)

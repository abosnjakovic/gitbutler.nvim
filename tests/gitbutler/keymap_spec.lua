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

-- The two-way test. Direction one catches a stale advert; direction two is the
-- one that would have caught the details pane binding a dozen keys that
-- appeared in no hint list anywhere.
local keys = require('gitbutler.keys')

local SOURCES = {
  status = 'lua/gitbutler/ui/status.lua',
  ci = 'lua/gitbutler/ui/ci.lua',
  details = 'lua/gitbutler/ui/details.lua',
}

-- For `status` and `ci` this guards the live bindings directly: both bind
-- through `Buffer:_set_keymaps`, which dispatches from the same `buf.keymaps`
-- table `registered()` greps for here. `details` is the exception — the pane
-- calls `buf:attach(win)` rather than `Buffer:open()`, so `_set_keymaps` never
-- runs and nothing dispatches from `buf.keymaps`. This still catches a
-- registry action with no `M._register_handlers` entry, which the eventual
-- binding rewrite needs, but it does NOT prove the pane's live keys match the
-- registry — that guard is `details_spec.lua`'s "the pane's live keymaps
-- match the registry" test, which inspects `nvim_buf_get_keymap` directly.
for view, path in pairs(SOURCES) do
  test('every ' .. view .. ' registry action has a handler', function()
    local handlers = registered(path)
    for _, spec in ipairs(keys.resolved(view)) do
      -- native entries (details' j/k/g/G) document a key the pane answers
      -- natively; by definition they carry no action and no handler.
      if not spec.native then
        assert_truthy(handlers[spec.action], view .. ' action has a handler: ' .. spec.action)
      end
    end
  end)
end

test('every bound key appears in exactly one registry entry', function()
  for view, bindings in pairs(config.defaults.keymaps) do
    local documented = {}
    for _, spec in ipairs(keys.resolved(view)) do
      assert_truthy(not documented[spec.key], view .. ' binds ' .. spec.key .. ' once')
      documented[spec.key] = true
    end
    for key, action in pairs(bindings) do
      if action then
        assert_truthy(documented[key], view .. ' documents its bound key: ' .. key)
      end
    end
  end
end)

-- The bug this whole project exists to fix: `?` in the details pane rendered
-- the status view's keybindings, because the pane's help wiring passed the
-- status buffer instead of its own. Asserts the resolution `M.help` performs
-- (context, then generated lines), not the wiring — the wiring is two lines
-- in `details.lua` passing `M.win_state.buffer` and is reviewable by eye.
test('? in the details pane resolves the details context, not status', function()
  local actions = require('gitbutler.actions')
  local pane_buf = h.mock_buffer()
  pane_buf.view = 'details'

  local context, lines = actions._help_content(pane_buf)
  assert_truthy(context == 'details', 'context resolves to details, got: ' .. tostring(context))

  local text = table.concat(lines, '\n')
  for _, key in ipairs({ 'C', 'Y', ']c' }) do
    assert_truthy(text:find(key, 1, true), 'details help includes the pane key: ' .. key)
  end
  assert_truthy(not text:find('Amend mode', 1, true), 'details help excludes status mode entries')
  assert_truthy(not text:find('Squash mode', 1, true), 'details help excludes status mode entries')
end)

-- The close/help footer has always been the last thing in the float. Prose is
-- appended for the status context, so composing it after the trailer strands
-- the footer mid-list — invisible to any presence/absence assertion.
test('the help float ends with its close/help footer', function()
  for _, view in ipairs({ 'status', 'details' }) do
    local _, lines = require('gitbutler.actions')._help_content({ view = view })
    local last
    for _, line in ipairs(lines) do
      if line ~= '' then
        last = line
      end
    end
    assert_truthy(last and last:find('Close'), view .. ' float ends with the footer, got: ' .. tostring(last))
  end
end)

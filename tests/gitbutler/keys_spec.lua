local config = require('gitbutler.config')
local h = require('tests.gitbutler.helpers')
local keys = require('gitbutler.keys')

print('\n=== Keys registry tests ===')

-- Every consumer reads these fields. A blank one produces an invisible
-- hotbar item or a help line with no explanation, and nothing else would catch it.
-- A native entry (documented, unbound on purpose) must have no action, and a
-- non-native entry must have one — "forgot the action" and "deliberately
-- native" must never be confusable.
h.test('keys: every entry in every context is complete', function()
  for context, specs in pairs(keys.contexts) do
    h.assert_truthy(#specs > 0, context .. ' has entries')
    for _, spec in ipairs(specs) do
      local where = context .. ' / ' .. tostring(spec.key)
      h.assert_truthy(spec.key and spec.key ~= '', where .. ' has a key')
      h.assert_truthy(spec.desc and spec.desc ~= '', where .. ' has a description')
      if spec.native then
        h.assert_falsy(spec.action, where .. ' is native, so it binds nothing')
      else
        h.assert_truthy(spec.action and spec.action ~= '', where .. ' has an action')
      end
    end
  end
end)

h.test('keys: the three contexts exist', function()
  for _, context in ipairs({ 'status', 'ci', 'details' }) do
    h.assert_truthy(keys.contexts[context], context .. ' is a context')
  end
end)

---Find the resolved entry for an action, or nil.
local function by_action(resolved, action)
  for _, spec in ipairs(resolved) do
    if spec.action == action then
      return spec
    end
  end
  return nil
end

-- The whole point of keeping config in charge of keys: remap one and every
-- surface that documents it follows, with no second list to update.
h.test('keys: a config remap replaces the registry key', function()
  local original = config.values.keymaps.status
  h.after(function()
    config.values.keymaps.status = original
  end)
  config.values.keymaps.status = vim.tbl_extend('force', {}, original, { ['a'] = false, ['A'] = 'amend_start' })

  local resolved = keys.resolved('status')
  local amend = by_action(resolved, 'amend_start')
  h.assert_truthy(amend, 'amend_start survives the remap')
  h.assert_eq('A', amend.key)
  h.assert_eq('amend', amend.desc, 'the description comes from the registry, not the config')
end)

-- A disabled binding must vanish from the documentation too, or the hotbar
-- advertises a key that does nothing.
h.test('keys: an action disabled in config resolves to nothing', function()
  local original = config.values.keymaps.status
  h.after(function()
    config.values.keymaps.status = original
  end)
  config.values.keymaps.status = vim.tbl_extend('force', {}, original, { ['a'] = false })

  h.assert_falsy(by_action(keys.resolved('status'), 'amend_start'), 'the entry is gone entirely')
end)

-- The details pane has no config table. That absence IS "not user-configurable
-- yet" — the registry's own key has to stand, with no special case.
h.test('keys: a context with no config table keeps the registry key', function()
  h.assert_falsy(config.values.keymaps.details, 'details is deliberately absent from config')
  local resolved = keys.resolved('details')
  h.assert_truthy(#resolved > 0, 'details still resolves to its bindings')
  local comment = by_action(resolved, 'comment_line')
  h.assert_truthy(comment, 'the comment binding resolves')
  h.assert_eq('C', comment.key)
end)

h.test('keys: resolved is empty for an unknown context', function()
  h.assert_eq(0, #keys.resolved('no-such-view'))
end)

-- The pane scrolls line by line because j/k/g/G are NOT mapped there. A binding
-- would take that back. They are documented so the hint line can say what they
-- do, and carry no action so nothing binds them.
h.test('keys: the details pane documents its native motions without binding them', function()
  local native = {}
  for _, spec in ipairs(keys.resolved('details')) do
    if spec.native then
      native[spec.key] = spec
    end
  end
  for _, key in ipairs({ 'j', 'k', 'g', 'G' }) do
    h.assert_truthy(native[key], 'the pane documents ' .. key)
    h.assert_falsy(native[key].action, key .. ' binds nothing')
  end
end)

-- Several actions are bound to two keys by default. The registry holds one
-- entry per key; resolution must not collapse them onto whichever key Lua's
-- unordered pairs() happened to yield last.
h.test('keys: aliased keys keep their own entries', function()
  local by_key = {}
  for _, spec in ipairs(keys.resolved('status')) do
    by_key[spec.key] = spec.action
  end
  h.assert_eq('cursor_down', by_key['j'])
  h.assert_eq('cursor_down', by_key['<Down>'])
  h.assert_eq('cursor_up', by_key['k'])
  h.assert_eq('cursor_up', by_key['<Up>'])
  h.assert_eq('details_focus', by_key['l'])
  h.assert_eq('details_focus', by_key['<Right>'])
end)

-- Idempotence, not determinism: `pairs()` order is stable within a process, so
-- this would pass under the old alias-collapsing code too. The regression is
-- pinned by 'aliased keys keep their own entries', which fails outright there.
h.test('keys: resolution is idempotent', function()
  local first, second = keys.resolved('status'), keys.resolved('status')
  h.assert_eq(#first, #second)
  for i = 1, #first do
    h.assert_eq(first[i].key, second[i].key, 'entry ' .. i .. ' is stable')
    h.assert_eq(first[i].action, second[i].action)
  end
end)

-- The hotbar reads this list in order, so order is part of the contract.
h.test('keys: resolution preserves registry order', function()
  local resolved = keys.resolved('status')
  local want = {}
  for _, spec in ipairs(keys.contexts.status) do
    table.insert(want, spec.action)
  end
  local got = {}
  for _, spec in ipairs(resolved) do
    table.insert(got, spec.action)
  end
  -- Same sequence, since the default config disables nothing.
  h.assert_eq(table.concat(want, ','), table.concat(got, ','))
end)

-- A native key is spoken for: the pane relies on it doing its default thing.
-- If a context ever gains a config table, a remap must not be able to land on
-- top of one and leave two entries claiming the same key.
--
-- `details` has no config table in production today — this test builds one
-- that doesn't exist yet, on purpose, to pin the behaviour before the deferred
-- `config.values.keymaps.details` change makes the scenario reachable for real.
h.test('keys: a native key cannot be claimed by a remapped action', function()
  local original = config.values.keymaps.details
  h.after(function()
    config.values.keymaps.details = original
  end)
  config.values.keymaps.details = { ['j'] = 'hunk_next' }

  local seen = {}
  for _, spec in ipairs(keys.resolved('details')) do
    h.assert_falsy(seen[spec.key], 'key ' .. spec.key .. ' is claimed once')
    seen[spec.key] = true
  end
end)

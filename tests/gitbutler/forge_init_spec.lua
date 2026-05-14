local h = require('tests.gitbutler.helpers')
local forge = require('gitbutler.forge')
local test, assert_eq = h.test, h.assert_eq

print('\n=== Forge registry tests ===')

-- Stub adapter: only `name` and `detect` are exercised here.
local stub_gh = {
  name = 'github',
  detect = function(url) return url:find('github.com', 1, true) ~= nil end,
}

test('register + get_adapter round-trip', function()
  forge._reset()
  forge.register(stub_gh)
  assert_eq(stub_gh, forge.get_adapter('github'))
end)

test('detect_from_url matches https github', function()
  forge._reset()
  forge.register(stub_gh)
  assert_eq(stub_gh, forge.detect_from_url('https://github.com/foo/bar.git'))
end)

test('detect_from_url matches ssh github', function()
  forge._reset()
  forge.register(stub_gh)
  assert_eq(stub_gh, forge.detect_from_url('git@github.com:foo/bar.git'))
end)

test('detect_from_url returns nil for gitlab', function()
  forge._reset()
  forge.register(stub_gh)
  assert_eq(nil, forge.detect_from_url('https://gitlab.com/foo/bar.git'))
end)

test('detect_from_url returns nil for empty', function()
  forge._reset()
  forge.register(stub_gh)
  assert_eq(nil, forge.detect_from_url(''))
end)

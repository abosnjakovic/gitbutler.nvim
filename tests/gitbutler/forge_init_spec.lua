local forge = require('gitbutler.forge')
local h = require('tests.gitbutler.helpers')
local test, assert_eq = h.test, h.assert_eq

print('\n=== Forge registry tests ===')

-- Stub adapter: only `name` and `detect` are exercised here.
local stub_gh = {
  name = 'github',
  detect = function(url)
    return url:find('github.com', 1, true) ~= nil
  end,
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

-- The origin remote does not change under a running session, so it is read
-- once, not on every branch the pane shows.
test('web_base reads the origin remote once and asks the adapter for the page', function()
  forge._reset()
  forge.register(vim.tbl_extend('force', stub_gh, {
    web_url = function(url)
      return url:find('github.com', 1, true) and 'https://github.com/foo/bar' or nil
    end,
  }))
  local spawns = 0
  local orig_system, orig_base = vim.system, forge._web_base
  h.after(function()
    vim.system, forge._web_base = orig_system, orig_base
  end)
  vim.system = function()
    spawns = spawns + 1
    return {
      wait = function()
        return { code = 0, stdout = 'git@github.com:foo/bar.git\n' }
      end,
    }
  end
  forge._web_base = nil
  assert_eq('https://github.com/foo/bar', forge.web_base())
  assert_eq('https://github.com/foo/bar', forge.web_base())
  assert_eq(1, spawns)
end)

test('web_base is nil when no adapter knows the remote', function()
  forge._reset()
  forge.register(stub_gh)
  local orig_system, orig_base = vim.system, forge._web_base
  h.after(function()
    vim.system, forge._web_base = orig_system, orig_base
  end)
  vim.system = function()
    return {
      wait = function()
        return { code = 0, stdout = 'git@gitlab.com:foo/bar.git\n' }
      end,
    }
  end
  forge._web_base = nil
  assert_eq(nil, forge.web_base())
end)

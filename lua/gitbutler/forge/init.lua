---Pluggable forge adapter registry.
---
---An adapter is a table with this contract:
---  {
---    name = string,
---    detect = function(remote_url) -> boolean,
---    list_checks = function(branch, callback(err, checks[])),
---    view_log = function(check_id, callback(err, log_text)),
---    rerun = function(check_id, callback(err)),
---    open_in_browser = function(url),
---    web_url = function(remote_url) -> string?,        -- optional
---    view_pr = function(number, callback(err, pr)),    -- optional
---  }
---
---A `check` is:
---  { id, name, status, conclusion?, started_at?, completed_at?, url }

local M = {}

---@type table<string, table>
local adapters = {}

function M.register(adapter)
  assert(type(adapter) == 'table' and adapter.name, 'forge adapter requires .name')
  adapters[adapter.name] = adapter
end

function M.get_adapter(name)
  return adapters[name]
end

function M.list_adapters()
  local names = {}
  for n in pairs(adapters) do
    table.insert(names, n)
  end
  return names
end

---Match a remote URL against each registered adapter's detect().
---Returns the first matching adapter, or nil.
function M.detect_from_url(url)
  if not url or url == '' then
    return nil
  end
  for _, a in pairs(adapters) do
    if a.detect and a.detect(url) then
      return a
    end
  end
  return nil
end

---@return string? url the origin remote, nil when there is none
local function origin_url()
  local r = vim.system({ 'git', 'remote', 'get-url', 'origin' }, { text = true }):wait()
  if r.code ~= 0 or not r.stdout then
    return nil
  end
  return vim.trim(r.stdout)
end

---Convenience: run `git remote get-url origin` then dispatch.
function M.detect_from_remote()
  return M.detect_from_url(origin_url())
end

---Cached `web_base()` answer; false caches "no known forge". Set nil to re-read.
---@type string|false|nil
M._web_base = nil

---The origin repo's web page (e.g. `https://github.com/o/r`), nil when the
---remote is not a forge with an adapter. Read once: the remote does not move
---under a running session.
---@return string?
function M.web_base()
  if M._web_base == nil then
    local url = origin_url()
    local adapter = M.detect_from_url(url)
    M._web_base = adapter and adapter.web_url and adapter.web_url(url) or false
  end
  return M._web_base or nil
end

---Test-only: clear registered adapters.
function M._reset()
  adapters = {}
end

M.register(require('gitbutler.forge.gh'))

return M

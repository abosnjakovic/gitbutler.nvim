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

---Convenience: run `git remote get-url origin` then dispatch.
function M.detect_from_remote()
  local r = vim.system({ 'git', 'remote', 'get-url', 'origin' }, { text = true }):wait()
  if r.code ~= 0 or not r.stdout then
    return nil
  end
  return M.detect_from_url(vim.trim(r.stdout))
end

---Test-only: clear registered adapters.
function M._reset()
  adapters = {}
end

return M

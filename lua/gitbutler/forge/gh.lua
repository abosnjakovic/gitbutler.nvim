---GitHub forge adapter. Shells out to the `gh` CLI.
local M = {}

M.name = 'github'

function M.detect(url)
  if not url or url == '' then
    return false
  end
  return url:find('github.com', 1, true) ~= nil
end

---Parse the JSON output of `gh run list --json ...` into the adapter check shape.
---@param json_text string
---@return table[]
function M.parse_checks(json_text)
  local ok, decoded = pcall(vim.json.decode, json_text)
  if not ok or type(decoded) ~= 'table' then
    return {}
  end
  local checks = {}
  for _, run in ipairs(decoded) do
    table.insert(checks, {
      id = tostring(run.databaseId),
      name = run.name,
      status = run.status,
      conclusion = run.conclusion,
      started_at = run.startedAt,
      completed_at = run.updatedAt,
      url = run.url,
    })
  end
  return checks
end

local gh_warned = false

local function require_gh(callback)
  if vim.fn.executable('gh') == 1 then
    return true
  end
  if not gh_warned then
    gh_warned = true
    vim.notify(
      'gitbutler: gh CLI not found. Install with `brew install gh` or see https://cli.github.com',
      vim.log.levels.WARN
    )
  end
  callback('gh not installed')
  return false
end

---@param branch string
---@param callback fun(err?: string, checks?: table[])
function M.list_checks(branch, callback)
  if not require_gh(callback) then
    return
  end
  local args = {
    'gh', 'run', 'list',
    '--branch', branch,
    '--json', 'databaseId,name,status,conclusion,startedAt,updatedAt,url',
    '--limit', '30',
  }
  vim.system(args, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        local msg = (result.stderr and result.stderr ~= '')
            and result.stderr
          or ('gh run list exited with code ' .. result.code)
        callback(vim.trim(msg))
        return
      end
      callback(nil, M.parse_checks(result.stdout or '[]'))
    end)
  end)
end

---@param check_id string
---@param callback fun(err?: string, log_text?: string)
function M.view_log(check_id, callback)
  if not require_gh(callback) then
    return
  end
  vim.system({ 'gh', 'run', 'view', check_id, '--log' }, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        local msg = (result.stderr and result.stderr ~= '')
            and result.stderr
          or ('gh run view exited with code ' .. result.code)
        callback(vim.trim(msg))
        return
      end
      callback(nil, result.stdout or '')
    end)
  end)
end

---@param check_id string
---@param callback fun(err?: string)
function M.rerun(check_id, callback)
  if not require_gh(callback) then
    return
  end
  vim.system({ 'gh', 'run', 'rerun', check_id, '--failed' }, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        local msg = (result.stderr and result.stderr ~= '')
            and result.stderr
          or ('gh run rerun exited with code ' .. result.code)
        callback(vim.trim(msg))
        return
      end
      callback(nil)
    end)
  end)
end

---@param url string
function M.open_in_browser(url)
  if vim.ui and vim.ui.open then
    vim.ui.open(url)
  else
    vim.notify('gitbutler: vim.ui.open unavailable; URL: ' .. url, vim.log.levels.INFO)
  end
end

return M

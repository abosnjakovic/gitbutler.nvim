---GitHub forge adapter. Shells out to the `gh` CLI.
local M = {}

M.name = 'github'

function M.detect(url)
  if not url or url == '' then
    return false
  end
  return url:find('github.com', 1, true) ~= nil
end

---Map a `gh pr checks` bucket to the {status, conclusion} pair the glyph mapper expects.
---@param bucket? string
---@return string status
---@return string? conclusion
local function bucket_to_status(bucket)
  if bucket == 'pass' then
    return 'completed', 'success'
  elseif bucket == 'fail' then
    return 'completed', 'failure'
  elseif bucket == 'pending' then
    return 'in_progress', nil
  elseif bucket == 'cancel' or bucket == 'skipping' then
    return 'completed', 'cancelled'
  end
  return 'queued', nil
end

---Parse `gh pr checks --json name,state,bucket,workflow,startedAt,completedAt,link`
---into the adapter check shape. One row per workflow job.
---@param json_text string
---@return table[]
function M.parse_checks(json_text)
  local ok, decoded = pcall(vim.json.decode, json_text)
  if not ok or type(decoded) ~= 'table' then
    return {}
  end
  local checks = {}
  for _, c in ipairs(decoded) do
    local status, conclusion = bucket_to_status(c.bucket)
    local job_id = c.link and tostring(c.link):match('/job/(%d+)') or nil
    local label
    if c.workflow and c.workflow ~= '' then
      label = c.workflow .. ' / ' .. (c.name or '?')
    else
      label = c.name or '?'
    end
    table.insert(checks, {
      id = job_id or c.link or '?',
      name = label,
      status = status,
      conclusion = conclusion,
      started_at = c.startedAt,
      completed_at = c.completedAt,
      url = c.link,
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

---List per-job checks for the branch's PR. Requires an open PR on the branch;
---if there's no PR the callback receives a clear error.
---@param branch string
---@param callback fun(err?: string, checks?: table[])
function M.list_checks(branch, callback)
  if not require_gh(callback) then
    return
  end
  local args = {
    'gh',
    'pr',
    'checks',
    branch,
    '--json',
    'name,state,bucket,workflow,startedAt,completedAt,link',
  }
  vim.system(args, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        local stderr = vim.trim(result.stderr or '')
        local msg
        if stderr:lower():find('no pull requests', 1, true) or stderr:lower():find('no open pull request', 1, true) then
          msg = 'no open PR for ' .. branch .. ' — push and run `R` to open one'
        elseif stderr ~= '' then
          msg = stderr
        else
          msg = 'gh pr checks exited with code ' .. result.code
        end
        callback(msg)
        return
      end
      callback(nil, M.parse_checks(result.stdout or '[]'))
    end)
  end)
end

---Open the log for a single job in a scratch buffer's source text.
---@param check_id string Job ID (extracted from the check's link)
---@param callback fun(err?: string, log_text?: string)
function M.view_log(check_id, callback)
  if not require_gh(callback) then
    return
  end
  vim.system({ 'gh', 'run', 'view', '--job', check_id, '--log' }, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        local msg = (result.stderr and result.stderr ~= '') and result.stderr
          or ('gh run view exited with code ' .. result.code)
        callback(vim.trim(msg))
        return
      end
      callback(nil, result.stdout or '')
    end)
  end)
end

---Re-run a single failed job.
---@param check_id string Job ID
---@param callback fun(err?: string)
function M.rerun(check_id, callback)
  if not require_gh(callback) then
    return
  end
  vim.system({ 'gh', 'run', 'rerun', '--job', check_id }, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        local msg = (result.stderr and result.stderr ~= '') and result.stderr
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

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

return M

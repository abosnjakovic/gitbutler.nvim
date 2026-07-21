-- Open a commit in an external diff tool (codediff.nvim, diffview.nvim, …) or
-- a built-in `git show` fallback. Configured via the `commit_diff` setup
-- option; bound to `o` on a commit row.
--
-- All the popular tools open a commit through a command string built from its
-- SHA, so the adapter is a template keyed by tool name, with a raw-template and
-- a function escape hatch for anything else.

local M = {}

---Command templates for known tools. `%s` is the full commit SHA; it is passed
---twice so single- and double-placeholder templates both work.
M.presets = {
  codediff = 'CodeDiff %s^ %s', -- esmuellert/codediff.nvim: commit^ vs commit
  diffview = 'DiffviewOpen %s^!', -- sindrets/diffview.nvim: ^! = commit vs parent
  fugitive = 'Git show %s', -- tpope/vim-fugitive: the commit's patch
}

---Resolve the `commit_diff` setting + a SHA into an action plan. Pure.
---@param setting nil|boolean|string|fun(sha: string)
---@param sha string full commit SHA
---@return { kind: 'fn'|'cmd'|'builtin'|'disabled', cmd?: string, fn?: fun() }
function M.plan(setting, sha)
  if setting == nil or setting == false then
    return { kind = 'builtin' }
  end
  if type(setting) == 'function' then
    return {
      kind = 'fn',
      fn = function()
        setting(sha)
      end,
    }
  end
  if type(setting) == 'string' then
    local template = M.presets[setting] or setting
    return { kind = 'cmd', cmd = template:format(sha, sha) }
  end
  return { kind = 'disabled' }
end

---Built-in fallback: a read-only `git show` patch in the editor window.
---@param sha string
function M._builtin(sha)
  local res = vim.system({ 'git', 'show', '--stat', '--patch', sha }, { text = true }):wait()
  if res.code ~= 0 then
    vim.notify('gitbutler: git show failed: ' .. vim.trim(res.stderr or ''), vim.log.levels.ERROR)
    return
  end
  require('gitbutler.ui.editor').show('git show ' .. sha:sub(1, 7), vim.split(res.stdout or '', '\n'), 'git')
end

---Open `sha` according to the configured `commit_diff` setting.
---@param sha string full commit SHA
function M.open(sha)
  if type(sha) ~= 'string' or sha == '' then
    vim.notify('gitbutler: no commit under cursor', vim.log.levels.WARN)
    return
  end
  local plan = M.plan(require('gitbutler.config').values.commit_diff, sha)
  if plan.kind == 'fn' then
    plan.fn()
  elseif plan.kind == 'cmd' then
    local ok, err = pcall(vim.cmd, plan.cmd)
    if not ok then
      vim.notify('gitbutler: commit_diff command failed (' .. plan.cmd .. '): ' .. tostring(err), vim.log.levels.ERROR)
    end
  elseif plan.kind == 'builtin' then
    M._builtin(sha)
  else
    vim.notify('gitbutler: invalid commit_diff setting', vim.log.levels.WARN)
  end
end

return M

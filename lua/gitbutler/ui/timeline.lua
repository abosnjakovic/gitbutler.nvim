local config = require('gitbutler.config')
local buffer_mod = require('gitbutler.ui.buffer')

local M = {}

---@type GitButlerBuffer?
M.instance = nil

---Parse the structured output of git log --all --format='%H|%h|%an|%ad|%D|%s'.
---The message field may itself contain pipe characters, so we split on the first 5 pipes only.
---@param raw string Raw git log output
---@return table[] commits Array of {sha, short_sha, author, date, refs, message}
function M.parse_git_log(raw)
  local commits = {}
  for line in raw:gmatch('[^\n]+') do
    local parts = {}
    local rest = line
    for _ = 1, 5 do
      local pos = rest:find('|', 1, true)
      if not pos then break end
      table.insert(parts, rest:sub(1, pos - 1))
      rest = rest:sub(pos + 1)
    end
    if #parts == 5 then
      table.insert(commits, {
        sha = parts[1],
        short_sha = parts[2],
        author = parts[3],
        date = parts[4],
        refs = parts[5],
        message = rest,
      })
    end
  end
  return commits
end

---Parse the output of git diff-tree --stat.
---Each file line looks like: " src/auth.lua | 15 +++---"
---The summary line ("N files changed, ...") is skipped.
---@param raw string Raw diff-tree --stat output
---@return table[] files Array of {path}
function M.parse_diff_tree(raw)
  local files = {}
  for line in raw:gmatch('[^\n]+') do
    -- Skip summary line
    if line:find('files? changed') then goto continue end
    local path = line:match('^%s*(.-)%s*|')
    if path then
      table.insert(files, { path = path })
    end
    ::continue::
  end
  return files
end

---Build structured lines from parsed commit data.
---@param buf table GitButlerBuffer instance (for fold state)
---@param commits table[] Parsed commits from parse_git_log
---@param days number Number of days shown (for header)
---@return GitButlerLine[]
function M.build_lines(buf, commits, days)
  local lines = {}

  local function add(text, hl, line_type, data_tbl, opts)
    opts = opts or {}
    table.insert(lines, {
      text = text,
      hl = hl,
      type = line_type,
      data = data_tbl,
      foldable = opts.foldable,
      folded = opts.folded,
      indent = opts.indent or 0,
    })
  end

  add('Timeline (last ' .. days .. ' days)', 'GitButlerSection', 'section_header', nil)
  add('', nil, 'blank', nil)

  -- Group commits by date
  local current_date = nil
  for _, commit in ipairs(commits) do
    if commit.date ~= current_date then
      current_date = commit.date
      add('── ' .. current_date .. ' ' .. string.rep('─', 30), 'GitButlerTimelineDate', 'date_header', nil)
    end

    local ref_part = ''
    if commit.refs ~= '' then
      ref_part = '  ' .. commit.refs
    end

    local display = commit.short_sha .. '  ' .. commit.author .. ref_part .. '  ' .. commit.message

    local fold_id = 'timeline:' .. commit.sha
    local is_folded = buf:is_folded(fold_id)
    -- Default to folded (collapsed)
    if buf.fold_state[fold_id] == nil then
      is_folded = true
    end

    add(display, 'GitButlerCommitHash', 'timeline_commit', {
      sha = commit.sha,
      short_sha = commit.short_sha,
      author = commit.author,
      refs = commit.refs,
      message = commit.message,
      fold_id = fold_id,
    }, { foldable = true, folded = is_folded })

    -- Expanded file list (when unfolded)
    if not is_folded and commit._files then
      for _, file in ipairs(commit._files) do
        add(file.path, 'GitButlerFileMod', 'timeline_file', {
          path = file.path,
          sha = commit.sha,
        }, { indent = 1 })
      end
    end
  end

  add('', nil, 'blank', nil)
  add('y=yank sha  l=log  r=refresh  q=close  <Tab>=toggle', 'GitButlerHelp', 'help', nil)

  return lines
end

---Fetch commits from git log --all.
---@param callback fun(commits: table[])
function M.fetch_commits(callback)
  local cfg = config.values.timeline or {}
  local days = cfg.days or 7
  local limit = cfg.limit or 200

  vim.system({
    'git', 'log', '--all', '--date=short',
    '--format=%H|%h|%an|%ad|%D|%s',
    '--since=' .. days .. ' days ago',
    '-n', tostring(limit),
  }, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        vim.notify('gitbutler timeline: git log failed', vim.log.levels.ERROR)
        callback({})
        return
      end
      local commits = M.parse_git_log(result.stdout or '')
      callback(commits)
    end)
  end)
end

---Fetch file changes for a commit (sync, fast for single commits).
---@param sha string Full commit SHA
---@return table[] files Array of {path}
function M.fetch_files(sha)
  local result = vim.system(
    { 'git', 'diff-tree', '--no-commit-id', '-r', '--stat', sha },
    { text = true }
  ):wait()
  if result.code ~= 0 or not result.stdout then return {} end
  return M.parse_diff_tree(result.stdout)
end

---Open the timeline view.
function M.open()
  M.fetch_commits(function(commits)
    local cfg = config.values.timeline or {}
    local days = cfg.days or 7

    local buf = buffer_mod.Buffer.new()
    M.instance = buf

    buf:on('close', function()
      buf:close()
      M.instance = nil
    end)

    buf:on('refresh', function()
      M.refresh()
    end)

    buf:on('toggle_fold', function(b)
      local line = b:get_cursor_line()
      if not line or line.type ~= 'timeline_commit' then return end
      if not line.data or not line.data.fold_id then return end

      local id = line.data.fold_id
      local currently_folded = b.fold_state[id]
      if currently_folded == nil then currently_folded = true end

      if currently_folded then
        -- Expanding: fetch files if not cached
        local sha = line.data.sha
        for _, c in ipairs(commits) do
          if c.sha == sha then
            if not c._files then
              c._files = M.fetch_files(sha)
            end
            break
          end
        end
      end

      b.fold_state[id] = not currently_folded
      local lines = M.build_lines(b, commits, days)
      b:render(lines)
    end)

    buf:on('yank_sha', function(b)
      local line = b:get_cursor_line()
      if not line or line.type ~= 'timeline_commit' then return end
      if not line.data or not line.data.sha then return end
      vim.fn.setreg('+', line.data.sha)
      vim.notify('Copied ' .. line.data.short_sha, vim.log.levels.INFO)
    end)

    buf:on('jump_to_log', function(b)
      local line = b:get_cursor_line()
      if not line or line.type ~= 'timeline_commit' then return end
      if not line.data or not line.data.refs or line.data.refs == '' then return end
      -- Take first ref, strip leading/trailing whitespace and remote prefix
      local ref = line.data.refs:match('^%s*(.-)%s*,') or line.data.refs:match('^%s*(.-)%s*$')
      if not ref or ref == '' then return end
      -- Strip origin/ prefix for local branch name
      ref = ref:gsub('^origin/', '')
      buf:close()
      M.instance = nil
      require('gitbutler.ui.log').open(ref)
    end)

    local timeline_keymaps = {
      ['q'] = 'close',
      ['r'] = 'refresh',
      ['<Tab>'] = 'toggle_fold',
      ['y'] = 'yank_sha',
      ['l'] = 'jump_to_log',
    }

    buf:open()

    for key, action in pairs(timeline_keymaps) do
      vim.keymap.set('n', key, function()
        local handler = buf.keymaps[action]
        if handler then handler(buf) end
      end, { buffer = buf.buf, nowait = true })
    end

    local lines = M.build_lines(buf, commits, days)
    buf:render(lines)
  end)
end

---Refresh the timeline view with fresh data.
function M.refresh()
  if not M.instance then return end
  local buf = M.instance
  local cfg = config.values.timeline or {}
  local days = cfg.days or 7

  M.fetch_commits(function(commits)
    local lines = M.build_lines(buf, commits, days)
    buf:render(lines)
  end)
end

return M

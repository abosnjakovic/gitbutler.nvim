local cli = require('gitbutler.cli')
local float = require('gitbutler.ui.float')
local buffer_mod = require('gitbutler.ui.buffer')

local M = {}

---@type table?
M.instance = nil

local function notify(action, err)
  if err then
    vim.notify('gitbutler ' .. action .. ': ' .. err, vim.log.levels.ERROR)
  else
    vim.notify('gitbutler: ' .. action .. ' done', vim.log.levels.INFO)
  end
end

---Build lines from `but show <branch> --json` output.
---Shape: { branch, commits: [{ sha, short_sha, message, full_message, author_name, timestamp, files_changed, insertions, deletions, files }] }
local function build_lines(buf, data)
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

  local branch_name = data.branch or '(unknown)'
  add('Log: ' .. branch_name .. ' (' .. #(data.commits or {}) .. ' commits)', 'GitButlerSection', 'section_header', nil)
  add('', nil, 'blank', nil)

  for _, commit in ipairs(data.commits or {}) do
    local sha_short = commit.short_sha or (commit.sha or ''):sub(1, 9)
    local msg = (commit.message or ''):match('^([^\n]*)') or ''
    local stats = ''
    if commit.files_changed then
      local parts = {}
      table.insert(parts, commit.files_changed .. ' file' .. (commit.files_changed > 1 and 's' or ''))
      if commit.insertions and commit.insertions > 0 then
        table.insert(parts, '+' .. commit.insertions)
      end
      if commit.deletions and commit.deletions > 0 then
        table.insert(parts, '-' .. commit.deletions)
      end
      stats = '  (' .. table.concat(parts, ', ') .. ')'
    end

    local fold_id = 'commit:' .. (commit.sha or sha_short)
    local is_folded = buf:is_folded(fold_id)

    add(sha_short .. ' ' .. msg .. stats, 'GitButlerCommitHash', 'commit', {
      commit = commit,
      sha = commit.sha,
      short_sha = sha_short,
      message = commit.message,
      full_message = commit.full_message,
      author = commit.author_name,
      fold_id = fold_id,
    }, { foldable = true, folded = is_folded })

    if not is_folded and commit.files then
      for _, file in ipairs(commit.files) do
        local status = file.status or 'modified'
        local prefix = status:sub(1, 1):upper()
        local file_stats = ''
        if file.insertions and file.insertions > 0 then file_stats = file_stats .. '+' .. file.insertions end
        if file.deletions and file.deletions > 0 then file_stats = file_stats .. '-' .. file.deletions end
        if file_stats ~= '' then file_stats = '  ' .. file_stats end

        local hl = 'GitButlerFileMod'
        if status == 'added' then hl = 'GitButlerFileAdd'
        elseif status == 'deleted' then hl = 'GitButlerFileDel'
        elseif status == 'renamed' then hl = 'GitButlerFileRenamed'
        end

        add(prefix .. '  ' .. file.path .. file_stats, hl, 'log_file', {
          path = file.path,
          status = status,
          commit_sha = commit.sha,
        }, { indent = 1 })
      end
    end
  end

  add('', nil, 'blank', nil)
  add('d=diff  r=reword  S=squash  q=close  <Tab>=toggle/close-diff', 'GitButlerHelp', 'help', nil)

  return lines
end

---Open the log view for a branch.
---@param branch_name string
function M.open(branch_name)
  cli.show(branch_name, function(err, data)
    if err then
      vim.notify('gitbutler log: ' .. err, vim.log.levels.ERROR)
      return
    end

    if type(data) ~= 'table' then
      vim.notify('gitbutler log: unexpected output', vim.log.levels.WARN)
      return
    end

    local buf = buffer_mod.Buffer.new()
    M.instance = buf

    -- Actions
    buf:on('close', function()
      buf:close()
      M.instance = nil
    end)

    buf:on('refresh', function()
      M.refresh(branch_name)
    end)

    buf:on('toggle_fold', function(b)
      local line = b:get_cursor_line()
      if not line then return end

      -- On file lines, show inline diff in a split below
      if line.type == 'log_file' and line.data and line.data.commit_sha then
        local commit_sha = line.data.commit_sha
        local diff_err, diff_result = cli.run_sync({ 'diff', commit_sha })
        if diff_err then
          vim.notify('gitbutler diff: ' .. diff_err, vim.log.levels.ERROR)
          return
        end

        local diff_lines = vim.split(tostring(diff_result), '\n')
        vim.cmd('belowright split')
        local diff_buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_win_set_buf(0, diff_buf)
        vim.api.nvim_buf_set_lines(diff_buf, 0, -1, false, diff_lines)
        vim.bo[diff_buf].buftype = 'nofile'
        vim.bo[diff_buf].bufhidden = 'wipe'
        vim.bo[diff_buf].filetype = 'gitbutler-diff'

        local ns = vim.api.nvim_create_namespace('gitbutler-diff')
        for i, l in ipairs(diff_lines) do
          if l:match('│%+') then
            vim.api.nvim_buf_add_highlight(diff_buf, ns, 'DiffAdd', i - 1, 0, -1)
          elseif l:match('│%-') then
            vim.api.nvim_buf_add_highlight(diff_buf, ns, 'DiffDelete', i - 1, 0, -1)
          elseif l:match('^[─╮╯╭]') or l:match('^%s*[─╮╯╭]') then
            vim.api.nvim_buf_add_highlight(diff_buf, ns, 'Comment', i - 1, 0, -1)
          end
        end

        vim.keymap.set('n', 'q', '<cmd>close<CR>', { buffer = diff_buf })
        vim.keymap.set('n', '<Tab>', '<cmd>close<CR>', { buffer = diff_buf })
        return
      end

      -- On commit lines, toggle file list
      if line.type == 'commit' and line.data and line.data.fold_id then
        local id = line.data.fold_id
        b.fold_state[id] = not b.fold_state[id]
        local lines = build_lines(b, data)
        b:render(lines)
      end
    end)

    buf:on('describe', function(b)
      local line = b:get_cursor_line()
      if not line or line.type ~= 'commit' or not line.data then return end

      local sha = line.data.sha
      local current = line.data.full_message or line.data.message or ''

      float.input({
        title = 'Reword ' .. (line.data.short_sha or ''),
        content = current ~= '' and vim.split(current, '\n') or nil,
        on_submit = function(message)
          cli.reword(sha, message, function(reword_err, _)
            notify('reword', reword_err)
            if not reword_err then M.refresh(branch_name) end
          end)
        end,
      })
    end)

    buf:on('squash', function(b)
      local line = b:get_cursor_line()
      if not line or line.type ~= 'commit' or not line.data then return end

      cli.squash(line.data.sha, function(squash_err, _)
        notify('squash', squash_err)
        if not squash_err then M.refresh(branch_name) end
      end)
    end)

    buf:on('open_file', function(b)
      local line = b:get_cursor_line()
      if not line then return end

      if line.type == 'log_file' and line.data and line.data.path then
        buf:close()
        M.instance = nil
        vim.cmd('edit ' .. vim.fn.fnameescape(line.data.path))
      end
    end)

    -- Override keymaps for log context
    local log_keymaps = {
      ['q'] = 'close',
      ['r'] = 'refresh',
      ['<Tab>'] = 'toggle_fold',
      ['d'] = 'describe',
      ['S'] = 'squash',
      ['<CR>'] = 'open_file',
    }

    buf:open()

    -- Apply log-specific keymaps (override status defaults)
    for key, action in pairs(log_keymaps) do
      vim.keymap.set('n', key, function()
        local handler = buf.keymaps[action]
        if handler then handler(buf) end
      end, { buffer = buf.buf, nowait = true })
    end

    local lines = build_lines(buf, data)
    buf:render(lines)
  end)
end

---Refresh the log view.
function M.refresh(branch_name)
  if not M.instance then return end
  local buf = M.instance

  cli.show(branch_name, function(err, data)
    if err then
      vim.notify('gitbutler log: ' .. err, vim.log.levels.ERROR)
      return
    end
    if type(data) ~= 'table' then return end
    local lines = build_lines(buf, data)
    buf:render(lines)
  end)
end

return M

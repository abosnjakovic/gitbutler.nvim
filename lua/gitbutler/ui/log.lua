local buffer_mod = require('gitbutler.ui.buffer')
local cli = require('gitbutler.cli')
local float = require('gitbutler.ui.float')

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

---SHA of the commit directly below `sha` in a `but show` payload — its parent
---in the branch's newest-first list. nil at the oldest commit, or when `sha`
---is not in the payload.
---@param data table show output
---@param sha string
---@return string?
function M._parent_sha(data, sha)
  local commits = type(data) == 'table' and data.commits or nil
  if type(commits) ~= 'table' then
    return nil
  end
  for i, c in ipairs(commits) do
    if c.sha == sha then
      return commits[i + 1] and commits[i + 1].sha or nil
    end
  end
  return nil
end

---Build lines from `but show <branch> --json` output.
---Shape: { branch, commits: [{ sha, short_sha, message, full_message, author_name, timestamp, files_changed, insertions, deletions, files }] }
---@param buf table GitButlerBuffer instance (for fold state)
---@param data table show output
function M.build_lines(buf, data)
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

    if not is_folded then
      local body_lines = {}
      if commit.full_message and commit.full_message ~= '' then
        local parts = vim.split(commit.full_message, '\n', { plain = true })
        table.remove(parts, 1)
        while #parts > 0 and parts[#parts]:match('^%s*$') do
          table.remove(parts)
        end
        while #parts > 0 and parts[1]:match('^%s*$') do
          table.remove(parts, 1)
        end
        body_lines = parts
      end

      for _, body_line in ipairs(body_lines) do
        add(body_line, 'GitButlerCommitBody', 'commit_body', nil, { indent = 1 })
      end

      local has_files = commit.files and #commit.files > 0
      if #body_lines > 0 and has_files then
        add('', nil, 'blank', nil, { indent = 1 })
      end
    end

    if not is_folded and commit.files then
      for _, file in ipairs(commit.files) do
        local status = file.status or 'modified'
        local prefix = status:sub(1, 1):upper()
        local file_stats = ''
        if file.insertions and file.insertions > 0 then
          file_stats = file_stats .. '+' .. file.insertions
        end
        if file.deletions and file.deletions > 0 then
          file_stats = file_stats .. '-' .. file.deletions
        end
        if file_stats ~= '' then
          file_stats = '  ' .. file_stats
        end

        local hl = 'GitButlerFileMod'
        if status == 'added' then
          hl = 'GitButlerFileAdd'
        elseif status == 'deleted' then
          hl = 'GitButlerFileDel'
        elseif status == 'renamed' then
          hl = 'GitButlerFileRenamed'
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
  return lines
end

---`<Tab>` on a file row: show that commit in the details pane, or close the
---pane when it is already the one showing. The pane renders landed commits
---through `git show`, which is what this key always showed here — the split
---it replaced ran `but diff <commit_sha>`, never the file's own diff.
---@param b GitButlerBuffer the log buffer the pane splits from
---@param sha string
function M._toggle_commit_details(b, sha)
  local details = require('gitbutler.ui.details')
  local showing = details.win_state.entity or {}
  if details.is_open() and showing.sha == sha then
    details.close()
  else
    details.open(b)
    details.show_commit(sha)
  end
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
    buf.view = 'log'
    M.instance = buf
    -- The watcher refreshes this view from outside the closure, so the branch
    -- it was opened for has to live on the instance.
    buf.branch_name = branch_name

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
      if not line then
        return
      end

      -- File rows: the details pane owns diffs here too. It renders the whole
      -- commit through `git show`, which is what this key always showed —
      -- the split it replaces ran `but diff <commit_sha>`, never the file's
      -- own diff. Pressing it again on the same commit closes the pane.
      --
      -- ponytail: the pane follows the cursor in the status view only
      -- (`Buffer:attach` wires that for `view == 'status'`), so here it
      -- refreshes on the keypress rather than as you move. Wire
      -- `show_for_line` up to `log_file` rows if that starts to grate.
      if line.type == 'log_file' and line.data and line.data.commit_sha then
        M._toggle_commit_details(b, line.data.commit_sha)
        return
      end

      -- On commit lines, toggle file list
      if line.type == 'commit' and line.data and line.data.fold_id then
        local id = line.data.fold_id
        b.fold_state[id] = not b.fold_state[id]
        local lines = M.build_lines(b, data)
        b:render(lines)
      end
    end)

    buf:on('describe', function(b)
      local line = b:get_cursor_line()
      if not line or line.type ~= 'commit' or not line.data then
        return
      end

      local sha = line.data.sha
      local current = line.data.full_message or line.data.message or ''

      float.input({
        title = 'Reword ' .. (line.data.short_sha or ''),
        content = current ~= '' and vim.split(current, '\n') or nil,
        on_submit = function(message)
          cli.reword(sha, message, function(reword_err, _)
            notify('reword', reword_err)
            if not reword_err then
              M.refresh(branch_name)
            end
          end)
        end,
      })
    end)

    buf:on('squash', function(b)
      local line = b:get_cursor_line()
      if not line or line.type ~= 'commit' or not line.data then
        return
      end

      -- `but squash` needs an explicit target: squash the cursor commit into
      -- the one below it. Without a target but only accepts a single branch.
      local parent = M._parent_sha(data, line.data.sha)
      if not parent then
        vim.notify('gitbutler: no commit below this one to squash into', vim.log.levels.WARN)
        return
      end

      cli.squash({ line.data.sha }, parent, function(squash_err, _)
        notify('squash', squash_err)
        if not squash_err then
          M.refresh(branch_name)
        end
      end)
    end)

    buf:on('open_file', function(b)
      local line = b:get_cursor_line()
      if not line then
        return
      end

      if line.type == 'log_file' and line.data and line.data.path then
        buf:close()
        M.instance = nil
        vim.cmd('edit ' .. vim.fn.fnameescape(line.data.path))
      end
    end)

    -- Override keymaps for log context
    local log_keymaps = {
      ['q'] = 'close',
      ['<C-r>'] = 'refresh',
      ['r'] = 'refresh', -- undocumented alias; advertised binding is <C-r>
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
        if handler then
          handler(buf)
        end
      end, { buffer = buf.buf, nowait = true })
    end

    local lines = M.build_lines(buf, data)
    buf:render(lines)
  end)
end

---Refresh the log view.
---@param branch_name string
---@param opts? { done?: fun(), quiet?: boolean }
function M.refresh(branch_name, opts)
  opts = opts or {}
  local function finish()
    if opts.done then
      opts.done()
    end
  end

  if not M.instance then
    finish()
    return
  end
  local buf = M.instance

  cli.show(branch_name, function(err, data)
    if err then
      if not opts.quiet then
        vim.notify('gitbutler log: ' .. err, vim.log.levels.ERROR)
      end
      return finish()
    end
    if type(data) ~= 'table' then
      return finish()
    end
    local lines = M.build_lines(buf, data)
    buf:render(lines)
    finish()
  end)
end

return M

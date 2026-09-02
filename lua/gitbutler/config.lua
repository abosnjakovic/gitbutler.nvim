local M = {}

---@class GitButlerConfig
M.defaults = {
  -- Path to but executable
  cmd = 'but',

  -- How to open the status buffer: 'tab', 'split', 'vsplit', 'float', 'current'
  kind = 'tab',

  -- Floating window dimensions (used when kind = 'float' or for popups)
  -- When true, pressing 'q' (actions.close) quits Neovim instead of just closing the buffer
  quit_neovim_on_quit = false,
  float = {
    relative = 'editor',
    width = 0.8,
    height = 0.7,
    border = 'rounded',
    style = 'minimal',
  },

  -- Input float dimensions (commit messages, branch names)
  input_float = {
    relative = 'cursor',
    width = 60,
    height = 10,
    border = 'rounded',
    style = 'minimal',
  },

  -- Branch picker popup dimensions
  picker = {
    relative = 'cursor',
    width = 40,
    border = 'rounded',
    style = 'minimal',
  },

  -- Auto-refresh the open views when the repository changes underneath them:
  -- filesystem events under .git/ plus focus autocmds. The debounce is in ms —
  -- the minimum gap between two automatic refreshes.
  watch = true,
  watch_debounce = 1000,

  -- What `o` on a commit row opens. One of:
  --   nil / false        -> built-in read-only `git show <sha>` split (default)
  --   'codediff'         -> :CodeDiff <sha>^ <sha>   (esmuellert/codediff.nvim)
  --   'diffview'         -> :DiffviewOpen <sha>^!    (sindrets/diffview.nvim)
  --   'fugitive'         -> :Git show <sha>          (tpope/vim-fugitive)
  --   a string template  -> vim.cmd(template:format(sha, sha)), e.g. 'CodeDiff %s^ %s'
  --   a function(sha)    -> called with the full commit SHA
  commit_diff = nil,

  -- Landed-history section shown below the common base in the main view.
  -- `count` is how many ancestors to load at a time (grows with "load more").
  base_history = {
    count = 15,
  },

  -- The details pane sits beside the status window, or below it when that
  -- column group is too narrow to give the pane at least `min_width` columns.
  -- At the default 50% share, 60 means an editor under 120 columns puts the
  -- pane underneath.
  details = {
    min_width = 60,
  },

  -- Keymaps for status buffer (set to false to disable)
  keymaps = {
    status = {
      -- navigation (official but-tui keys)
      ['j'] = 'cursor_down',
      ['k'] = 'cursor_up',
      ['<Down>'] = 'cursor_down',
      ['<Up>'] = 'cursor_up',
      ['J'] = 'section_down',
      ['K'] = 'section_up',
      ['<C-d>'] = 'jump_down',
      ['<C-u>'] = 'jump_up',
      ['g'] = 'goto_top',
      ['G'] = 'goto_bottom',
      ['t'] = 'goto_branch',
      ['/'] = 'jump_to_id',
      ['<Esc>'] = 'back',
      -- marks
      ['<Space>'] = 'toggle_select',
      -- modes
      ['a'] = 'amend_start',
      ['R'] = 'amend_all',
      ['S'] = 'squash_start',
      ['w'] = 'uncommit',
      ['c'] = 'commit_mode_start',
      ['m'] = 'move_start',
      ['s'] = 'stack_start',
      -- operations (official keys)
      ['n'] = 'insert_empty_commit',
      ['b'] = 'branch_new',
      ['x'] = 'discard',
      ['u'] = 'undo',
      ['U'] = 'redo',
      ['<CR>'] = 'describe',
      ['M'] = 'reword_editor',
      ['f'] = 'toggle_file_list',
      ['F'] = 'toggle_all_file_lists',
      ['y'] = 'copy_selection',
      [':'] = 'but_command',
      ['!'] = 'shell_command',
      ['<C-r>'] = 'refresh',
      ['q'] = 'close',
      ['?'] = 'help',
      ['<Tab>'] = 'toggle_fold',
      -- details pane
      ['d'] = 'details_toggle',
      ['D'] = 'details_toggle_full',
      ['+'] = 'details_grow',
      ['-'] = 'details_shrink',
      ['l'] = 'details_focus',
      ['<Right>'] = 'details_focus',
      -- plugin extras on free keys (see spec keymap table)
      ['o'] = 'open_file',
      ['A'] = 'absorb',
      ['p'] = 'push',
      ['P'] = 'push_all',
      ['v'] = 'pr_create',
      ['V'] = 'pr_toggle_draft',
      ['C'] = 'ci_open',
      ['L'] = 'direct_to_main',
      ['i'] = 'pull',
      ['H'] = 'log',
      ['O'] = 'oplog',
      ['B'] = 'branches',
    },
    ci = {
      ['<CR>'] = 'open_log',
      ['o'] = 'open_in_browser',
      ['R'] = 'rerun',
      ['<C-r>'] = 'refresh',
      ['q'] = 'close',
    },
  },
}

---@type GitButlerConfig
M.values = {}

function M.setup(opts)
  M.values = vim.tbl_deep_extend('force', {}, M.defaults, opts or {})
end

return M

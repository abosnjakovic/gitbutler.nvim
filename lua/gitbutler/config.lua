local M = {}

---@class GitButlerConfig
M.defaults = {
  -- Path to but executable
  cmd = 'but',

  -- How to open the status buffer: 'tab', 'split', 'vsplit', 'float', 'current'
  kind = 'tab',

  -- Floating window dimensions (used when kind = 'float' or for popups)
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

  -- Auto-refresh status buffer on .git/ filesystem changes
  watch = true,
  watch_interval = 1000,

  -- Timeline view settings
  timeline = {
    days = 7,
    limit = 200,
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
      -- marks
      ['<Space>'] = 'toggle_select',
      -- modes
      ['r'] = 'rub_start',
      ['R'] = 'rub_reverse',
      ['c'] = 'commit_mode_start',
      ['m'] = 'move_start',
      ['s'] = 'stack_start',
      -- operations (official keys)
      ['n'] = 'insert_empty_commit',
      ['b'] = 'branch_new',
      ['x'] = 'discard',
      ['u'] = 'undo',
      ['<C-r>'] = 'refresh',
      ['q'] = 'close',
      ['?'] = 'help',
      -- direct actions retained until phase 2 replaces them with modes
      ['S'] = 'squash',
      ['U'] = 'uncommit',
      ['d'] = 'describe',
      ['<Tab>'] = 'toggle_fold',
      -- plugin extras on free keys (see spec keymap table)
      ['o'] = 'open_file',
      ['<CR>'] = 'open_file', -- becomes inline reword in phase 2
      ['A'] = 'absorb',
      ['p'] = 'push',
      ['P'] = 'push_all',
      ['v'] = 'pr_create',
      ['V'] = 'pr_toggle_draft',
      ['C'] = 'ci_open',
      ['L'] = 'direct_to_main',
      ['i'] = 'pull',
      ['T'] = 'timeline',
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

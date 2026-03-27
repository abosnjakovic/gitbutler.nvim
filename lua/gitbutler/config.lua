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

  -- Status buffer sections (can be hidden or start folded)
  sections = {
    branches = { folded = false, hidden = false },
    unassigned = { folded = false, hidden = false },
  },

  -- Keymaps for status buffer (set to false to disable)
  keymaps = {
    status = {
      ['<CR>'] = 'open_file',
      ['s'] = 'assign_to_branch',
      ['a'] = 'absorb',
      ['c'] = 'commit',
      ['A'] = 'amend',
      ['S'] = 'squash',
      ['m'] = 'move',
      ['d'] = 'describe',
      ['u'] = 'undo',
      ['p'] = 'push',
      ['B'] = 'branches',
      ['P'] = 'push_all',
      ['F'] = 'pull',
      ['q'] = 'close',
      ['r'] = 'refresh',
      ['b'] = 'branch_new',
      ['x'] = 'discard',
      ['<Tab>'] = 'toggle_fold',
      ['<Space>'] = 'toggle_select',
      ['l'] = 'log',
      ['O'] = 'oplog',
      ['?'] = 'help',
    },
  },
}

---@type GitButlerConfig
M.values = {}

function M.setup(opts)
  M.values = vim.tbl_deep_extend('force', {}, M.defaults, opts or {})
end

return M

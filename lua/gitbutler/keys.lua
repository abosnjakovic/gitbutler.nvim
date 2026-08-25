-- One list of what every key does, per context.
--
-- Before this module the same binding was described in up to five places —
-- `config.values.keymaps`, the details pane's own keymap table, `hotbar.lua`,
-- `hints.lua`, and the help float's prose — and none was derived from the
-- others. They drifted: the CI view showed status hints, and the details pane
-- showed status help.
--
-- Config still owns which key is bound. This module owns what it is called.

local config = require('gitbutler.config')

local M = {}

---@class KeySpec
---@field key string default binding
---@field action? string handler name, as registered with `Buffer:on`; absent iff `native`
---@field desc string short lowercase phrase for the hotbar and hint line
---@field hotbar? boolean include in the status hotbar
---@field help? string longer line for the `?` float; falls back to `desc`
---@field section? string groups the entry in the `?` float
---@field native? boolean documented but not bound — the key does something
---       useful without a mapping, and mapping it would break that

---@type table<string, KeySpec[]>
M.contexts = {
  status = {
    -- Navigation
    { key = 'j', action = 'cursor_down', desc = 'down', hotbar = true, section = 'Navigation' },
    { key = 'k', action = 'cursor_up', desc = 'up', hotbar = true, section = 'Navigation' },
    { key = '<Down>', action = 'cursor_down', desc = 'down', section = 'Navigation' },
    { key = '<Up>', action = 'cursor_up', desc = 'up', section = 'Navigation' },
    { key = 'J', action = 'section_down', desc = 'next section', section = 'Navigation', help = 'Next section' },
    { key = 'K', action = 'section_up', desc = 'prev section', section = 'Navigation', help = 'Previous section' },
    { key = '<C-d>', action = 'jump_down', desc = 'jump down', section = 'Navigation', help = 'Jump 10 rows' },
    { key = '<C-u>', action = 'jump_up', desc = 'jump up', section = 'Navigation', help = 'Jump 10 rows' },
    { key = 'g', action = 'goto_top', desc = 'top', section = 'Navigation', help = 'Uncommitted area' },
    { key = 'G', action = 'goto_bottom', desc = 'bottom', section = 'Navigation', help = 'Merge base' },
    {
      key = '<Esc>',
      action = 'back',
      desc = 'back',
      section = 'Navigation',
      help = 'Back (exit mode, else clear marks)',
    },
    -- Marks
    {
      key = '<Space>',
      action = 'toggle_select',
      desc = 'mark',
      hotbar = true,
      section = 'Marks',
      help = 'Mark / unmark (homogeneous multi-select)',
    },
    -- Modes
    {
      key = 'a',
      action = 'amend_start',
      desc = 'amend',
      hotbar = true,
      section = 'Modes',
      help = 'Amend mode: uncommitted changes into a commit or branch',
    },
    {
      key = 'R',
      action = 'amend_all',
      desc = 'amend all',
      section = 'Modes',
      help = 'Amend mode with every unassigned file as the source',
    },
    {
      key = 'S',
      action = 'squash_start',
      desc = 'squash',
      hotbar = true,
      section = 'Modes',
      help = 'Squash mode: commits / branches / committed files into a target',
    },
    {
      key = 'w',
      action = 'uncommit',
      desc = 'uncommit',
      section = 'Modes',
      help = 'Uncommit the marked (or cursor) commits / committed files',
    },
    {
      key = 'c',
      action = 'commit_mode_start',
      desc = 'commit',
      hotbar = true,
      section = 'Modes',
      help = 'Commit mode (pick where the commit lands)',
    },
    {
      key = 'm',
      action = 'move_start',
      desc = 'move',
      hotbar = true,
      section = 'Modes',
      help = 'Move mode (reorder / retarget commits)',
    },
    {
      key = 's',
      action = 'stack_start',
      desc = 'stack',
      hotbar = true,
      section = 'Modes',
      help = 'Stack mode (apply / unapply / move)',
    },
    -- Navigation (hotbar order places these after Modes; see hotbar.normal_items)
    {
      key = 't',
      action = 'goto_branch',
      desc = 'branch',
      hotbar = true,
      section = 'Navigation',
      help = 'Go to branch (fuzzy picker)',
    },
    { key = '/', action = 'jump_to_id', desc = 'jump', hotbar = true, section = 'Navigation', help = 'Jump to CLI id' },
    -- Operations
    {
      key = 'n',
      action = 'insert_empty_commit',
      desc = 'empty commit',
      section = 'Operations',
      help = 'Insert empty commit',
    },
    { key = 'b', action = 'branch_new', desc = 'new branch', section = 'Operations', help = 'New branch' },
    {
      key = 'x',
      action = 'discard',
      desc = 'discard',
      hotbar = true,
      section = 'Operations',
      help = 'Discard (confirm)',
    },
    { key = 'u', action = 'undo', desc = 'undo', hotbar = true, section = 'Operations', help = 'Undo (confirm)' },
    { key = 'U', action = 'redo', desc = 'redo', section = 'Operations', help = 'Redo (confirm)' },
    {
      key = '<CR>',
      action = 'describe',
      desc = 'describe',
      section = 'Operations',
      help = 'Describe / reword (float)',
    },
    {
      key = 'M',
      action = 'reword_editor',
      desc = 'reword',
      section = 'Operations',
      help = 'Reword in an editor split',
    },
    {
      key = 'f',
      action = 'toggle_file_list',
      desc = 'files',
      section = 'Operations',
      help = 'Toggle file list (commit)',
    },
    {
      key = 'F',
      action = 'toggle_all_file_lists',
      desc = 'all files',
      section = 'Operations',
      help = 'Toggle file list (all)',
    },
    { key = 'y', action = 'copy_selection', desc = 'copy', section = 'Operations', help = 'Copy sha / path / name' },
    { key = ':', action = 'but_command', desc = 'but command', section = 'Operations', help = 'Run a but command' },
    {
      key = '!',
      action = 'shell_command',
      desc = 'shell command',
      section = 'Operations',
      help = 'Run a shell command',
    },
    { key = '<C-r>', action = 'refresh', desc = 'refresh', section = 'Operations', help = 'Refresh' },
    {
      key = '<Tab>',
      action = 'toggle_fold',
      desc = 'expand',
      section = 'Operations',
      help = 'Expand commit files / inline diff / fold',
    },
    -- Details pane
    {
      key = 'd',
      action = 'details_toggle',
      desc = 'details',
      section = 'Details pane',
      help = 'Toggle the details split',
    },
    {
      key = 'D',
      action = 'details_toggle_full',
      desc = 'fullscreen',
      section = 'Details pane',
      help = 'Toggle the details pane fullscreen',
    },
    { key = '+', action = 'details_grow', desc = 'grow', section = 'Details pane', help = 'Grow the pane' },
    { key = '-', action = 'details_shrink', desc = 'shrink', section = 'Details pane', help = 'Shrink the pane' },
    {
      key = 'l',
      action = 'details_focus',
      desc = 'focus',
      section = 'Details pane',
      help = 'Focus the pane (h/<Esc> focuses back)',
    },
    { key = '<Right>', action = 'details_focus', desc = 'focus', section = 'Details pane' },
    -- Extras
    {
      key = 'o',
      action = 'open_file',
      desc = 'open',
      section = 'Extras',
      help = 'Open under cursor: file → jump to code; commit → diff tool',
    },
    { key = 'A', action = 'absorb', desc = 'absorb', section = 'Extras', help = 'Absorb changes' },
    { key = 'p', action = 'push', desc = 'push', hotbar = true, section = 'Extras', help = 'Push branch' },
    { key = 'P', action = 'push_all', desc = 'push all', section = 'Extras', help = 'Push all' },
    { key = 'v', action = 'pr_create', desc = 'pr', hotbar = true, section = 'Extras', help = 'Create PR' },
    { key = 'V', action = 'pr_toggle_draft', desc = 'pr draft', section = 'Extras', help = 'Toggle PR draft' },
    {
      key = 'i',
      action = 'pull',
      desc = 'pull',
      hotbar = true,
      section = 'Extras',
      help = 'Pull / integrate upstream',
    },
    {
      key = 'L',
      action = 'direct_to_main',
      desc = 'land',
      hotbar = true,
      section = 'Extras',
      help = 'Land directly onto target',
    },
    { key = 'O', action = 'oplog', desc = 'oplog', hotbar = true, section = 'Extras', help = 'Operations log' },
    { key = 'H', action = 'log', desc = 'log', section = 'Extras', help = 'Commit log' },
    { key = 'B', action = 'branches', desc = 'branches', section = 'Extras', help = 'Branch management' },
    { key = 'C', action = 'ci_open', desc = 'ci', section = 'Extras', help = 'CI view' },
    -- Operations (hotbar order places these last; see hotbar.normal_items)
    { key = '?', action = 'help', desc = 'help', hotbar = true, section = 'Operations' },
    { key = 'q', action = 'close', desc = 'quit', hotbar = true, section = 'Operations' },
  },

  -- No `log` context here yet: the log view still binds its keys from its own
  -- `log_keymaps` literal in `log.lua` and describes itself from `hints.log`,
  -- neither of which reads this registry. Wiring it up means deleting
  -- `hints.log`'s per-row entries first — those carry information a flat
  -- registry entry can't (what `<Tab>` means *on this row*) — so it's left
  -- for that work rather than added here unread.

  ci = {
    { key = '<CR>', action = 'open_log', desc = 'open log' },
    { key = 'o', action = 'open_in_browser', desc = 'browser' },
    { key = 'R', action = 'rerun', desc = 'rerun' },
    { key = '<C-r>', action = 'refresh', desc = 'refresh' },
    { key = 'q', action = 'close', desc = 'close' },
  },

  details = {
    -- j/k/g/G are deliberately NOT bound in the pane (see `set_keymap` in
    -- details.lua) so it scrolls line by line in both render modes. Documented
    -- here so the hint line can say what they do; `native = true` keeps them
    -- unbound — see the "native motions" test in keys_spec.lua.
    { key = 'j', native = true, desc = 'line down' },
    { key = 'k', native = true, desc = 'line up' },
    { key = 'g', native = true, desc = 'top' },
    { key = 'G', native = true, desc = 'bottom' },
    -- Curated (`hotbar = true`) entries are declared here, ahead of the rest
    -- of the pane's keys: `hotbar.build` truncates the curated bucket
    -- greedily in this declaration order, so whatever is listed first is
    -- what survives a narrow pane. `comment` and `yank review` are the two
    -- least-guessable keys in the pane (the only two with a `help` string),
    -- so they lead.
    {
      key = 'C',
      action = 'comment_line',
      desc = 'comment',
      hotbar = true,
      help = 'Comment the line under the cursor (empty submit deletes)',
    },
    {
      key = 'Y',
      action = 'yank_comments',
      desc = 'yank review',
      hotbar = true,
      help = 'Yank every comment as a review blob, then clear them',
    },
    { key = ']c', action = 'hunk_next', desc = 'next hunk', hotbar = true },
    { key = '[c', action = 'hunk_prev', desc = 'prev hunk' },
    { key = 'J', action = 'scroll_down', desc = 'scroll' },
    { key = 'K', action = 'scroll_up', desc = 'scroll' },
    { key = '<C-d>', action = 'scroll_page_down', desc = 'scroll 10' },
    { key = '<C-u>', action = 'scroll_page_up', desc = 'scroll 10' },
    { key = '<CR>', action = 'open_hunk', desc = 'open file' },
    { key = 'o', action = 'open_hunk', desc = 'open file' },
    { key = '<Space>', action = 'toggle_mark', desc = 'mark hunk', hotbar = true },
    { key = 'x', action = 'hunk_discard', desc = 'discard', hotbar = true },
    { key = 'y', action = 'hunk_copy', desc = 'copy hunk', hotbar = true },
    { key = 'a', action = 'hunk_amend', desc = 'amend', hotbar = true },
    { key = 'h', action = 'focus_status', desc = 'back' },
    { key = '<Left>', action = 'focus_status', desc = 'back' },
    { key = '<Esc>', action = 'focus_status', desc = 'back' },
    { key = 'd', action = 'close_pane', desc = 'close' },
    { key = 'q', action = 'close_pane', desc = 'close' },
    { key = 'D', action = 'toggle_full', desc = 'fullscreen' },
    { key = '+', action = 'grow', desc = 'grow' },
    { key = '-', action = 'shrink', desc = 'shrink' },
    { key = '?', action = 'help', desc = 'help' },
  },
}

---Registry entries for a context with the user's remapping applied.
---
---A context absent from `config.values.keymaps` — `details`, today — keeps the
---registry's own key. That absence is the whole of "not user-configurable yet";
---there is no branch for it here.
---
---Aliases are why this is two passes rather than a lookup. Several actions are
---bound to more than one key by default (`j` and `<Down>` both scroll down),
---and the registry holds one entry per key. Collapsing the config to one key
---per action would rewrite both entries to whichever key `pairs()` happened to
---yield last.
---@param context string
---@return KeySpec[]
function M.resolved(context)
  local specs = M.contexts[context]
  if not specs then
    return {}
  end
  local overrides = (config.values.keymaps and config.values.keymaps[context]) or nil
  if not overrides then
    return vim.deepcopy(specs)
  end

  -- Every key the config binds, grouped by action. Sorted so a remapped entry
  -- picks the same key on every run.
  local keys_for = {}
  for key, action in pairs(overrides) do
    if action then
      keys_for[action] = keys_for[action] or {}
      table.insert(keys_for[action], key)
    end
  end
  for _, list in pairs(keys_for) do
    table.sort(list)
  end

  local claimed = {}
  local out = {}

  -- A native entry binds nothing, so config — which only ever talks about
  -- bound keys — has no say over it. It survives untouched, whether or not
  -- this context happens to have a config table.
  for i, spec in ipairs(specs) do
    if spec.native then
      out[i] = vim.deepcopy(spec)
      claimed[spec.key] = true
    end
  end

  -- Pass one: an entry whose own key is still bound to its own action keeps it.
  -- This is every entry in the common case where the user remapped nothing.
  for i, spec in ipairs(specs) do
    if not out[i] then
      for _, key in ipairs(keys_for[spec.action] or {}) do
        if key == spec.key then
          claimed[key] = true
          out[i] = vim.deepcopy(spec)
          break
        end
      end
    end
  end

  -- Pass two: an entry whose key the user moved takes the first key still
  -- unclaimed for its action. An entry with none left was disabled, and
  -- disappears from every surface that documents it.
  for i, spec in ipairs(specs) do
    if not out[i] then
      for _, key in ipairs(keys_for[spec.action] or {}) do
        if not claimed[key] then
          claimed[key] = true
          local copy = vim.deepcopy(spec)
          copy.key = key
          out[i] = copy
          break
        end
      end
    end
  end

  -- Compact, preserving registry order — the hotbar's ordering comes from it.
  local resolved = {}
  for i = 1, #specs do
    if out[i] then
      table.insert(resolved, out[i])
    end
  end
  return resolved
end

return M

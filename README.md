# gitbutler.nvim

A neovim interface for [Git Butler](https://gitbutler.com) virtual branches. Manage parallel branches, assign files, commit, absorb, squash, reword, and push — all from a buffer-based UI without leaving your editor.

Zero dependencies. Requires neovim 0.10+ and the [`but` CLI](https://docs.gitbutler.com/cli-overview).

<img width="2066" height="1202" alt="image" src="https://github.com/user-attachments/assets/a32f66e2-eb5b-49ac-a7e4-eeb9d823731f" />


## Installation

Install the `but` CLI first:

```sh
brew install gitbutler
```

Then initialise Git Butler in your repository:

```sh
cd your-repo
but setup
```

### lazy.nvim

```lua
{
  'abosnjakovic/gitbutler.nvim',
  config = function()
    require('gitbutler').setup()
  end,
}
```

### vim.pack (native packages)

```lua
vim.pack.add { 'https://github.com/abosnjakovic/gitbutler.nvim' }
require('gitbutler').setup()
```

### Local development

```lua
vim.opt.rtp:prepend(vim.fn.expand('~/path/to/gitbutler.nvim'))
require('gitbutler').setup()
```

## Usage

Open the status buffer with `:Butler` or bind it to a key:

```lua
vim.keymap.set('n', '<leader>bb', ':Butler<CR>', { desc = 'gitbutler' })
```

### Commands

`:Butler` toggles the status view. `:ButlerBranches` opens the branch management popup. `:ButlerLog [branch]` shows the commit log for a branch (defaults to the first applied branch). `:ButlerOplog` opens the operations history. `:ButlerAbsorb`, `:ButlerPush`, `:ButlerPull`, and `:ButlerUndo` run the corresponding operations directly.

### Status buffer keybindings

```
<CR>     Open file under cursor
s        Assign file to a branch (inline picker)
c        Commit to the branch under cursor
a        Absorb uncommitted changes into logical commits
A        Amend into HEAD commit of branch
S        Squash commit into its parent
m        Move commit to a different branch (picker)
d        Describe/reword a commit or rename a branch
u        Undo last operation
p        Push the branch under cursor
P        Push all branches
b        Create a new branch
B        Branch management popup
l        Commit log for the branch under cursor
O        Operations log
x        Discard file changes (with confirmation)
<Tab>    Inline diff on files, fold toggle on branch headers
r        Refresh
q        Close
?        Help
```

### Branch management (B)

The branch popup lists applied and unapplied branches. From within:

```
a        Apply an unapplied branch to the workspace
u        Unapply (stash) an applied branch
n        Create a new branch
d        Delete a branch (with confirmation)
r        Rename a branch
q/Esc    Close
```

### Commit log (l)

Shows commit history with per-file stats. Commits are foldable to reveal their changed files.

```
<Tab>    Toggle file list / inline diff on files
d        Reword commit message
S        Squash commit into parent
<CR>     Open file
q        Close
```

### Operations log (O)

Browse the full operations history. Restore to any previous state or create manual snapshots.

```
r        Restore to snapshot (with confirmation)
s        Create a new snapshot
q/Esc    Close
```

## Configuration

All options are optional. Defaults are shown below:

```lua
require('gitbutler').setup({
  cmd = 'but',
  kind = 'tab',              -- 'tab', 'split', 'vsplit', 'float', 'current'

  float = {
    relative = 'editor',
    width = 0.8,
    height = 0.7,
    border = 'rounded',
  },

  keymaps = {
    status = {
      -- Set any key to false to disable it.
      -- Override values to remap actions.
      ['<CR>'] = 'open_file',
      ['s'] = 'assign_to_branch',
      ['c'] = 'commit',
      -- ... see lua/gitbutler/config.lua for the full list
    },
  },
})
```

## How it works

The plugin talks to the `but` CLI exclusively through `but <command> --json`, which returns structured data. There is no git output parsing. The architecture has three layers:

`cli.lua` wraps every `but` subcommand with `vim.system()` for async execution and `vim.json.decode()` for parsing. All other modules go through this layer.

`ui/` modules handle rendering. `buffer.lua` is the managed scratch buffer with collapsible sections. `float.lua` provides floating windows for input and pickers. `status.lua`, `log.lua`, `branch.lua`, and `oplog.lua` build the specific views.

`actions.lua` connects keybindings to CLI operations and manages the interaction flow (inline pickers, input floats, confirmations, refresh cycles).

## Running tests

```sh
make test
```

Tests run in an isolated neovim instance (`--clean --headless`) with no user config loaded. CI runs against both neovim stable and nightly.

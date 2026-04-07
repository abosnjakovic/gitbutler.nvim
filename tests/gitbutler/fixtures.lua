-- Test fixtures: real JSON structures from `but` CLI output.
-- Captured from actual but commands to ensure our parsing matches reality.

local M = {}

-- `but status --json -f -v` with one stack, one branch, one commit, committed files, and unassigned changes
M.status_full = {
  unassignedChanges = {
    {
      cliId = 'up',
      filePath = 'neovim/.config/nvim/plugin/git.lua',
      changeType = 'modified',
    },
    {
      cliId = 'qu',
      filePath = 'plan.md',
      changeType = 'modified',
    },
  },
  stacks = {
    {
      cliId = 'g0',
      assignedChanges = {
        {
          cliId = 'ac',
          filePath = 'src/pending.lua',
          changeType = 'added',
        },
      },
      branches = {
        {
          cliId = 'br',
          name = 'feature-auth',
          commits = {
            {
              cliId = 'c4',
              commitId = 'c4d75dfd95bf28d3ce1b6dc1a99bb96338aae8fa',
              createdAt = '2026-03-24T02:31:23+00:00',
              message = 'add login endpoint',
              authorName = 'Adam Bosnjakovic',
              authorEmail = 'adam@adimension.io',
              conflicted = false,
              reviewId = vim.NIL,
              changes = {
                {
                  cliId = 'c4:xw',
                  filePath = 'src/auth.lua',
                  changeType = 'added',
                },
                {
                  cliId = 'c4:kw',
                  filePath = 'src/middleware.lua',
                  changeType = 'added',
                },
              },
            },
            {
              cliId = 'a1',
              commitId = 'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0',
              createdAt = '2026-03-23T10:00:00+00:00',
              message = 'initial auth setup\nwith multiline description',
              authorName = 'Adam Bosnjakovic',
              authorEmail = 'adam@adimension.io',
              conflicted = false,
              reviewId = vim.NIL,
              changes = nil,
            },
          },
          upstreamCommits = {},
          branchStatus = 'unpushedCommits',
          reviewId = vim.NIL,
          ci = vim.NIL,
        },
      },
    },
  },
  mergeBase = {
    cliId = '',
    commitId = 'a89ff8ca312fd20cbc4549150551fbc17f6ccad4',
    createdAt = '2026-03-24T02:30:43+00:00',
    message = 'Initial empty commit\n',
    authorName = 'Adam Bosnjakovic',
    authorEmail = 'adam@adimension.io',
    conflicted = vim.NIL,
    reviewId = vim.NIL,
    changes = vim.NIL,
  },
  upstreamState = {
    behind = 0,
    latestCommit = {
      cliId = '',
      commitId = 'a89ff8ca312fd20cbc4549150551fbc17f6ccad4',
    },
    lastFetched = vim.NIL,
  },
}

-- `but status --json -f -v` with empty workspace
M.status_empty = {
  unassignedChanges = {},
  stacks = {},
  mergeBase = {
    cliId = '',
    commitId = 'aaa',
    message = 'init\n',
  },
  upstreamState = { behind = 0 },
}

-- `but status --json -f -v` with upstream behind
M.status_behind = {
  unassignedChanges = {},
  stacks = {},
  mergeBase = { cliId = '', commitId = 'aaa', message = 'init\n' },
  upstreamState = { behind = 3 },
}

-- `but branch --json` with applied and unapplied branches
M.branch_list = {
  appliedStacks = {
    {
      id = 'c58ded9a-0916-4ee5-8fbc-b364c93d9cde',
      heads = {
        {
          name = 'feature-auth',
          reviews = {},
          lastCommitAt = 1774319483000,
          commitsAhead = vim.NIL,
          lastAuthor = {
            name = 'Adam Bosnjakovic',
            email = 'adam@adimension.io',
          },
          mergesCleanly = true,
        },
      },
    },
  },
  branches = {
    {
      name = 'old-experiment',
      reviews = {},
      hasLocal = false,
      lastCommitAt = 1713308917000,
      commitsAhead = 83,
      lastAuthor = {
        name = 'Adam Bosnjakovic',
        email = 'adam@adimension.io',
      },
      mergesCleanly = false,
    },
  },
}

-- `but branch --json` with no branches
M.branch_list_empty = {
  appliedStacks = {},
  branches = {},
}

-- `but show <branch> --json` with commits and file stats
M.show_branch = {
  branch = 'feature-auth',
  commits = {
    {
      sha = '9331c55fb5b4f279474e60e07f106a9b354f8cad',
      short_sha = '9331c55fb',
      message = 'add login endpoint',
      full_message = 'add login endpoint\n\nImplements the /login route with JWT',
      author_name = 'Adam Bosnjakovic',
      author_email = 'adam@adimension.io',
      timestamp = 1774318542,
      files_changed = 3,
      insertions = 120,
      deletions = 5,
      files = {
        { path = 'src/auth.lua', status = 'added', insertions = 80, deletions = 0 },
        { path = 'src/middleware.lua', status = 'added', insertions = 35, deletions = 0 },
        { path = 'src/config.lua', status = 'modified', insertions = 5, deletions = 5 },
      },
    },
    {
      sha = 'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0',
      short_sha = 'a1b2c3d4e',
      message = 'initial setup',
      full_message = 'initial setup',
      author_name = 'Adam Bosnjakovic',
      author_email = 'adam@adimension.io',
      timestamp = 1774300000,
      files_changed = 1,
      insertions = 10,
      deletions = 0,
      files = {
        { path = 'README.md', status = 'added', insertions = 10, deletions = 0 },
      },
    },
  },
}

-- `but show <branch> --json` with no commits
M.show_branch_empty = {
  branch = 'empty-branch',
  commits = {},
}

-- `but oplog list --json`
M.oplog = {
  {
    id = '06cdde9f3a78f01ddbda140d9e7d4660d3a4fbe9',
    createdAt = 1774318542,
    details = {
      version = 3,
      operation = 'CreateCommit',
      title = 'CreateCommit',
      body = vim.NIL,
      trailers = {},
    },
  },
  {
    id = 'abc12345def67890abc12345def67890abc12345',
    createdAt = 1774318000,
    details = {
      version = 3,
      operation = 'MoveCommit',
      title = 'MoveCommit',
      body = 'moved c4d75df to bugfix branch',
      trailers = {},
    },
  },
}

-- empty oplog
M.oplog_empty = {}

-- Simulated parsed output from git log --all for timeline view
M.timeline_commits = {
  {
    sha = 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2',
    short_sha = 'a1b2c3d',
    author = 'adam',
    date = '2026-04-08',
    refs = 'origin/main, main',
    message = 'Fix auth bug',
  },
  {
    sha = 'f4e5d6c7a8b9f4e5d6c7a8b9f4e5d6c7a8b9f4e5',
    short_sha = 'f4e5d6c',
    author = 'sarah',
    date = '2026-04-08',
    refs = 'feat/ui',
    message = 'Update sidebar layout',
  },
  {
    sha = '8c9d0e1f2a3b8c9d0e1f2a3b8c9d0e1f2a3b8c9d',
    short_sha = '8c9d0e1',
    author = 'adam',
    date = '2026-04-07',
    refs = '',
    message = 'Add API endpoint',
  },
}

M.timeline_commits_empty = {}

-- Simulated parsed output from git diff-tree --stat
M.timeline_diff_tree = {
  { path = 'src/auth.lua', status = 'M' },
  { path = 'src/token.lua', status = 'A' },
}

return M

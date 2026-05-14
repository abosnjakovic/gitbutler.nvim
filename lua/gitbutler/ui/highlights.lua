local M = {}

function M.setup()
  local groups = {
    GitButlerBranch = { link = 'Title' },
    GitButlerBranchApplied = { link = 'String' },
    GitButlerBranchUnapplied = { link = 'Comment' },
    GitButlerCommitHash = { link = 'Identifier' },
    GitButlerCommitMessage = { link = 'Normal' },
    GitButlerCommitBody = { link = 'Comment' },
    GitButlerSection = { link = 'Label' },
    GitButlerFileMod = { link = 'diffChanged' },
    GitButlerFileAdd = { link = 'diffAdded' },
    GitButlerFileDel = { link = 'diffRemoved' },
    GitButlerFileRenamed = { link = 'diffChanged' },
    GitButlerUnassigned = { link = 'WarningMsg' },
    GitButlerHelp = { link = 'Comment' },
    GitButlerHelpKey = { link = 'Identifier' },
    GitButlerSelected = { link = 'Visual' },
    GitButlerPickerSelected = { link = 'CursorLine' },
    GitButlerPickerBranch = { link = 'String' },
    GitButlerTimelineDate = { link = 'Title' },
    GitButlerTimelineAuthor = { link = 'Special' },
    GitButlerTimelineRef = { link = 'Comment' },
  }

  for name, def in pairs(groups) do
    vim.api.nvim_set_hl(0, name, vim.tbl_extend('keep', def, { default = true }))
  end

  vim.api.nvim_set_hl(0, 'GitButlerCIQueued', { link = 'Comment', default = true })
  vim.api.nvim_set_hl(0, 'GitButlerCIRunning', { link = 'WarningMsg', default = true })
  vim.api.nvim_set_hl(0, 'GitButlerCIPass', { link = 'DiagnosticOk', default = true })
  vim.api.nvim_set_hl(0, 'GitButlerCIFail', { link = 'DiagnosticError', default = true })
  vim.api.nvim_set_hl(0, 'GitButlerCIUnknown', { link = 'Comment', default = true })
end

return M

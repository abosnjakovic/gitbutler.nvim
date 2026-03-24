local M = {}

function M.setup()
  local groups = {
    GitButlerBranch = { link = 'Title' },
    GitButlerBranchApplied = { link = 'String' },
    GitButlerBranchUnapplied = { link = 'Comment' },
    GitButlerCommitHash = { link = 'Identifier' },
    GitButlerCommitMessage = { link = 'Normal' },
    GitButlerSection = { link = 'Label' },
    GitButlerFileMod = { link = 'diffChanged' },
    GitButlerFileAdd = { link = 'diffAdded' },
    GitButlerFileDel = { link = 'diffRemoved' },
    GitButlerFileRenamed = { link = 'diffChanged' },
    GitButlerUnassigned = { link = 'WarningMsg' },
    GitButlerHelp = { link = 'Comment' },
    GitButlerHelpKey = { link = 'Special' },
    GitButlerPickerSelected = { link = 'CursorLine' },
    GitButlerPickerBranch = { link = 'String' },
  }

  for name, def in pairs(groups) do
    vim.api.nvim_set_hl(0, name, vim.tbl_extend('keep', def, { default = true }))
  end
end

return M

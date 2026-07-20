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
    GitButlerHelp = { link = 'Comment' },
    GitButlerHelpKey = { link = 'Identifier' },
    GitButlerSelected = { link = 'Visual' },
    GitButlerPickerSelected = { link = 'CursorLine' },
    GitButlerPickerBranch = { link = 'String' },
    GitButlerTimelineDate = { link = 'Title' },
    GitButlerTimelineAuthor = { link = 'Special' },
    GitButlerTimelineRef = { link = 'Comment' },
    GitButlerCIQueued = { link = 'Comment' },
    GitButlerCIRunning = { link = 'WarningMsg' },
    GitButlerCIPass = { link = 'DiagnosticOk' },
    GitButlerCIFail = { link = 'DiagnosticError' },
    GitButlerCIUnknown = { link = 'Comment' },
    GitButlerGraphConnector = { link = 'Comment' },
    GitButlerCliId = { link = 'Function' },
    GitButlerMark = { link = 'IncSearch' },
    GitButlerUpstream = { link = 'WarningMsg' },
    GitButlerCommitDotPushed = { link = 'DiagnosticOk' },
    GitButlerCommitDotIntegrated = { link = 'Special' },
    GitButlerCommitDotModified = { link = 'DiagnosticOk' },
    GitButlerModeNormal = { link = 'StatusLine' },
    GitButlerModeRub = { link = 'DiffAdd' },
    GitButlerModeCommit = { link = 'DiffAdd' },
    GitButlerModeMove = { link = 'DiffChange' },
    GitButlerModeStack = { link = 'DiffChange' },
    GitButlerModeSource = { link = 'Visual' },
    GitButlerVerbPill = { link = 'IncSearch' },
    GitButlerDimmed = { link = 'Comment' },
    GitButlerDetailFile = { link = 'Title' },
    GitButlerDetailHunk = { link = 'Comment' },
    GitButlerDetailGutter = { link = 'LineNr' },
    GitButlerDetailSelected = { link = 'WarningMsg' },
  }

  for name, def in pairs(groups) do
    vim.api.nvim_set_hl(0, name, vim.tbl_extend('keep', def, { default = true }))
  end
end

return M

-- Simple test runner. Run with:
--   nvim --clean --headless -u tests/minimal_init.lua -l tests/run.lua

-- Load all test modules (each registers tests via helpers)
require('tests.gitbutler.status_view_spec')
require('tests.gitbutler.branch_data_spec')
require('tests.gitbutler.change_type_spec')
require('tests.gitbutler.log_spec')
require('tests.gitbutler.oplog_spec')
require('tests.gitbutler.selection_spec')
require('tests.gitbutler.action_spec')
require('tests.gitbutler.timeline_spec')
require('tests.gitbutler.status_glyph_spec')
require('tests.gitbutler.forge_init_spec')
require('tests.gitbutler.forge_gh_spec')
require('tests.gitbutler.ci_view_spec')
require('tests.gitbutler.direct_to_main_spec')
require('tests.gitbutler.graph_spec')

-- Summary
local h = require('tests.gitbutler.helpers')
local pass, fail = h.summary()

print(string.format('\n%d passed, %d failed\n', pass, fail))
if fail > 0 then
  vim.cmd('cquit 1')
else
  vim.cmd('qall')
end

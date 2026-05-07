std = 'lua51+luajit'

globals = {
  'vim',
}

read_globals = {
  'describe',
  'it',
  'setup',
  'after_each',
  'assert',
}

-- Callback signatures often ignore some arguments by convention
-- (e.g. `function(_, _, opts)`). Don't flag those.
unused_args = false

-- Allow self-as-first-argument idioms in OO methods
self = false

-- Line length is handled by stylua, not luacheck
max_line_length = false

-- The `_` underscore is conventionally a throwaway variable
ignore = { '212/_' }

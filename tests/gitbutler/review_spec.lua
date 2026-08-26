local h = require('tests.gitbutler.helpers')
local review = require('gitbutler.review')

print('\n=== Review store tests ===')

local function anchor(over)
  local a = {
    scope = 'commit',
    ref = '9e9dcf55d3ef69f49c7d67d7208ad4b422bebad7',
    subject = 'fix: keep the gutter',
    path = 'lua/gitbutler/ui/details.lua',
    side = 'new',
    line = 196,
    captured = '+          local entity = { cli_id = id, path = path }',
  }
  over = over or {}
  for k, v in pairs(over) do
    a[k] = v
  end
  -- Workaround for Lua behavior: {ref = nil} creates no entry in the table.
  -- If override has 'scope' but no 'ref', assume ref was explicitly nil
  if over.scope and not over.ref and over.scope == 'uncommitted' then
    a.ref = nil
  end
  -- Same for subject when explicitly passed with scope='uncommitted'
  if over.scope == 'uncommitted' and over.path and not over.subject then
    a.subject = nil
  end
  return a
end

-- The key is what makes one comment per line true. Two notes on the same line
-- number but opposite sides of the diff are different lines in different files
-- of history, so they must not collide.
h.test('review: side is part of the identity of a line', function()
  review.clear()
  review.set(anchor({ side = 'new' }), 'on the added line')
  review.set(anchor({ side = 'old' }), 'on the removed line')
  h.assert_eq(2, #review.comments)
  h.assert_eq('on the added line', review.get(anchor({ side = 'new' })).text)
  h.assert_eq('on the removed line', review.get(anchor({ side = 'old' })).text)
end)

-- Uncommitted changes have no ref. An empty ref is a real scope, not a missing
-- value, so it must key distinctly rather than matching everything.
h.test('review: an uncommitted anchor does not collide with a committed one', function()
  review.clear()
  review.set(anchor({}), 'on the commit')
  review.set(anchor({ scope = 'uncommitted', ref = nil, subject = nil }), 'on the working tree')
  h.assert_eq(2, #review.comments)
  h.assert_eq('on the working tree', review.get(anchor({ scope = 'uncommitted', ref = nil })).text)
end)

-- Re-commenting is an edit, not a second note. The captured line refreshes too:
-- the note is about the line as it reads now.
h.test('review: set replaces in place and refreshes the captured line', function()
  review.clear()
  review.set(anchor({}), 'first take')
  review.set(anchor({ captured = '+          local entity = { cli_id = id }' }), 'second take')
  h.assert_eq(1, #review.comments)
  h.assert_eq('second take', review.comments[1].text)
  h.assert_eq('+          local entity = { cli_id = id }', review.comments[1].captured)
end)

h.test('review: remove deletes the comment and reports whether it did', function()
  review.clear()
  review.set(anchor({}), 'a note')
  h.assert_truthy(review.remove(anchor({})))
  h.assert_eq(0, #review.comments)
  h.assert_falsy(review.remove(anchor({})), 'removing a missing comment reports false')
end)

-- The key is the whole linkage between the store and the renderer, and both
-- sides build it. If it drifts, the pane renders no comments and nothing fails.
h.test('review: row_key is the format both sides of the seam agree on', function()
  h.assert_eq('src/auth.lua:new:2', review.row_key('src/auth.lua', 'new', 2))
  h.assert_eq('src/auth.lua:old:21', review.row_key('src/auth.lua', 'old', 21))
end)

-- build() looks rows up by path/side/line only, because it already knows which
-- diff it is rendering. Comments from other diffs must not leak into it.
h.test('review: for_entity returns only this diff, keyed path:side:line', function()
  review.clear()
  review.set(anchor({}), 'this diff')
  review.set(anchor({ ref = 'abc1234', line = 12 }), 'another commit')
  review.set(anchor({ scope = 'uncommitted', ref = nil }), 'the working tree')

  local found = review.for_entity('commit', '9e9dcf55d3ef69f49c7d67d7208ad4b422bebad7')
  local n = 0
  for _ in pairs(found) do
    n = n + 1
  end
  h.assert_eq(1, n)
  h.assert_eq('this diff', found['lua/gitbutler/ui/details.lua:new:196'].text)
end)

h.test('review: for_entity matches an uncommitted scope on a nil ref', function()
  review.clear()
  review.set(anchor({ scope = 'uncommitted', ref = nil, path = 'src/app.rs', line = 88 }), 'unwrap')
  local found = review.for_entity('uncommitted', nil)
  h.assert_eq('unwrap', found['src/app.rs:new:88'].text)
end)

-- Y reports how many notes it took and how many were known-stale. Staleness is
-- written onto the record by build(), so counts() only reads it.
h.test('review: counts reports the total and the stale subset', function()
  review.clear()
  review.set(anchor({}), 'fresh')
  review.set(anchor({ line = 200 }), 'moved')
  review.comments[2].stale = true
  local total, stale = review.counts()
  h.assert_eq(2, total)
  h.assert_eq(1, stale)
end)

h.test('review: clear empties the store', function()
  review.clear()
  review.set(anchor({}), 'a note')
  review.clear()
  h.assert_eq(0, #review.comments)
  local total, stale = review.counts()
  h.assert_eq(0, total)
  h.assert_eq(0, stale)
end)

-- This string is the contract. It is what gets pasted into an agent, so it is
-- asserted whole rather than probed field by field — a formatting change that
-- breaks an agent's ability to locate the line should fail here.
h.test('review: format renders the blob that gets pasted', function()
  review.clear()
  review.set({
    scope = 'commit',
    ref = '9e9dcf55d3ef69f49c7d67d7208ad4b422bebad7',
    subject = 'fix: keep the gutter',
    path = 'lua/gitbutler/ui/details.lua',
    side = 'new',
    line = 196,
    captured = '+          local entity = { cli_id = id, path = path }',
  }, 'This drops the line numbers.\nStore old/new on the row.')
  review.set({
    scope = 'uncommitted',
    ref = nil,
    path = 'src/app.rs',
    side = 'old',
    line = 88,
    captured = '-    let cfg = Config::load().unwrap();',
  }, 'unwrap in a load path.')
  review.comments[2].stale = true

  local expected = table.concat({
    'Review — 2 comments on fix/graph-tab-details',
    '',
    'lua/gitbutler/ui/details.lua:196  (9e9dcf5 · fix: keep the gutter · added)',
    '  +          local entity = { cli_id = id, path = path }',
    '  > This drops the line numbers.',
    '    Store old/new on the row.',
    '',
    'src/app.rs:88  (uncommitted · removed · stale)',
    '  -    let cfg = Config::load().unwrap();',
    '  > unwrap in a load path.',
  }, '\n')
  h.assert_eq(expected, review.format('fix/graph-tab-details'))
end)

-- The branch is a label on the review, not a property of any comment, so the
-- blob has to read correctly without one.
h.test('review: format drops the branch clause when there is no branch', function()
  review.clear()
  review.set({
    scope = 'branch',
    ref = 'feat/visual-overhaul',
    path = 'src/main.rs',
    side = 'new',
    line = 4,
    captured = ' fn main() {',
  }, 'why here?')
  local expected = table.concat({
    'Review — 1 comment',
    '',
    'src/main.rs:4  (feat/visual-overhaul · context)',
    '   fn main() {',
    '  > why here?',
  }, '\n')
  h.assert_eq(expected, review.format(nil))
end)

h.test('review: format of an empty store is the empty string', function()
  review.clear()
  h.assert_eq('', review.format('any-branch'))
end)

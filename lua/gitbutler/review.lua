-- Comment store for the details pane's review workflow: one note per diff
-- line, drained to the clipboard by `Y`.
--
-- Pure by design — no windows, no extmarks, no keymaps, no CLI. The pane
-- rebuilds on every status-cursor move, every hunk selection and every watch
-- refresh, and `details.win_state` is reset on each entity change, so a review
-- in progress has to live somewhere that outlives all of it.

local M = {}

---@class ReviewAnchor
---@field scope 'commit'|'branch'|'uncommitted'
---@field ref? string sha, branch name, or nil for uncommitted changes
---@field subject? string commit subject, when the row knew one
---@field path string
---@field side 'new'|'old' which side of the diff the line belongs to
---@field line integer line number on that side
---@field captured string the diff line's text when the comment was written

---@class ReviewComment: ReviewAnchor
---@field text string the comment body
---@field stale? boolean set by details.build when `captured` stops matching

---@type ReviewComment[]
M.comments = {}

---Stable identity for a commented line. An absent `ref` is an uncommitted
---change, which is a real scope rather than a missing value, so it keys as an
---empty segment instead of being skipped.
---@param anchor ReviewAnchor
---@return string
function M.key(anchor)
  return table.concat({
    anchor.scope or 'uncommitted',
    anchor.ref or '',
    anchor.path or '',
    anchor.side or 'new',
    tostring(anchor.line or 0),
  }, ':')
end

---ponytail: linear scan. `get` and `remove` run once per keypress and the
---store holds one review's worth of notes; an index would be a second
---structure to keep in step with the array for no measurable gain.
---@param anchor ReviewAnchor
---@return ReviewComment?
---@return integer? index
function M.get(anchor)
  local key = M.key(anchor)
  for i, c in ipairs(M.comments) do
    if M.key(c) == key then
      return c, i
    end
  end
  return nil, nil
end

---Insert, or replace in place when this line already has a comment. Replacing
---refreshes `captured` and clears `stale`: re-commenting a line means the line
---as it reads now is what the note is about.
---@param anchor ReviewAnchor
---@param text string
function M.set(anchor, text)
  local existing = M.get(anchor)
  if existing then
    existing.subject = anchor.subject
    existing.captured = anchor.captured
    existing.stale = nil
    existing.text = text
    return
  end
  table.insert(M.comments, {
    scope = anchor.scope,
    ref = anchor.ref,
    subject = anchor.subject,
    path = anchor.path,
    side = anchor.side,
    line = anchor.line,
    captured = anchor.captured,
    text = text,
  })
end

---@param anchor ReviewAnchor
---@return boolean removed
function M.remove(anchor)
  local _, index = M.get(anchor)
  if not index then
    return false
  end
  table.remove(M.comments, index)
  return true
end

---The key `for_entity` returns and `details.build` looks rows up by. One
---function so the two sides of that seam cannot drift apart silently — a
---mismatch renders no comments at all, with nothing failing.
---@param path string
---@param side 'new'|'old'
---@param line integer
---@return string
function M.row_key(path, side, line)
  return path .. ':' .. side .. ':' .. tostring(line)
end

---The comments belonging to one open diff, keyed `path:side:line`. `build()`
---already knows the scope and ref it is rendering, so rows look themselves up
---without rebuilding the full key per line.
---@param scope string
---@param ref? string
---@return table<string, ReviewComment>
function M.for_entity(scope, ref)
  local out = {}
  for _, c in ipairs(M.comments) do
    if c.scope == scope and (c.ref or '') == (ref or '') then
      out[M.row_key(c.path, c.side, c.line)] = c
    end
  end
  return out
end

---@return integer total
---@return integer stale
function M.counts()
  local stale = 0
  for _, c in ipairs(M.comments) do
    if c.stale then
      stale = stale + 1
    end
  end
  return #M.comments, stale
end

function M.clear()
  M.comments = {}
end

---How the note's line reads in the diff, derived rather than stored: a context
---line anchors to the new side like an addition, so `side` alone cannot tell
---them apart.
---@param captured string
---@return string
local function side_word(captured)
  local marker = (captured or ''):sub(1, 1)
  if marker == '+' then
    return 'added'
  elseif marker == '-' then
    return 'removed'
  end
  return 'context'
end

---What the comment is anchored to, in the shortest form that stays unambiguous.
---@param c ReviewComment
---@return string
local function ref_label(c)
  if c.scope == 'commit' then
    return (c.ref or ''):sub(1, 7)
  elseif c.scope == 'branch' then
    return c.ref or 'branch'
  end
  return 'uncommitted'
end

---The clipboard blob. `path:line` leads every block because a terminal makes it
---clickable and an agent resolves it natively, so a note lands on the code
---without a round trip about where it points.
---@param branch? string label for the header; omitted when nil
---@return string
function M.format(branch)
  if #M.comments == 0 then
    return ''
  end

  local blocks = {
    'Review — '
      .. #M.comments
      .. ' comment'
      .. (#M.comments == 1 and '' or 's')
      .. (branch and (' on ' .. branch) or ''),
  }

  for _, c in ipairs(M.comments) do
    local meta = { ref_label(c) }
    if c.subject and c.subject ~= '' then
      table.insert(meta, c.subject)
    end
    table.insert(meta, side_word(c.captured))
    if c.stale then
      table.insert(meta, 'stale')
    end

    local lines = {
      c.path .. ':' .. c.line .. '  (' .. table.concat(meta, ' · ') .. ')',
      '  ' .. (c.captured or ''),
    }
    for i, body in ipairs(vim.split(c.text or '', '\n', { plain = true })) do
      table.insert(lines, (i == 1 and '  > ' or '    ') .. body)
    end
    table.insert(blocks, table.concat(lines, '\n'))
  end

  return table.concat(blocks, '\n\n')
end

return M

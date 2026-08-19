--- Allocate LaTeX table column widths from measured cell content.
--
-- Requires pandoc >= 2.17 and Lua 5.3+ (`utf8.len`).
--
-- 2.17, not 2.10. The Table AST itself arrived in 2.10, but its LUA marshalling
-- did not: `TableHead.rows`, `Row.cells` and `Cell.col_span` were only exposed
-- to filters in 2.17 (jgm/pandoc#7718). On 2.16.2 this filter dies with
-- "attempt to index a nil value" the moment it walks a row — verified, not
-- inferred. Guarding at 2.10 promised a range that crashes.
--
-- WHAT PANDOC DOES WITHOUT THIS FILTER
--
-- For a pipe table, pandoc derives relative column widths from the number of
-- DASHES you type in the separator row, and only when a source line exceeds
-- `--columns`. So `|:-------------------|:----|---:|` and `|:---|:---|---:|`
-- on identical content produce different PDFs, and neither measures what is
-- actually in the cells. With uniform dashes you get a flat equal split.
--
-- This is not a pandoc defect — it does exactly what it documents. It is
-- simply a different thing from "make the columns fit the content", which is
-- what you usually want, and it makes the source formatting load-bearing in a
-- way that is easy to change by accident.
--
-- WHAT THIS FILTER DOES INSTEAD
--
-- Two stages, because a single proportional pass is not safe:
--
--   1. FLOOR. Every column gets at least the width of its longest UNBREAKABLE
--      token. Prose survives being squeezed — it rewraps at spaces. An amount
--      like "1.234.567,89" does not: it has no break opportunity, so a column
--      narrower than that token overflows the rule no matter how much slack
--      exists elsewhere in the table.
--
--   2. DISTRIBUTE. Remaining slack goes to columns proportionally to their
--      UNCOVERED demand — the gap between what they would naturally want and
--      the floor they already received. Space goes where it still helps.
--
-- Widths are normalised to sum to 1, so the table fills the type area exactly
-- rather than sitting centred with slack or running past the margin.
--
-- USAGE
--
--   pandoc doc.md --lua-filter table-widths.lua --pdf-engine=xelatex -o doc.pdf
--
-- The character capacity of one line is geometry-dependent. The default (80)
-- was measured for A4, 11pt body text and tables set one step smaller; it is a
-- starting point for that geometry, not a universal constant, and no value is
-- right for every document. Set it for your own with:
--
--   pandoc doc.md -M table-capacity=72 --lua-filter table-widths.lua ...
--
-- A capacity that is too low is the safe direction: it produces more generous
-- minimum widths.

if PANDOC_VERSION == nil or PANDOC_VERSION < {2, 17} then
  error("table-widths.lua requires pandoc >= 2.17 " ..
        "(Lua TableHead.rows / Row.cells / Cell.col_span; 2.16 and older lack them)")
end

-- LaTeX only. Without this guard the filter also rewrites HTML, docx and ODT
-- output, where pandoc renders the widths as `<col style="width: 31%">`. The
-- percentages are truncated rather than rounded, so they sum to 99% and leave
-- a visible gap — a layout bug, not merely a redundant attribute.
if not FORMAT:match("latex") then
  return {}
end

local stringify = pandoc.utils.stringify

local CAPACITY = 80      -- characters per line; override with -M table-capacity
local ATOMIC_SAFETY = 1.25  -- digits and capitals run wider than the average glyph
local PADDING = 2
local MIN_WIDTH = 3

local function len(s)
  return utf8.len(s) or #s
end

-- Longest run with no break opportunity. TeX may break at spaces, at hyphens
-- and dashes, and (via a companion filter) after slashes. Digit groups with
-- thousands separators and decimal commas stay whole.
local function longest_unbreakable(s)
  local longest = 0
  for chunk in s:gmatch("[^%s/]+") do
    for piece in chunk:gmatch("[^%-–—]+") do
      local n = len(piece)
      if n > longest then longest = n end
    end
  end
  return longest
end

local function each_row(tbl)
  local rows = {}
  local function add(list)
    for _, r in ipairs(list or {}) do rows[#rows + 1] = r end
  end
  add(tbl.head.rows)
  for _, body in ipairs(tbl.bodies) do
    add(body.head)
    add(body.body)
  end
  add(tbl.foot.rows)
  return rows
end

local function size_table(tbl)
  local ncols = #tbl.colspecs
  if ncols == 0 then return nil end

  local natural, atomic = {}, {}
  for i = 1, ncols do natural[i], atomic[i] = MIN_WIDTH, MIN_WIDTH end

  for _, row in ipairs(each_row(tbl)) do
    local col = 1
    for _, cell in ipairs(row.cells) do
      local span = cell.col_span or 1
      -- A cell spanning several columns says nothing about any single width.
      if span == 1 and col <= ncols then
        local text = stringify(cell.contents)
        local n, a = len(text), longest_unbreakable(text)
        if n > natural[col] then natural[col] = n end
        if a > atomic[col] then atomic[col] = a end
      end
      col = col + span
    end
  end

  local sum_natural, sum_atomic = 0, 0
  for i = 1, ncols do
    natural[i] = natural[i] + PADDING
    atomic[i] = math.ceil(atomic[i] * ATOMIC_SAFETY) + PADDING
    if atomic[i] > natural[i] then atomic[i] = natural[i] end
    sum_natural = sum_natural + natural[i]
    sum_atomic = sum_atomic + atomic[i]
  end

  local width = {}
  if sum_natural <= CAPACITY then
    -- Everything fits; scale up, nothing wraps.
    width = natural
  elseif sum_atomic >= CAPACITY then
    -- The floors alone already exceed the line. The table cannot fit at this
    -- capacity, so something must give — but distribute by FLOOR, not by
    -- natural width. Falling back to natural here (an earlier version of this
    -- filter did) discards the minimums at exactly the moment they matter
    -- most: a column holding one long unbreakable token has a small natural
    -- width and a large floor, so natural proportions starve it and it is the
    -- column that overflows. Proportional-to-floor keeps relative unbreakable
    -- demand intact and spreads the unavoidable shortfall evenly.
    width = atomic
  else
    local slack = CAPACITY - sum_atomic
    local demand = 0
    for i = 1, ncols do demand = demand + (natural[i] - atomic[i]) end
    for i = 1, ncols do
      local share = demand > 0 and (natural[i] - atomic[i]) / demand or 0
      width[i] = atomic[i] + slack * share
    end
  end

  local total = 0
  for i = 1, ncols do total = total + width[i] end
  if total <= 0 then return nil end
  for i = 1, ncols do
    tbl.colspecs[i][2] = width[i] / total
  end
  return tbl
end

-- Two-element filter list so Meta is read before any Table is visited.
-- Note: there is no PANDOC_DOCUMENT global — the documented ones are FORMAT,
-- PANDOC_VERSION, PANDOC_API_VERSION, PANDOC_STATE and PANDOC_WRITER_OPTIONS
-- — so metadata must be
-- picked up this way rather than read directly.
return {
  { Meta = function(meta)
      local c = meta["table-capacity"]
      if c then
        local n = tonumber(stringify(c))
        if n and n > 0 then CAPACITY = n end
      end
      return meta
    end },
  { Table = size_table },
}

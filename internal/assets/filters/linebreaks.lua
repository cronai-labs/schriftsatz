--- Add break opportunities after slashes in body text.
--
-- TeX breaks at hyphens and, with a language package loaded, inside words at
-- hyphenation points. It never breaks after a slash. So a token like
-- "Bundesanzeiger/Registerauszug" or "read/write/execute" is atomic: if it
-- lands at the end of a line it runs into the margin, and \emergencystretch
-- only stretches the interword space, which does not save every case.
--
-- This filter puts \allowbreak after each slash: a permitted but not forced
-- break, with no inserted hyphen. That matches normal German typesetting
-- practice and costs nothing while the line still fits — TeX only takes the
-- opportunity when it needs it.
--
-- Deliberately \allowbreak and deliberately only in Str elements. Inline
-- `code` is a different AST node and is left alone, so URLs and paths in code
-- spans keep their slashes intact. The usual alternative — making "/" an
-- active character globally — breaks exactly those.
--
-- Order matters: run this AFTER any filter that measures text width, so the
-- measurement sees undivided tokens.
--
-- USAGE
--
--   pandoc doc.md --lua-filter linebreaks.lua --pdf-engine=xelatex -o doc.pdf

if not FORMAT:match("latex") then
  return {}
end

local ALLOWBREAK = pandoc.RawInline("latex", "\\allowbreak{}")

function Str(el)
  local text = el.text
  if not text:find("/", 1, true) then return nil end

  local out, pos = {}, 1
  while true do
    local _, stop = text:find("/", pos, true)
    if not stop then
      if pos <= #text then out[#out + 1] = pandoc.Str(text:sub(pos)) end
      break
    end
    -- The slash stays attached to the preceding piece.
    out[#out + 1] = pandoc.Str(text:sub(pos, stop))
    out[#out + 1] = ALLOWBREAK
    pos = stop + 1
  end
  return out
end

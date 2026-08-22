--- Apply the text-layer font feature to fonts pandoc loads itself.
--
-- Companion to styles/text-layer.tex, which carries the full account of the
-- defect. This file exists because that fragment cannot reach every font.
--
-- WHY A FILTER IS NEEDED AT ALL
--
-- text-layer.tex disables `calt` with \defaultfontfeatures, which sets a
-- default for fonts loaded AFTER it. pandoc emits `header-includes` — where -H
-- content lands — after its own font block, so a font named in front matter is
-- already loaded by the time the fragment arrives:
--
--   line 22:  \setmainfont[]{Inter-Regular.otf}          <- pandoc's fonts
--   line 96:  \defaultfontfeatures{RawFeature={-calt}}   <- too late
--
-- So `mainfont:` in front matter — the documented, obvious way to choose a
-- typeface — was the one ordering the fix did not cover, and the defect the
-- project is named after reproduced in full. The suite did not see it because
-- it sets the font in a second -H file passed after the fragment, which is the
-- one ordering where \defaultfontfeatures does apply.
--
-- WHAT THIS DOES INSTEAD
--
-- Appends the feature to the document's own `*options` list, so it reaches
-- \setmainfont at the point the font is loaded, and whatever the author already
-- set is kept:
--
--   mainfontoptions: [Numbers=Lining]
--   -> \setmainfont[Numbers=Lining,RawFeature={-calt}]{Inter-Regular.otf}
--
-- A RawInline rather than a plain string, deliberately: metadata values are
-- parsed as Markdown and the LaTeX writer escapes the braces, which yields
-- RawFeature=\{-calt\} — rejected by fontspec. -V would render verbatim but
-- REPLACES the author's list rather than adding to it.
--
-- USAGE
--
--   pandoc doc.md --lua-filter text-layer.lua -H text-layer.tex \
--     --pdf-engine=xelatex -o doc.pdf
--
-- Both parts are wanted: this covers the fonts pandoc loads, the fragment
-- covers fonts loaded by a header file of your own.

if not FORMAT:match("latex") then
  return {}
end

local FEATURE = "RawFeature={-calt}"

-- The keys pandoc's LaTeX template turns into \setmainfont, \setsansfont and
-- \setmonofont. Each has a matching <key>options list.
local FONT_KEYS = { "mainfont", "sansfont", "monofont" }

local stringify = pandoc.utils.stringify

--- Has the author already said something about calt?
--
-- text-layer.tex documents RawFeature={+calt} as the way to put case-sensitive
-- punctuation back on a face whose text will never be extracted. fontspec takes
-- the LAST setting, so appending here would silently defeat that. An explicit
-- choice is left alone.
local function mentions_calt(opts)
  return opts ~= nil and stringify(opts):find("calt", 1, true) ~= nil
end

--- Font options are LaTeX, not prose.
--
-- Metadata values are parsed as Markdown, so the LaTeX writer escapes their
-- braces: `Numbers={Proportional,Lining}` in front matter reaches the template
-- as `Numbers=\{Proportional,Lining\}` and the build dies with a fontspec
-- error. Every option carrying braces was unusable that way — which is most of
-- the interesting ones. The same value passed with -V renders verbatim, so this
-- only makes front matter behave the way the flag already does.
local function raw_option(v)
  return pandoc.MetaInlines({ pandoc.RawInline("latex", stringify(v)) })
end

--- A single option may be written as a bare string rather than a list.
local function options_list(opts)
  if opts == nil then
    return pandoc.MetaList({})
  elseif opts.t == "MetaList" then
    return opts
  end
  return pandoc.MetaList({ opts })
end

function Meta(meta)
  for _, key in ipairs(FONT_KEYS) do
    -- Only when a font is actually set. With none, pandoc loads nothing and an
    -- options list would describe a \setmainfont that never happens.
    if meta[key] then
      local opts_key = key .. "options"
      local given = meta[opts_key]
      local out = pandoc.MetaList({})
      for _, v in ipairs(options_list(given)) do
        out[#out + 1] = raw_option(v)
      end
      if not mentions_calt(given) then
        out[#out + 1] = pandoc.MetaInlines({ pandoc.RawInline("latex", FEATURE) })
      end
      meta[opts_key] = out
    end
  end
  return meta
end

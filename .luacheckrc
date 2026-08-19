-- Lua linting for pandoc filters.
--
-- Two things need declaring, or every filter looks like it is abusing globals:
--
--   read_globals — pandoc injects these into a filter's environment.
--   globals      — a filter REGISTERS a handler by defining a global with the
--                  AST element's name. `function Str(el)` is the documented
--                  API, not an accidental global, so luacheck has to be told.
std = "lua54"

read_globals = {
  "pandoc",
  "PANDOC_VERSION",
  "PANDOC_STATE",
  "PANDOC_WRITER_OPTIONS",
  "FORMAT",
}

globals = {
  "Str", "Table", "Meta", "Inlines", "Blocks", "Pandoc", "Block", "Inline",
}

-- Filters are single files run by pandoc; there is no module system to satisfy.
allow_defined_top = true
max_line_length = 100

-- 131 is "unused global". A handler is defined for pandoc to CALL; nothing in
-- this codebase reads it, so every one of them is unused by that definition.
-- Scoped to the handler names rather than switching 131 off wholesale, so a
-- genuinely unused global elsewhere is still reported.
ignore = {
  "131/Str", "131/Table", "131/Meta", "131/Inlines", "131/Blocks",
  "131/Pandoc", "131/Block", "131/Inline",
}

# Why not X

This repository occupies a narrow slot in a crowded space. Conceding the rest of it
explicitly is more useful than defending against it.

## Pandoc + LaTeX styling

**[Eisvogel](https://github.com/Wandmalfarbe/pandoc-latex-template)** (~7k stars) is the
default answer for "make my Markdown into a good-looking PDF", and it should be. It has
a titlepage, code highlighting, header/footer variables and years of polish. It does not
compute table column widths, does not address the text-layer defect, and has no
signature or imprint components — but if those are not your problems, use Eisvogel.

**[Quarto](https://quarto.org)** is the industrial version: executable code,
cross-references, books, websites, many output formats. Anything the CLI here does, a
`_quarto.yml` does more generally. Quarto inherits pandoc's table-width behaviour.

**[pandocomatic](https://github.com/htdebeer/pandocomatic)** and
**[panrun](https://github.com/mb21/panrun)** solve "stop hand-writing the pandoc
invocation" with more generality and template inheritance than `bin/schriftsatz` has.

## Table widths

**[pantable](https://github.com/ickc/pantable)** is the closest prior art and the only
published filter that measures content: its `auto_width` takes the maximum line length
per cell, adds three, and normalises. Two differences. It applies only to its own
CSV-in-a-code-block syntax, so you must rewrite your tables; and it is single-stage with
no minimum-width floor, which is the stage that stops a column holding `1.234.567,89`
from being squeezed below the width of that token.

**[pandocker-lua-filters](https://github.com/pandocker/pandocker-lua-filters)** applies
widths you supply by hand.

Pandoc's own behaviour — relative widths from the separator-row dash count, and only
when a source line exceeds `--columns` — is under discussion upstream in
[#10433](https://github.com/jgm/pandoc/issues/10433) and
[#10111](https://github.com/jgm/pandoc/issues/10111).

If you just want the table to fill the line, try `--columns=200` first. It is one flag
and it stops pandoc emitting widths at all.

## Diagrams

**[pandoc-ext/diagram](https://github.com/pandoc-ext/diagram)** embeds Mermaid,
GraphViz, PlantUML, TikZ, Asymptote, D2 and CeTZ. Diagram embedding is out of scope here
and will stay out of scope: there is nothing this project could add to that.

## German business documents

**KOMA-Script `scrlttr2`** owns letter geometry, and several DIN 5008 Briefvorlagen
build on it. `styles/formal.tex` deliberately does not reimplement a letter class.

**[OpenBilanz](https://github.com/chloepriceless/OpenBilanz)** generates a German GmbH's Bilanz,
GuV and Gesellschafterbeschlüsse with the figures filled in, plus E-Bilanz XBRL — a
layer this project does not touch and will not.

**Resolvio** publishes hundreds of lawyer-maintained Beschluss-Muster for free. This
repository ships no document templates, and that is why.

## Non-LaTeX routes

**[md-to-pdf](https://github.com/simonhaenisch/md-to-pdf)** (~124k weekly downloads) and
the CSS Paged Media route (**WeasyPrint**, **Paged.js**, **Prince**) are where most
users actually are, and they are easier to install.

The honest case for XeLaTeX here is narrow: justified text with real hyphenation for
German compounds, `longtable` across page breaks, and direct control over OpenType
features — which is what the `calt` fix requires. If you do not need those, a browser
engine is less work.

**[Typst](https://typst.app)** is the strongest argument against this whole approach.
It compiles in milliseconds, has 1450+ packages including DIN 5008 letters, and is
explicitly courting automated business-document generation. If this project were started
today rather than extracted from something already running, Typst would deserve a
serious look first. The reason it is LaTeX is that the pipeline it came from is LaTeX
and works.

## Tagged and archival output

**LuaLaTeX** is the engine LaTeX's own tagging project targets, and pandoc's
`document-metadata.latex` partial says as much. If you need explicit interword marking in the
structure tree, use it — XeTeX cannot do that part.

What is not widely known, and is why this is here: the rest of tagging **does** work on XeLaTeX.
Measured against veraPDF, this pipeline produces PDF/A-3b and PDF/UA-2 that validate, with a
real structure tree, while keeping the OpenType feature control the `calt` fix depends on. That
combination — `-calt` on the font *and* a tagged, conforming PDF — is the one this project
needs and did not find elsewhere.

**[Ghostscript](https://www.ghostscript.com)** converts an existing PDF to PDF/A. It cannot
invent a structure tree that was never in the source, so it solves a different problem.

## What survives

The text-layer finding is engine-specific (XeTeX) and font-general — it affects anyone
using a font with case-sensitive punctuation, including through the CTAN `inter` package
in a stock TeX Live. The width filter is the only published pandoc filter that floors
columns at their longest unbreakable token and applies to ordinary pipe tables. And tagged,
validating PDF/A on XeLaTeX is documented here because the tooling's own comments say it needs
a different engine.

That is the whole claim.

---
type: decision
title: Tagged and archival output is opt-in, and only standards that validate are offered
description: schriftsatz can emit tagged, XMP-carrying PDF/A-3b and PDF/UA-2 on XeLaTeX, but not by default — the pandoc floor is 3.9 and the output format changes. Revisit when Debian stable ships pandoc 3.9 or newer.
tags: [pdf, tagging, pdf-a, pandoc, accessibility]
sources:
  - { name: "veraPDF 1.28 (verapdf/cli) run against this pipeline's output", credibility: verified-firsthand }
  - { name: "jgm/pandoc#11407, templates/document-metadata.latex, first released in 3.9", credibility: primary }
verified: true
verified_on: 2026-08-23
stale_after: 2027-02-23
status: active
---

# Tagged and archival output is opt-in

A faithful text layer is half of "machine readable". The other half is structure: without a
structure tree a reader has glyphs and positions and nothing else — no reading order, no table
structure, no way to tell a heading from a caption. This project claimed the whole of it while
delivering the first half.

`--tagged` and `--pdf-standard` close that gap. Neither is on by default.

## Why XeLaTeX can do this at all

pandoc's `templates/document-metadata.latex` emits `\DocumentMetadata` from a `pdfstandard`
metadata key. Its own comment says the feature "requires LuaLaTeX". Measured on TeX Live 2026
that is not true of the tagging path: XeLaTeX produces a real structure tree through this
project's whole pipeline — fontspec, the `-calt` fix, both Lua filters, `longtable`, `fancyhdr`
and a `minipage`:

```text
/Document -> /Sect -> /Table -> /TR -> /TH -> ...
```

`schriftsatz verify` still passes on the tagged output, so the two guarantees compose.

One limitation is real and unfixable here: `tagpdf` warns that `engine/output mode xetex doesn't
support the interword space`, so word boundaries are not explicitly marked in the structure tree.
Measured, both poppler and pypdf recover word boundaries correctly from the output anyway,
because they reconstruct spacing from glyph positions — but a consumer walking the structure tree
rather than extracting text has less to go on than the same document built with LuaLaTeX.

## Why it is opt-in

`templates/document-metadata.latex` first ships in **pandoc 3.9** (released 2026-02-04). The
project's floor is 2.17 and Debian 13 stable ships 3.1.11, so on most Linux installations the
key is ignored in silence.

Turning tagging on by default would therefore make every user's output depend on which pandoc
they happen to have — and would change the file format itself, since tagging implies PDF 2.0.
Environment-dependent behaviour is the failure mode this project rejects everywhere else, so
asking for tagging on a pandoc that cannot deliver it is an **error**, not a downgrade.

**Re-check trigger:** when Debian stable ships pandoc 3.9 or newer, or when the project's floor
is raised past it, reconsider making `--tagged` the default.

## Why only PDF/A-3b and PDF/UA-2 are offered

A conformance declaration is what a downstream system trusts *instead of* checking. Shipping one
the file does not honour is worse than shipping none, so the list contains only what has been
validated end to end with veraPDF:

| standard | header | veraPDF | offered |
|:---|:---|:---|:---|
| PDF/A-3b | 1.7 | PASS | yes |
| PDF/UA-2 | 2.0 | PASS | yes |
| PDF/A-2b | 1.7 | FAIL 6.8-5 | no |
| PDF/A-4 | 2.0 | FAIL 6.1.3-4, 6.1.3-5, 6.9-3 | no |

**PDF/A-2b cannot pass as things stand.** LaTeX's tagging support attaches
`latex-list-css.html` and `latex-align-css.html` as associated files (`/AF`,
`/AFRelationship /Supplement`). PDF/A-3 permits arbitrary associated files; PDF/A-2 does not.

Two findings that cost a validation round each, recorded so they are not rediscovered:

- **The header version has to match the standard.** `\DocumentMetadata` defaults to PDF 2.0 and
  PDF/A-1/2/3 require a header of 1.7 or lower. Rule 6.1.2-1 was the *only* failure for A-3b
  before the version was pinned.
- **PDF/UA-2 requires `dc:title`.** Rule 8.11.1-1, and the only failure for a document whose
  front matter carries an empty title — which `examples/formal-document.md` does deliberately.
  The CLI now refuses at build time and names the cause.

## What "validated" does and does not mean

veraPDF checks the machine-checkable rules of a standard. PDF/UA in particular also carries
requirements no validator can decide — whether alternative text is *meaningful*, whether the
heading hierarchy reflects the document's actual structure. Passing veraPDF is necessary, not
sufficient, and the documentation says so rather than implying a conformance claim the project
cannot make.

## Accepted debt

- PDF/A-2b and PDF/A-4 are not offered. Tracked with the veraPDF rule identifiers above; there
  is no issue to fix them because neither is wanted yet — the entry exists so that a future
  request starts from evidence rather than from scratch.

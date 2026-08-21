---
name: schriftsatz
description: Render Markdown to a print-ready PDF whose text layer survives extraction, and diagnose PDFs whose visible text and extractable text disagree. Use when producing a document that will be printed, signed, archived or parsed, when a PDF's copied text is missing minus signs or parentheses, or when table columns overflow the page.
license: MIT
compatibility: Requires the schriftsatz binary plus pandoc >= 2.17, xelatex and poppler on the host.
---

# schriftsatz

A PDF can look perfectly correct and have a text layer that is wrong. That is the problem this
tool exists for, and the reason a skill is useful here: the failure is invisible, so nobody
looks for it until a number has already been copied wrongly.

## When to reach for this

- Producing a document that will be **printed, signed, archived, or read by a machine** later.
- Someone reports that copying from a PDF **drops minus signs or parentheses**, or yields
  characters that render as boxes.
- A table **runs off the page** or its columns are absurdly proportioned.

## Build

```bash
schriftsatz document.md                    # → document.pdf, next to the input
schriftsatz document.md -o out/report.pdf
schriftsatz document.md --lang de-DE       # affects hyphenation
```

Two styles are applied by default: text-layer correctness and line breaking. Page furniture —
footer, signature line, letterhead — is opt-in:

```bash
schriftsatz doc.md --style "$(schriftsatz --print-asset styles/formal.tex > /tmp/f.tex; echo /tmp/f.tex)"
```

Inspect what the binary carries with `schriftsatz --list-assets`.

## Diagnose a suspect PDF

```bash
schriftsatz verify report.pdf
```

Exit 0 means the text layer is faithful. **Exit 1 is a finding, not a tool failure.** Read it:

**`Private Use Area codepoints (U+E09E …)`** — the font substituted glyphs that carry no
meaning outside it. The document renders correctly and extracts wrongly. Cause: a `calt`
(contextual alternates) feature swapping punctuation for `.case` variants next to capitals and
digits. Fix by disabling that feature on the font — the shipped `styles/text-layer.tex` does
this for every font loaded after it, so the usual cause is a font set *without* that fragment.

**`extractors disagree (poppler vs pypdf)`** — worse than it sounds. poppler discards Private
Use Area codepoints, so a character silently vanishes; other readers keep them and yield
mojibake. A text layer whose content depends on the reader is not a text layer. Same cause,
same fix.

Do not "fix" either by switching fonts at random. Any font with case-sensitive punctuation
behaves this way; the fix is the feature setting, not the typeface.

## The one piece of LaTeX a caller has to write

`formal.tex` gives an **empty** imprint by default — it deliberately knows nothing about the
user. Filling it in means writing raw LaTeX inside the Markdown, which is where callers get
stuck, because an unescaped `%` silently comments out the rest of the line and `&` and `_`
fail obscurely:

```latex
\renewcommand{\docimprint}{%
  \footnotesize\color{doc-secondary}%
  \begin{tabular}[b]{@{}l@{}}
  ABC Company Ltd · 1 Example Street · EX4 2MP Exampleton\\
  Directors: A. Placeholder · Reg. 00000000
  \end{tabular}}
```

Escape `% & _ # $` as `\% \& \_ \# \$` in any value placed there. Whether a document *must*
carry particular particulars is a question for the caller's jurisdiction and adviser; this is
a typesetting tool and takes no position on it.

## What not to promise

The binary embeds its filters and styles, but it is **not self-contained**: pandoc, xelatex and
poppler must be present. Say that plainly rather than implying a single binary means no
dependencies.

PDF output is **not byte-reproducible** — two builds of the same source differ in font subset
streams. The *text layer* is stable, and that is what `verify` asserts.

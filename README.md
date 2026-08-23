# schriftsatz

**Markdown to print-ready PDF — with a text layer you can trust and a structure a machine can read.**

[![Release](https://img.shields.io/github/v/release/cronai-labs/schriftsatz?sort=semver)](https://github.com/cronai-labs/schriftsatz/releases)
[![CI](https://github.com/cronai-labs/schriftsatz/actions/workflows/ci.yml/badge.svg)](https://github.com/cronai-labs/schriftsatz/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![pandoc](https://img.shields.io/badge/pandoc-%E2%89%A5%202.17-brightgreen.svg)](https://pandoc.org)
[![engine](https://img.shields.io/badge/engine-XeLaTeX-orange.svg)](https://tug.org/xetex/)

A PDF can look perfectly correct and be wrong underneath. Copy a figure out of it and the minus
sign is gone. Hand it to a parser and there is no reading order, no table structure, nothing but
glyphs and coordinates. Neither failure is visible on the page, so nobody looks until a number
has already been read wrongly.

`schriftsatz` renders Markdown through pandoc and XeLaTeX so that both layers are right, and
gives you a `verify` command to prove it on any PDF — including ones it did not build.

> *Ein Schriftsatz ist beides: ein Schriftstück bei Gericht, und gesetzter Text.*

## 📄 A document, and what comes out

```markdown
---
title: Kontoauszug
lang: de-DE
imprint:
  - Müller & Co. GmbH · 1 Example Street · 12345 Example City
  - 'Directors: A. Placeholder · HRB 00000000 · 19 % VAT'
---

# Kontoauszug

| Position | Grundlage | Betrag |
|:---|:---|---:|
| Beratung, laufend | Kapitalertragsteuerbescheinigung | −1.204,00 |
| Lizenz, jährlich | Umsatzsteuervoranmeldung | 123,45 |
```

```bash
schriftsatz kontoauszug.md --pdf-standard a-3b
```

Out comes an A4 PDF with German hyphenation, the imprint in the footer of **every** page, and
table columns sized to what is in them rather than to how many dashes you typed. `−1.204,00`
copies out as `−1.204,00`, minus sign intact. The file is tagged and declares PDF/A-3b, so an
archive or a parser gets structure and not just pixels.

Nothing in that front matter is LaTeX. `&`, `%` and `_` are escaped for you — hand-writing that
`tabular` was the single thing callers got wrong most often.

## 🚀 Install

```bash
brew install cronai-labs/tap/schriftsatz
```

Use the fully-qualified name: Homebrew 6.0 added tap trust, and an unqualified
`brew install schriftsatz` after `brew tap` is refused.

As an agent skill:

```bash
npx skills add cronai-labs/schriftsatz
```

**Required:** `pandoc` ≥ 2.17, `xelatex`, and `poppler-utils` (`pdftotext`, `pdfinfo`) — all
three come with the Homebrew cask. `--tagged` and `--pdf-standard` additionally need pandoc
≥ 3.9 and a LaTeX kernel from 2024-11-01 or newer, and say so rather than quietly producing an
untagged file.

## ✨ What it does

- **Keeps the text layer faithful.** A font's `calt` feature makes XeLaTeX emit PDFs where minus
  signs and parentheses are on the page but absent from the extractable text — `−123,45` copies
  out as `123,45`. Both obvious fixes fail. The write-up, with a reproducer that needs nothing
  but a stock TeX Live → [docs/inter-calt-tounicode.md](docs/inter-calt-tounicode.md)
- **Sizes table columns by their content.** Pandoc derives pipe-table widths from how many
  dashes you type in the separator row. This measures the cells instead, and floors every column
  at its longest unbreakable token so an amount never hangs off the rule →
  [docs/table-widths.md](docs/table-widths.md)
- **Emits tagged and archival PDFs.** Structure tree, XMP metadata, and PDF/A-3b or PDF/UA-2 —
  each validated against veraPDF → [docs/decisions/tagged-pdf.md](docs/decisions/tagged-pdf.md)
- **Takes your house style as data.** Imprint, brand colours and letterhead from front matter or
  a shared `--metadata-file`, escaped by pandoc's own writer.
- **Breaks long compounds.** Break opportunities after slashes, for languages that build words
  like `Bundesanzeiger/Registerauszug`.

## 🎛 What the document controls

Defaults apply only where the document is silent, so anything set in front matter wins:

```yaml
---
lang: de-DE          # hyphenation, and the PDF catalogue's /Lang
papersize: a4        # the default
fontsize: 11pt
documentclass: article
indent: false        # block paragraphs; true for first-line indentation
mainfont: Inter      # any font fontspec can find — the calt fix still applies
geometry: [top=30mm, left=25mm]
imprint: [Line one, Line two]
brand: {ink: '1A1A1A', secondary: '666666', hairline: 'D8D8D8'}
letterhead: logo.pdf
---
```

Put the same block in a file and share one identity across every document you produce:

```bash
schriftsatz doc.md --metadata-file house-style.yaml
```

Precedence throughout: the tool's defaults lose to that file, which loses to the document.
`--lang` is the one flag that overrides the document, because someone rebuilding another
person's file needs a way to.

## 🔍 Verify any PDF

```console
$ schriftsatz verify statement.pdf
ok    two extractors agree
ok    tagged: a structure tree is present, declaring PDF/A-3b
ok    statement.pdf: text layer is faithful
```

Exit 1 is a **finding about the PDF**, not a tool failure. It names what it found:

```console
$ schriftsatz verify from-elsewhere.pdf
FAIL  from-elsewhere.pdf: text layer contains Private Use Area codepoints (U+EE6B)
      the font mapped glyphs to codepoints that carry no meaning
      outside it — see docs/inter-calt-tounicode.md
ok    two extractors agree
note  not tagged: no structure tree, so reading order and table
      structure are not available to a machine. Rebuild with
      --tagged, or --pdf-standard for an archival conformance level.
```

`U+EE6B` is a Private Use Area codepoint: it means whatever the font that produced it says it
means, and nothing at all outside it. That scan is what catches the defect. A second extractor
runs as a cross-check on top, because a text layer whose content depends on which reader opens
it is not a text layer.

## 🧰 Use the pieces without the CLI

The filters are single files with no dependencies, and the style fragments can be adopted one at
a time. `--list-assets` shows what the binary carries; `--print-asset <name>` reads one out.

```bash
pandoc doc.md --pdf-engine=xelatex \
  --lua-filter filters/text-layer.lua \
  --lua-filter filters/table-widths.lua \
  --lua-filter filters/linebreaks.lua \
  -H styles/text-layer.tex \
  -o doc.pdf
```

`--style` takes a path of your own **or** an embedded name, and adds to the defaults rather than
replacing them:

```bash
schriftsatz doc.md --style styles/formal.tex   # footer, signature line, letterhead
```

## 🎯 Why XeLaTeX, and why not something else

A small tool in a crowded space; better to be direct about where it does not compete. The longer
version, including the case *against* this whole approach, is in
[docs/why-not.md](docs/why-not.md).

| If you want | Use |
|:---|:---|
| A polished general-purpose Markdown → PDF template | [Eisvogel](https://github.com/Wandmalfarbe/pandoc-latex-template) |
| Technical and scientific publishing, many formats | [Quarto](https://quarto.org) |
| Diagrams embedded from Markdown | [pandoc-ext/diagram](https://github.com/pandoc-ext/diagram) |
| DIN 5008 business letters | KOMA-Script `scrlttr2` |
| Fast modern typesetting, no LaTeX | [Typst](https://typst.app) |
| Explicit interword marking in the structure tree | LuaLaTeX — XeTeX cannot do that part |

What is left over, and what this repository is for: the text layer has to survive extraction,
table columns have to be sized by what is in them, and the result has to be readable by a
machine as well as by a person.

## 🧪 Development

```bash
git clone https://github.com/cronai-labs/schriftsatz && cd schriftsatz
make setup     # verify the toolchain; installs nothing
make check     # lint + tests + leak scan — what CI runs
make build     # compile, and build every example with the command it documents
```

`make` with no target lists everything. The suite asserts the **failing** cases as well as the
passing ones, because a test that only checks that the fix works cannot tell you whether it is
still testing anything:

```text
ok   unfixed drops the minus (control)              absent −123,45
ok   -case does NOT fix it (control)                absent −123,45
ok   -calt fixes it                                 present −123,45
ok   actualtext FAILS under pypdf (the whole point) absent −123,45
```

Contributing, the commit and release conventions, and the leak gate:
[CONTRIBUTING.md](CONTRIBUTING.md).

## 📐 Scope

One claim: **a PDF that is correct to a machine, not only to a reader.** Typesetting a document
must be able to control for itself — paper, language, fonts, margins, page furniture, house
style — is in scope too, because a tool nobody can produce their own documents with never gets
used on the documents where the guarantee matters.

Out of scope: diagram embedding, document templates, HTML or DOCX output, and anything that
would make this a general-purpose document system. The table above points somewhere better.

## ⚠️ Not legal advice

`styles/formal.tex` provides a footer component and `imprint:` fills it in. Whether your
documents must carry particular information, and which, is a question for your jurisdiction and
your adviser — this repository does not know and does not claim to. It is a typesetting tool.

## 📄 License

MIT © [CronAI UG](https://cronai.de). "CronAI" is a trademark of CronAI UG; this licence grants
no trademark rights. No fonts are bundled — see [LICENSE](LICENSE).

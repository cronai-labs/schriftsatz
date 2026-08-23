# schriftsatz

**Markdown to print-ready PDF, with a text layer you can trust.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![pandoc](https://img.shields.io/badge/pandoc-%E2%89%A5%202.17-brightgreen.svg)](https://pandoc.org)
[![engine](https://img.shields.io/badge/engine-XeLaTeX-orange.svg)](https://tug.org/xetex/)

Three pandoc Lua filters, three preamble fragments and a small CLI, extracted from a
working pipeline that renders a company's statutory documents. The parts worth
publishing are the ones that took the longest to get right: how table columns get their
widths, and why a PDF that looks correct can have a text layer that is silently wrong.

> *Ein Schriftsatz ist beides: ein Schriftstück bei Gericht, und gesetzter Text.*

## ✨ What is here

- **A text-layer defect, documented and reproduced.** Inter's `calt` feature makes
  XeLaTeX emit PDFs where minus signs and parentheses are visible on the page but
  absent from the extractable text. `−123,45` copies out as `123,45`. Both obvious
  fixes fail. → [docs/inter-calt-tounicode.md](docs/inter-calt-tounicode.md)
  The fix ships in two halves, because one cannot cover both orderings: a preamble
  fragment for fonts a header file loads, and a filter for a font named in front
  matter, which pandoc loads before any header is read.
- **Content-measured table column widths.** Pandoc derives pipe-table widths from how
  many dashes you type in the separator row. This filter measures the cells instead,
  and floors every column at its longest unbreakable token so an amount never hangs off
  the rule. → [docs/table-widths.md](docs/table-widths.md)
- **Break opportunities after slashes**, for languages that build long compounds.
- **Preamble fragments** you can adopt one at a time, and an imprint component that is
  empty by default.

## 🚀 Quick start

```bash
brew install cronai-labs/tap/schriftsatz
schriftsatz document.md              # → document.pdf
schriftsatz verify document.pdf      # is the text layer faithful?
```

Use the fully-qualified name: Homebrew 6.0 added tap trust, and an unqualified
`brew install schriftsatz` after `brew tap` is refused.

The binary carries its own Lua filters and LaTeX fragments — `--list-assets` to see them,
`--print-asset <name>` to read one out, and `--style <name>` to use one:

```bash
schriftsatz document.md --style styles/formal.tex   # adds the footer and signature line
```

`--style` also takes a path to a header of your own, and adds to the default styles rather than
replacing them. `--no-default-style` drops the defaults — including the text-layer fix.

From a clone:

```bash
git clone https://github.com/cronai-labs/schriftsatz && cd schriftsatz
make setup                  # verify the toolchain; installs nothing
make check                  # lint + tests + leak scan (this is what CI runs)
make build                  # compile the binary and build every example
```

As an agent skill, in any of the 76+ agents the installer supports:

```bash
npx skills add cronai-labs/schriftsatz
```

`make` with no target lists everything.

Defaults are supplied only where the document is silent, so `lang`, `papersize`, `fontsize`,
`documentclass`, `indent`, `mainfont` and `geometry` in the front matter are yours to set.
Paper is A4 and paragraphs are not first-line indented unless you say otherwise.

**Required:** `pandoc` ≥ 2.17, `xelatex`, and `poppler-utils` (`pdftotext`, `pdfinfo`). The
suite refuses to run without the extractors rather than pass vacuously on empty output.
**Optional, skipped with a notice:** `pypdf` for the second-extractor assertions, `qpdf` for
the structural check, `shellcheck` for `make lint`.

Use the filters without the CLI if you prefer — they are single files with no
dependencies:

```bash
pandoc doc.md --pdf-engine=xelatex \
  --lua-filter filters/text-layer.lua \
  --lua-filter filters/table-widths.lua \
  --lua-filter filters/linebreaks.lua \
  -H styles/text-layer.tex \
  -o doc.pdf
```

## 🎯 Why XeLaTeX, and why not something else

This is a small tool in a crowded space. It is worth being direct about where it does
not compete — see [docs/why-not.md](docs/why-not.md) for the longer version.

| If you want | Use |
|:---|:---|
| A polished general-purpose Markdown → PDF template | [Eisvogel](https://github.com/Wandmalfarbe/pandoc-latex-template) |
| Technical and scientific publishing, many formats | [Quarto](https://quarto.org) |
| Diagrams embedded from Markdown | [pandoc-ext/diagram](https://github.com/pandoc-ext/diagram) |
| DIN 5008 business letters | KOMA-Script `scrlttr2` |
| Fast modern typesetting, no LaTeX | [Typst](https://typst.app) |
| CSV tables with computed widths | [pantable](https://github.com/ickc/pantable) |

What is left over, and what this repository is for: the text layer has to survive
extraction, and table columns have to be sized by what is in them.

## 🧪 Testing

The suite asserts the failing cases as well as the passing ones. A test that only checks
that the fix works cannot tell you whether it is still testing anything:

```text
ok   unfixed drops the minus (control)              absent −123,45
ok   -case does NOT fix it (control)                absent −123,45
ok   -calt fixes it                                 present −123,45
ok   actualtext FAILS under pypdf (the whole point) absent −123,45
```

`tests/no-leaks.sh` is a hard gate against anything traceable to the private setup this
was extracted from — by shape, not by a denylist, because a denylist publishes the strings it
protects. It runs in CI, and as a pre-commit hook once you opt in with
`git config core.hooksPath .githooks`.

Everything a document build generates goes to `build/`, which is gitignored and which
`make clean` deletes in full. CI asserts the working tree is clean after a build.

## 📐 Scope

Deliberately narrow, and intended to stay that way. Out of scope: diagram embedding, a
style-pack DSL, document templates, HTML or DOCX output, and anything that would make
this a general-purpose document system. If you need those, the table above points
somewhere better.

## ⚠️ Not legal advice

`styles/formal.tex` provides a footer component. Whether your documents must carry
particular information, and which, is a question for your jurisdiction and your adviser
— this repository does not know and does not claim to. It is a typesetting tool.

## 📄 License

MIT © [CronAI UG](https://cronai.de). "CronAI" is a trademark of CronAI UG; this licence
grants no trademark rights. No fonts are bundled — see [LICENSE](LICENSE).

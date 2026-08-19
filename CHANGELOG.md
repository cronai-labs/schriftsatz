# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-08-19

First extraction from a private, working pipeline.

### Added

- **`filters/table-widths.lua`** — allocates LaTeX table column widths from measured cell
  content: floor every column at its longest unbreakable token, then distribute the remaining
  slack in proportion to uncovered demand. `FORMAT` guard so it is a no-op outside LaTeX, a
  runtime guard requiring pandoc ≥ 2.17, and capacity configurable via `-M table-capacity=N`.
- **`filters/linebreaks.lua`** — `\allowbreak` after slashes in body text, leaving code spans
  alone.
- **`styles/text-layer.tex`**, **`styles/linebreaking.tex`**, **`styles/formal.tex`** —
  preamble fragments usable one at a time. The imprint in `formal.tex` is empty by default and
  opt-in, mirrored into the `plain` page style so page one cannot silently lose it, and the
  signature block is wrapped in a `minipage` so a page break cannot separate it from its date.
- **`bin/schriftsatz`** — CLI with `-o`, `--style`, `--lang`, `--capacity`, `--keep-tex`,
  dependency preflight and distinct exit codes. Writes where told, never into its own tree.
- **`docs/inter-calt-tounicode.md`** — a text-layer defect where Inter's `calt` feature yields
  PDFs whose minus signs and parentheses are visible but wrong in the extractable text, with a
  reproducer needing nothing but a stock TeX Live. Establishes that the `.case` variants *are*
  cmap-encoded — into the Private Use Area — so poppler discards them while pypdf returns
  mojibake, and that neither `RawFeature={-case}` nor `\XeTeXgenerateactualtext=1` is a
  sufficient fix.
- **`docs/table-widths.md`**, **`docs/why-not.md`** — what the filter does and does not claim,
  and where this project concedes to Eisvogel, Quarto, pandoc-ext/diagram, pantable, scrlttr2
  and Typst.
- **`Makefile`** — `setup build test lint fmt check run release clean`. CI calls these targets.
- **`tests/`** — assertions with negative controls, a structural PDF check, and `no-leaks.sh`,
  a publication gate that checks by shape rather than by a denylist.

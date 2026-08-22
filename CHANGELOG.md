# Changelog

All notable changes to this project are documented here.

Generated from the commit history by [git-cliff](https://git-cliff.org) — do not
edit by hand, the next release overwrites it. Each entry's prose is the
description of the pull request that introduced the change.

## [0.1.0] - 2026-08-22


### Added

- **Markdown to print-ready PDF via pandoc and XeLaTeX**

Two pandoc Lua filters, three preamble fragments, a CLI, and the finding that
motivated publishing any of it.

THE TEXT LAYER

Inter's calt feature substitutes .case variants of minus and parentheses beside
capitals and digits. Those variants are cmap-encoded into the Private Use Area,
so XeTeX maps them faithfully to a codepoint that means nothing outside the
font. Extractors then disagree: poppler discards PUA and the character silently
vanishes, pypdf keeps it and returns mojibake. The page renders correctly either
way and nothing reports a problem, so a profit-and-loss statement can lose its
minus signs in copy-paste without anyone noticing.

RawFeature={-calt} is the only fix correct under both extractors. -case is the
wrong feature entirely, and \XeTeXgenerateactualtext=1 only adds an optional
/ActualText hint over the unchanged encoding, so it satisfies poppler while
leaving every other consumer with the same mojibake.

TABLE WIDTHS

pandoc derives pipe-table widths from the dash count in the separator row, so
the source formatting is load-bearing and the content is not consulted. The
filter allocates from measured content instead, flooring each column at its
longest unbreakable token so an amount never hangs off the rule.

Requires pandoc 2.17, not the 2.10 the Table AST arrived in: the Lua bindings
for Row.cells and Cell.col_span only landed in 2.17, and 2.16 fails outright.
CI tests the versions people actually run — 2.17.1.1 (Debian 12), 3.1.11
(Debian 13) and current — rather than an arbitrary point in history.

DISCIPLINE

Every claim has an assertion and every fix has a negative control, including the
cells that show a fix failing. No fonts are bundled; pypdf arrives through uv,
so nothing is installed on the machine. The publication gate checks by shape
rather than by a denylist, because a denylist publishes in plaintext the strings
it exists to protect.


- **Rewrite in Go with embedded assets, and ship it (#5)**

#### Why

The shell CLI worked only from a clone: it found its filters and styles
via
`$(dirname "$0")/..`, which breaks the moment a package manager installs
the executable
elsewhere. Embedding them removes the problem instead of papering over
it with a `libexec`
wrapper — and it is what lets goreleaser generate a Homebrew cask.

Three silent shell failures in this repo's short life pushed the same
way: an empty array
under `set -u` on bash 3.2, a `grep -qP` check that errored on BSD grep
and reported **clean**
while testing nothing, and a bracket expression written as literal bytes
that passed by luck.

#### Behaviour-preserving, and proven

Golden comparison rather than inspection:

| check | result |
|---|---|
| PDF text layer, all 3 examples | identical |
| exit codes: bad option / no input / --help / --version / missing file
| identical |
| `verify` on a faithful and a defective PDF | identical after one fix |

**One genuine difference, found and fixed.** `verify` returned 4 (build
failure) where the
shell returned 1. A finding about someone else's PDF is not this tool
failing — 1 is correct,
and the exit code is now documented.

#### Also in here

- `verify` names the culprits natively: `Private Use Area codepoints
(U+EE4E U+EE6B)`
- goreleaser → four platform builds, checksums, Homebrew cask pushed to
`cronai-labs/homebrew-tap` (created, public). Dry-run verified end to
end.
- Agent skill at `skills/schriftsatz/`, six spec fields only — claude.ai
hard-errors on extras
- A Go test that fails if the embedded assets drift from the canonical
ones at the repo root

#### Decisions worth review

- **Cask, not formula.** goreleaser deprecated `brews` in v2.10 and
hard-deprecated it in
v2.16; formulae installing pre-built binaries were a pre-Linuxbrew
workaround.
- **No `go mod tidy` in the release hooks** — it rewrites a tracked
file, so a release would
  mutate the tree it is releasing. `go mod verify` is read-only.
- **`go 1.26`, not `1.26.6`.** `go mod init` pinned my local patch,
which then refused to
  build in the goreleaser container at 1.26.5.

#### Not solved

The binary still needs pandoc, xelatex and poppler. "Single binary" is
portability and
packaging, not dependency elimination — stated in the README and the
skill.

- [x] Working tree clean after `make build && make clean`



### Fixed

- **Apply the calt fix instead of describing it (#3)**

#### What changed

`styles/text-layer.tex` now applies the fix it documents. Its only
executable content was
`\usepackage{fontspec}` plus tabular figures; the fix was prose telling
the reader to add
`RawFeature={-calt}` themselves.
`\defaultfontfeatures{RawFeature={-calt}}` applies it to every
font loaded afterwards.

Adds `schriftsatz verify <file.pdf>`, lifting the text-layer check out
of the test fixtures so
a reader can run it against their own document. It names the offending
Private Use Area
codepoints and cross-checks a second extractor.

#### Verified

Before, with the fragment included and Inter set by the user:

```
Materialaufwand 123,45 · (§ 4 Abs. 2 MusterG, ¼ 6.789,01     ← minus and paren gone
```


- **Publish real notes, and fold Unreleased into 0.1.0 (#8)**

Found by pre-flighting the release gates rather than by tagging and
seeing what happened.

**Empty release notes.** `changelog: disable: true` is correct — a
generated changelog beside
a hand-maintained one gives two sources that drift — but nothing
replaced the `--notes` step
lost in the move to goreleaser. `v0.1.0` would have shipped with an
empty body.

**Wrong content.** 0.1.0 has never been released, so the Go port, cask,
`verify` and skill all
sat under `[Unreleased]`. The first release would have described only
the original content.

#### Verified

```
extracted 47 lines, 3024 bytes
✓ Go binary   ✓ Homebrew   ✓ verify   ✓ skill
control (version with no section): 0 bytes
```

The workflow treats an empty extraction as a hard error, so this cannot
regress silently.

- [x] actionlint, goreleaser check, `make check` clean




# Contributing

## Scope

This project is deliberately small and intends to stay small. Before opening a feature
request, please read [docs/why-not.md](docs/why-not.md) — it lists what this project
does not do and which tool to use instead.

Things that will not be accepted:

- diagram embedding (use [pandoc-ext/diagram](https://github.com/pandoc-ext/diagram))
- a style-pack configuration language
- document templates, legal or otherwise
- HTML, DOCX or EPUB output
- anything requiring a runtime beyond bash, pandoc and a TeX distribution

Things that are very welcome:

- a case where `table-widths.lua` allocates badly, with a minimal reproducer
- confirmation or refutation of the `calt` finding on another platform, TeX
  distribution, PDF extractor or font
- portability fixes for Linux and Windows
- documentation that is clearer or more honest than what is here

## Working on it

```bash
git clone https://github.com/cronai-labs/schriftsatz
cd schriftsatz
./tests/run.sh
```

Requirements: `pandoc` ≥ 2.17, `xelatex` and `poppler-utils`. For the full suite also
[`uv`](https://docs.astral.sh/uv/) (which supplies `pypdf` on demand — you do not install it
yourself) and `qpdf`. `make setup` tells you what is missing.

## Tests

Every behavioural claim needs an assertion, and claims about a fix need a **negative
control** — a test proving the failure occurs without it. See `tests/calt-mwe/run.sh`.
A test that cannot fail is not a test.

`./tests/no-leaks.sh` must pass before any commit. It guards against material from the
private setup this project was extracted from, and it checks by SHAPE rather than by a
denylist — a denylist would publish in plaintext the very strings it exists to protect.

Install it as a hook so it runs automatically:

```bash
git config core.hooksPath .githooks
```

If you hold an exact-string list of private data, put it at
`~/.config/schriftsatz/denylist.txt` (or point `SCHRIFTSATZ_DENYLIST` at it) and the gate
applies it as a second layer. That list is deliberately never committed.

## Style

- Bash: `set -euo pipefail`, must pass `shellcheck`
- Lua: no dependencies; each filter stays a single file that can be copied out and used
  on its own
- Comments explain *why*, especially where behaviour is non-obvious or was arrived at by
  measurement. Record the measurement.

## Commits and branches

Work starts as an issue; branch from it so the branch is linked and named
`<issue-number>-<short-slug>`; the PR targets `main` and says `Closes #<n>`.

**The PR title follows [Conventional Commits](https://www.conventionalcommits.org)** and is
checked in CI. Branch commits are not linted, because the PR is squashed and the PR title
becomes the commit subject on `main` — that subject is what ends up in the changelog and is
what gets reverted, so it is the thing worth enforcing:

```
feat(filters): allow table capacity to be set from document metadata
fix(cli): write output next to the input instead of into the tool directory
docs(calt): correct the ToUnicode mechanism
test(styles): assert the signature block cannot be split
```

`make release` regenerates `CHANGELOG.md` from this history with `git-cliff` when it is
installed, and otherwise verifies the hand-written entry for the version. Either way the
commit message is what a reader of the release notes sees — write it for them.

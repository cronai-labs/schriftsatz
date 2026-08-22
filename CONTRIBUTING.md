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

```text
feat(filters): allow table capacity to be set from document metadata
fix(cli): write output next to the input instead of into the tool directory
docs(calt): correct the ToUnicode mechanism
test(styles): assert the signature block cannot be split
```

**`CHANGELOG.md` is generated and not tracked at all.** It is written at release time from the
commit history and shipped inside the release archives; the Releases page is the changelog of
record. `make changelog` writes a local copy if you want one to read.

That is not tidiness. A tracked file can only change on `main` through a pull request, so for as
long as the version lived in a tracked file, cutting a release required one. Deleting the file
from git is what removed the ceremony.

**Rehearse a release before tagging: `make release-dryrun`.** It runs the entire publish path —
build, archive, checksum, create the release, upload every asset, push the Homebrew cask —
against a mock GitHub on loopback, and asserts on what goreleaser actually sent. Nothing leaves
the machine and no tag is created.

This exists because four bugs reached users through a path that could not be tested without
using it: two releases published an empty body, one shipped a cask whose binary macOS killed on
sight, and one shipped tarballs containing no documentation. `goreleaser --snapshot` catches
none of them, because it skips publishing and so never computes a release body. A tag is
immutable, so anything wrong with what it publishes is permanent — which is what makes the
rehearsal worth the ninety seconds.

That has a consequence worth knowing before you write a PR description: **your description
becomes the changelog entry.** Squash-merging puts it into the commit body verbatim, so write
it for someone reading release notes later, not only for the reviewer today. Sections titled
Checklist, Not verified, or Needs a secret are stripped as process, and headings are demoted
so they nest under the version.

Put `Closes #n` at the **end** of the description if you can. A leading one is handled, but
only because a preprocessor removes it first: the conventional-commit parser reads a leading
`Closes #n` as a footer and swallows the entire body into it.

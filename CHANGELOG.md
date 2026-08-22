# Changelog

All notable changes to this project are documented here.

Generated from the commit history by [git-cliff](https://git-cliff.org) — do not
edit by hand, the next release overwrites it. Each entry's prose is the
description of the pull request that introduced the change.

This file is regenerated when a release is prepared, so it lags the history by
the single commit that regenerated it — a commit cannot describe itself. The
**GitHub release notes are authoritative**: they are generated from the history
at the moment the tag is pushed, and are complete.

## [0.1.1] - 2026-08-22


### Fixed

- **Use --current, and assert entries rather than bytes (#14)**

`v0.1.0` shipped an empty body past a step whose entire purpose was
preventing that.

`--unreleased` means *commits not contained in any tag* — and this
workflow is triggered **by
a tag push**, so the tag exists when it runs. I verified it locally
before tagging, the one
environment where the flag is correct.

| flags (tag present) | bytes | entries |
|---|---|---|
| `--unreleased --tag v0.1.0` | 23 | **0** |
| `--current` | 7362 | 8 |

The guard was `[ ! -s ]` — true for any non-empty file — so a bare
version heading passed it.
It now counts entries and prints what it got on failure.

#### Verified both directions

```
old output: bytes=26   entries=0  -> CAUGHT
new output: bytes=7366 entries=18 -> passes
```

The published v0.1.0 notes are already repaired (1 → 7325 bytes).

- [x] `make check`, actionlint clean


- **Strip the quarantine attribute so the cask is runnable (#16)**

`brew install --cask cronai-labs/tap/schriftsatz` succeeds, and then:

```
$ schriftsatz --version
$ echo $?
137
```

No output. 137 is SIGKILL — Gatekeeper kills it before `main()`, so the
program cannot report
its own failure.

#### It is not a broken signature

Go's linker ad-hoc signs the cross-compiled binaries and that signature
is valid:

```
CodeDirectory v=20400 flags=0x20002(adhoc,linker-signed)
$ codesign -v … ; echo $?
0
```

Homebrew tags cask downloads with `com.apple.quarantine`, and Gatekeeper
rejects an
ad-hoc-signed, non-notarized binary — `spctl -a -t exec` says
`rejected`.

#### Proof

Byte-identical copies, same sha256, differing only in one extended
attribute:

| binary | xattrs | result |
|---|---|---|
| as installed | `com.apple.quarantine` | **exit 137 (SIGKILL)**, no
output |
| `cp` + `xattr -c` | none | `schriftsatz 0.1.0`, exit 0 |

#### The tradeoff, stated rather than buried

Stripping the attribute removes Gatekeeper's check that the binary comes
from an identified
developer. The correct fix is Developer ID signing plus notarization
(paid Apple account) —
filed separately. Until then this hook is what makes the cask function,
and users are trusting
this tap directly.

#### New `package` job

Builds the real artifacts on every PR and asserts the **generated** cask
carries the hook — a
config can hold a hook that fails to render, so only the output is
evidence. Feeds
`ci-required`.

- [x] Negative-controlled: hook present → passes; hook removed → fails
on the missing `postflight`
- [x] `make check`, actionlint clean

#### Not fixed here

Two further defects this run surfaced, each filed on its own:
- goreleaser warns `glob=docs/**/*` matched nothing — the release
tarballs ship without any docs
- `no-leaks.sh` scans gitignored `dist/`, so `make check` fails for
anyone who has built


- **Ship the documentation in the archives (#20)**

goreleaser has been warning on every single build, and it went unread:

```
• no files matched   glob=docs/**/*
```

The published v0.1.0 tarballs contain `CHANGELOG.md LICENSE README.md
schriftsatz` — and none
of `docs/`. The three writeups that are most of the reason this repo
exists shipped in no
artifact at all.

#### Cause

goreleaser matches with `gobwas/glob`, where `**` spans separators and
the trailing `/*` then
demands a literal `/` after it. So `docs/**/*` matches only at depth ≥
2, and every doc is at
depth 1. Measured by building the archive and listing it:

| pattern | docs in tarball |
|---|---|
| `docs/**/*` (before) | **0** |
| `docs/**` (after) | 3 |

`docs/**` over `docs/*` so a future subdirectory is not dropped the same
way.

#### Guard

goreleaser only *warns* on an unmatched glob — that is why this shipped.
The `package` job now
lists the real archive and asserts every tracked doc is present,
enumerating
`git ls-files 'docs/*'` rather than checking a count, since a count
passes while a newly added
doc goes missing.

- [x] Zero `no files matched` warnings after the change
- [x] Negative-controlled: a listing with `docs/table-widths.md` removed
is caught
- [x] `make check`, actionlint clean



### Testing

- **Scan publishable files, not the working directory (#21)**

The scanner recursed the working directory, so it swept in gitignored
build output:

```
$ goreleaser release --snapshot
$ make check
LEAK mail address that is not a documented role address
       ./dist/config.yaml:18:      email: bot@goreleaser.com
no-leaks: 1 check(s) failed — DO NOT PUBLISH
```

That is goreleaser's own commit-author default, in generated output.

#### Why it mattered

Not because the finding was dangerous — `dist/` is gitignored and cannot
be published — but
because the gate's result depended on leftover build state. CI runs on a
fresh checkout and
stayed green; anyone who had built went red. A check that red-greens on
whether you happened to
build last is one people learn to ignore, which is the exact failure
mode this script exists to
prevent.

#### Fix

`git ls-files --cached --others --exclude-standard` — tracked files,
plus untracked files that
are not ignored. That preserves the property that actually matters (a
file one `git add` from
landing is still scanned, so a leak is caught **before** it becomes
history) while excluding
build output by construction instead of by a growing list of
`--exclude-dir` flags.

NUL-separated throughout; `xargs -r` so empty input cannot leave grep
reading stdin, and `--`
so a leading-dash path is not parsed as an option.

#### Controls, all four

| case | result |
|---|---|
| leak in a tracked file | caught |
| leak in an untracked, unignored file | caught before it lands |
| populated gitignored `dist/` | ignored, gate green |
| leak appended to this script itself | caught — self-scan intact |

That last one is load-bearing: this script was itself the leak once, so
it must never stop
scanning itself.

- [x] shellcheck clean, `make check` ok


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


- **Generate the changelog from history, one release path (#10)**

The changelog was hand-maintained while `cliff.toml` and
`scripts/release.sh` sat unused —
and `release.sh` was referenced nowhere in the release workflow. Two
paths that disagreed.

The justification for keeping it manual was **wrong**: squash-merging
puts the PR description
into the commit body, so the prose is already in the history and
git-cliff renders bodies.

#### Three bugs had to be fixed for generation to actually work

- A leading `Closes #n` made the conventional-commit parser treat the
entire body as a footer
value, so `commit.body` was null — that is why the first attempt
rendered subjects only.
- PR `##` headings landed level with the version heading, breaking the
hierarchy.
- Reviewer-facing sections (Checklist and friends) became release notes.

Rust's regex crate has no lookahead, so the section strip is written
without one.

#### Verified

| | |
|---|---|
| bodies populated | 4/4 commits, 6.2 KB prose |
| release notes | 6117 bytes |
| control (empty range) | 0 bytes |
| `grep -qP`, `bash 3.2`, Homebrew, golden comparison | all retained |
| heading depth | `## [0.1.0]` → `### Added` → `#### Why` |

- [x] `make check`, actionlint clean




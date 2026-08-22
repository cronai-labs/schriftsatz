---
type: decision
title: Merging to main publishes the release; no release pull request
description: >-
  The version moved out of a tracked file and into the git tag, so a release no
  longer needs a pull request. Revisit if the tag ruleset, the App, or
  goreleaser's draft-then-undraft ordering changes.
tags: [ci, release, goreleaser, github]
sources:
  - { name: "probed the GitHub Releases API directly in a throwaway repository", credibility: verified-firsthand }
  - { name: "goreleaser v2.17.1 source, internal/client/github.go", credibility: verified-firsthand }
verified: true
verified_on: 2026-08-22
stale_after: 2027-02-22
status: active
---

# Merging to main publishes the release

## What was decided

Merging a pull request to `main` publishes a release, with no further human action. The version
comes from the Conventional Commit titles, computed by git-cliff. No tracked file records a
version.

## Why the old flow required a pull request

`CHANGELOG.md` was the version source of truth and was tracked. A tracked file can only change
on `main` through a pull request, so cutting a release required one. That was never a policy
decision — it was a consequence of where the number lived. Deleting the file from git is what
removed the ceremony.

## Why this is safe despite immutable tags

`release-tag-immutability` has **no bypass actor**: a tag cut in error is permanent for
everyone, including an org owner. The design is safe because of *when* the tag comes into
existence.

goreleaser always creates the GitHub release as a **draft** (`internal/client/github.go`,
`Draft: new(true)` — *"Always start with a draft release while uploading artifacts.
PublishRelease will undraft it."*), uploads every asset, then PATCHes `draft:false`. GitHub
creates the git tag from `target_commitish` at that final call.

Probed directly against the API on 2026-08-22:

| step | tag created? |
|---|---|
| draft release naming a non-existent tag | no |
| PATCH `draft:false` | **yes**, at the exact `target_commitish` |
| draft created then deleted | no |

So the build, cross-compiles, checksums, five asset uploads and a complete mock-GitHub
rehearsal all happen while the version number is still unspent.

`tests/release-dryrun.sh` asserts that ordering on every pull request, so a goreleaser upgrade
that reordered it would be caught in a rehearsal rather than on a real tag.

## The tag ruleset governs the API call

Verified in a throwaway repository with an equivalent `creation` rule and no bypass:

```text
HTTP 422  field: pre_receive
"Cannot create ref due to creations being restricted."
"Published releases must have a valid tag"
```

The App is therefore a required `Integration` bypass actor on `release-tag-creation` (21163432).
It fails **safe**: 422, no tag, no version spent, and the orphaned draft is cleared by the next
run.

## What this gives up

- **A docs-only merge cuts a patch release.** `no_increment_regex` is documented upstream but had
  no effect in git-cliff 2.13.1 with this config, tested three ways. The only lever that works is
  `commit_parsers ... skip = true`, which would also drop docs from the changelog.
- **A failure after the un-draft spends the version number permanently.** The two that live in
  that window are the cask push (`cask.Pipe` is `ContinueOnError`, so goreleaser reports it after
  the release is live) and the read-back verification steps. Recovery is
  `gh workflow run release.yml -f tag=vX.Y.Z`, which re-runs the publish against the existing
  tag. The hourly sweep does **not** cover this — it only repairs failures from before the tag
  existed.
- **`release.mode: replace` discards hand-edited release notes** on any later resume. If you edit
  a published body with `gh release edit`, a subsequent resume overwrites it.

## Re-check triggers

Not just the date. Re-verify when any of these happen:

- goreleaser changes its create/upload/publish ordering, or stops drafting first — the
  rehearsal's ordering assertions fail loudly if so
- the `release-tag-creation` ruleset or the App installation changes
- GitHub changes when a release creates its tag
- git-cliff's bump rules change, or `breaking_always_bump_major` is removed from `cliff.toml`
  (without it the first `feat!:` mints a permanent 1.0.0)

## Accepted debt

- Signing and notarising the macOS binaries, so the Homebrew cask no longer strips the
  quarantine attribute: tracked in issue #19. Until then users trust the tap directly.

#!/usr/bin/env sh
# Print the version this working tree represents.
#
# No version string is stored anywhere in this repository — not in the source,
# not in a manifest, not in CHANGELOG.md. The git tag is the sole record of a
# released version and this script is the only thing that reads it. goreleaser
# derives {{ .Version }} from the same tag by the same rule (the tag minus its
# leading v), so a released binary and a build made here cannot disagree about
# what a tag means; tests/run.sh asserts the chain end to end.
#
#   version.sh            the version for a build made here, now
#   version.sh --release  the same, but fail unless HEAD is exactly a release
set -u

mode=${1:-}

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  # An exported source tarball has no git. Nothing can be derived, so say so
  # rather than inventing a number that would read as a release.
  if [ "$mode" = "--release" ]; then
    echo "version.sh: not a git repository" >&2
    exit 1
  fi
  echo "0.0.0-unknown"
  exit 0
fi

# An exact tag on HEAD is a release, and is the only thing that is. --match
# keeps stray tags (a probe, a fork's naming) out of the answer.
exact=$(git describe --tags --exact-match --match 'v[0-9]*' 2>/dev/null || true)
if [ -n "$exact" ]; then
  echo "${exact#v}"
  exit 0
fi

if [ "$mode" = "--release" ]; then
  echo "version.sh: HEAD is not tagged; there is no release version here" >&2
  exit 1
fi

# Not a release, so produce something that cannot be mistaken for one — and
# that still works in a --depth 1 clone, where no tags are fetched at all and
# `git describe --tags` exits 128 with "No names found, cannot describe
# anything". $(shell ...) in a Makefile swallows that into an empty version and
# a binary that reports nothing, which is how this fails silently.
base=$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)
sha=$(git rev-parse --short=7 HEAD 2>/dev/null || echo unknown)
dirty=''
[ -n "$(git status --porcelain 2>/dev/null)" ] && dirty='-dirty'

if [ -n "$base" ]; then
  n=$(git rev-list --count "$base..HEAD" 2>/dev/null || echo 0)
  # Based on the NEXT patch version, not the last tag.
  #
  # SemVer 2.0 §11: a pre-release sorts BELOW its normal version. Basing on the
  # last tag produced 0.2.1-dev.3 for work done AFTER v0.2.1 — which sorts below
  # v0.2.1, so every development build claimed to predate the release it
  # follows, and anything comparing versions got it backwards.
  #
  #   0.2.1  <  0.2.2-dev.3+abc1234  <  0.2.2
  #
  # A patch bump rather than asking git-cliff for the real next version: it
  # needs no tools, is identical on every machine, and sorts correctly either
  # way — 0.2.2-dev.N is below 0.2.2 and below 0.3.0. A dev version's job is to
  # order and identify, not to predict the next release number.
  stripped=${base#v}
  major=${stripped%%.*}
  rest=${stripped#*.}
  minor=${rest%%.*}
  patch=${stripped##*.}
  printf '%s.%s.%s-dev.%s+%s%s\n' "$major" "$minor" "$((patch + 1))" "$n" "$sha" "$dirty"
else
  # No tags at all: 0.0.1-dev sorts below a future 0.0.1 and below everything after.
  printf '0.0.1-dev.0+%s%s\n' "$sha" "$dirty"
fi

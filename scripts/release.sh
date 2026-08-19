#!/usr/bin/env bash
# Tag-driven release. The version lives in exactly one place: bin/schriftsatz.
#
# Deliberately tag-driven rather than merge-driven: this repo publishes no
# package, so a release is a human decision about when the documentation and the
# findings are worth pointing someone at — not a consequence of merging.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(sed -n 's/^VERSION="\(.*\)"/\1/p' bin/schriftsatz)"
[ -n "$VERSION" ] || { echo "cannot read VERSION from bin/schriftsatz" >&2; exit 1; }

branch="$(git rev-parse --abbrev-ref HEAD)"
[ "$branch" = "main" ] || { echo "release must run on main (on $branch)" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "working tree is dirty" >&2; exit 1; }

tag="v$VERSION"
if git rev-parse "$tag" >/dev/null 2>&1; then
  echo "tag $tag already exists — bump VERSION in bin/schriftsatz first" >&2
  exit 1
fi

# Regenerate the changelog from the commit history when git-cliff is available
# (cliff.toml configures it). It is not a hard dependency: the repository is
# young enough that the 0.1.0 section is hand-written, and requiring a tool
# nobody has installed would just mean the release path never runs.
if command -v git-cliff >/dev/null 2>&1; then
  echo "▸ regenerating CHANGELOG.md with git-cliff"
  git-cliff --tag "v$VERSION" --output CHANGELOG.md
  if ! git diff --quiet CHANGELOG.md; then
    echo "  CHANGELOG.md changed — review it, commit, then re-run" >&2
    exit 1
  fi
else
  echo "▸ git-cliff not installed — checking the hand-written entry instead"
fi

if ! grep -q "^## \[$VERSION\]" CHANGELOG.md; then
  echo "CHANGELOG.md has no '## [$VERSION]' section" >&2
  exit 1
fi

echo "▸ verifying before tagging"
make check

git tag -a "$tag" -m "$tag"
echo "▸ tagged $tag"
echo "  push with: git push origin main --follow-tags"

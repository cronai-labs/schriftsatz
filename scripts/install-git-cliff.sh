#!/usr/bin/env sh
# Install the git-cliff pinned in .tool-versions into /usr/local/bin.
#
# Pinned and checksummed rather than `curl | bash` or an action that resolves a
# release through api.github.com at run time — the same reason actionlint is
# installed this way in ci.yml. It matters more here: git-cliff decides the
# VERSION NUMBER now, not just the prose, so which git-cliff runs is part of the
# release rather than a formatting detail.
#
# The version comes from .tool-versions, which is also what goreleaser-action
# reads via `version-file:` and what tests/release-dryrun.sh reads for its
# container image. The checksum lives here, keyed by version, and a version with
# no checksum is a hard failure — so bumping .tool-versions without recording
# the new digest cannot silently fall back to an unverified download.
set -eu

cd "$(dirname "$0")/.."

# This installs a linux/amd64 binary into /usr/local/bin. It exists for CI and
# says so, rather than failing on a developer machine with a confusing
# "sha256sum: command not found" (macOS has shasum, not sha256sum) or by
# unpacking an x86_64 binary onto an arm64 laptop. Locally, use the container
# the dry run already uses, or `brew install git-cliff`.
os=$(uname -s)
arch=$(uname -m)
if [ "$os" != "Linux" ] || { [ "$arch" != "x86_64" ] && [ "$arch" != "amd64" ]; }; then
  echo "install-git-cliff: this installs a linux/amd64 binary and is meant for CI." >&2
  echo "  detected $os/$arch. Locally: brew install git-cliff, or use the" >&2
  echo "  orhunp/git-cliff container that tests/release-dryrun.sh runs." >&2
  exit 1
fi

version=$(awk '$1 == "git-cliff" { print $2; exit }' .tool-versions)
[ -n "$version" ] || { echo "install-git-cliff: no git-cliff line in .tool-versions" >&2; exit 1; }

case "$version" in
  # sha256 of git-cliff-<version>-x86_64-unknown-linux-gnu.tar.gz.
  # Upstream publishes only .sha512 alongside the release, so these are computed
  # from the downloaded artefact; re-compute when bumping the pin:
  #   curl -fsSL <url> | shasum -a 256
  # Verified against the published artefact on 2026-08-22 (7538117 bytes).
  2.13.1) sha256=9a1263f24e59a2f508c7b3d3283c9dea94a8bf697f96dbc18cc783cac6284546 ;;
  *) echo "install-git-cliff: no checksum recorded for git-cliff $version" >&2
     echo "  add it to scripts/install-git-cliff.sh before bumping .tool-versions" >&2
     exit 1 ;;
esac

url="https://github.com/orhun/git-cliff/releases/download/v$version/git-cliff-$version-x86_64-unknown-linux-gnu.tar.gz"
curl -fsSL -o /tmp/git-cliff.tar.gz "$url"
echo "$sha256  /tmp/git-cliff.tar.gz" | sha256sum -c -
tar -xzf /tmp/git-cliff.tar.gz -C /usr/local/bin --strip-components=1 "git-cliff-$version/git-cliff"
git-cliff --version

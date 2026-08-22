#!/usr/bin/env bash
# Rehearse a full release against a fake GitHub, locally, in containers.
#
# Three bugs reached real users because nothing could exercise the publish path
# without publishing:
#
#   #14  --unreleased found nothing once the tag existed    -> empty release body
#   #23  changelog.disable silently disabled --release-notes -> empty body again
#   #16  the cask installed a binary macOS killed on sight
#
# `goreleaser --snapshot` cannot catch any of them: it skips publishing, so it
# never computes a release body — and an empty body was the bug twice. The CI
# guard that eventually caught it reads the body back AFTER publishing, by which
# point the release is already public.
#
# So: point goreleaser's github_urls at a local mock (tests/mockgh), let a
# complete release run happen against a socket, and assert on what it sent.
# Nothing leaves the machine, and no tag is created in the working repository.
#
# Usage: tests/release-dryrun.sh [--keep]
set -euo pipefail

cd "$(dirname "$0")/.."
REPO=$PWD

KEEP=0
if [ "${1:-}" = "--keep" ]; then KEEP=1; fi

# Parsed from the release workflow rather than pinned here. Rehearsing with a
# different goreleaser than the one that publishes would be theatre — and the
# two drifting apart is exactly the kind of thing nobody notices until a release.
GORELEASER_VERSION=$(sed -n "s/^ *version: *'\(v[0-9][^']*\)'.*/\1/p" \
  .github/workflows/release.yml | head -1)
if [ -z "$GORELEASER_VERSION" ]; then
  echo "release-dryrun: could not read the goreleaser version from .github/workflows/release.yml"
  echo "  it must be an exact quoted version, e.g. version: 'v2.17.1'"
  exit 1
fi
GORELEASER_IMAGE=goreleaser/goreleaser:$GORELEASER_VERSION
CLIFF_IMAGE=orhunp/git-cliff:latest
PORT=8099

if ! command -v docker >/dev/null; then
  echo "release-dryrun: docker is required"; exit 3
fi

# The version the release WOULD carry, from the single source of truth.
VERSION=$(sed -n 's/^## \[\([0-9][^]]*\)\].*/\1/p' CHANGELOG.md | head -1)
if [ -z "$VERSION" ]; then echo "release-dryrun: no version in CHANGELOG.md"; exit 1; fi
TAG="v$VERSION"

# Deliberately inside build/, not mktemp -d. Docker Desktop on macOS shares only
# a few host paths, and the private temp directory mktemp returns is not one of
# them — the mount silently produces an empty directory rather than an error.
# build/ is already gitignored and already what `make clean` removes.
WORK=$REPO/build/dryrun
cleanup () {
  # On Linux the container runs as root, so everything it wrote into the bind
  # mount is root-owned and the calling user cannot delete it — the rehearsal
  # then succeeds and the script still exits non-zero on the cleanup. macOS
  # hides this: Docker Desktop maps ownership back to the caller, so it only
  # ever appears on a CI runner. Hand the files back before removing them.
  if [ -d "$WORK" ] && [ -n "${GORELEASER_IMAGE:-}" ]; then
    docker run --rm -v "$WORK":/work --entrypoint sh "$GORELEASER_IMAGE" \
      -c "chown -R $(id -u):$(id -g) /work" >/dev/null 2>&1 || true
  fi
  if [ "$KEEP" -eq 1 ]; then echo "kept: $WORK"; return 0; fi
  rm -rf "$WORK"
}
trap cleanup EXIT
rm -rf "$WORK"; mkdir -p "$WORK/out"

echo "release-dryrun: rehearsing $TAG with goreleaser $GORELEASER_VERSION"

# A throwaway clone, so the tag never touches the working repository. It also
# means the rehearsal runs against COMMITTED state, which is what a real tag
# captures — uncommitted work being silently included is its own bug class.
git clone --quiet "$REPO" "$WORK/src"

# Cloning from a path leaves origin pointing at that path, and goreleaser infers
# owner/repo from the remote — so it would derive nonsense from a local path.
# Restore the real remote so the rehearsal exercises the real owner and name.
# Nothing reaches github.com regardless: every endpoint is redirected to the mock.
git -C "$WORK/src" remote set-url origin \
  "$(git -C "$REPO" remote get-url origin 2>/dev/null || echo https://github.com/cronai-labs/schriftsatz.git)"

# An annotated tag needs a committer identity, and a CI runner has none — this
# passed locally purely because a developer machine has one configured globally.
# Set it on the throwaway clone so no machine state is touched. Annotated rather
# than lightweight because that is what a real release pushes.
git -C "$WORK/src" config user.name  "release-dryrun"
git -C "$WORK/src" config user.email "dryrun@localhost"
# actions/checkout leaves a detached HEAD, which is fine here — that commit is
# exactly what we mean to rehearse — but the advice block is pure noise.
git -C "$WORK/src" config advice.detachedHead false

git -C "$WORK/src" tag -d "$TAG" >/dev/null 2>&1 || true
git -C "$WORK/src" tag -a "$TAG" -m "$TAG"

# The mock is harness, not payload, so take it from the working tree rather than
# the clone. Otherwise the rehearsal cannot run while the harness itself is
# being edited — and a test you must commit before you can run is a test people
# stop running.
#
# .git/info/exclude, not .gitignore: goreleaser refuses to release from a dirty
# tree, and this keeps the harness invisible to git without modifying a tracked
# file or inventing a commit that would then show up in the release notes.
echo "/tests/mockgh/" >>"$WORK/src/.git/info/exclude"
mkdir -p "$WORK/src/tests/mockgh"
cp "$REPO"/tests/mockgh/*.go "$WORK/src/tests/mockgh/"

# The same command the release workflow runs, so a flag that breaks there breaks
# here too. --current is load-bearing; --unreleased silently yields nothing once
# the tag exists, which is bug #14.
docker run --rm -v "$WORK/src":/repo -w /repo "$CLIFF_IMAGE" \
  --current --strip header >"$WORK/notes.md" 2>/dev/null
echo "  notes: $(wc -c <"$WORK/notes.md" | tr -d ' ') bytes, $(grep -c '^- ' "$WORK/notes.md" || true) entries"

# The real config, plus an endpoint override. Deriving it rather than editing
# .goreleaser.yaml keeps the shipped config the thing under test: the changelog
# settings, the cask, the hooks and the archives are all used verbatim.
cp .goreleaser.yaml "$WORK/dryrun.yaml"
cat >>"$WORK/dryrun.yaml" <<EOF

# appended by tests/release-dryrun.sh — never committed
github_urls:
  api: http://127.0.0.1:$PORT/
  upload: http://127.0.0.1:$PORT/
  download: http://127.0.0.1:$PORT
EOF

# Mock and goreleaser share one container so they meet on loopback. Host
# networking differs between macOS and Linux CI; loopback does not.
rc=0
docker run --rm \
  -v "$WORK/src":/src -v "$WORK/out":/out \
  -v "$WORK/dryrun.yaml":/dryrun.yaml -v "$WORK/notes.md":/notes.md \
  -w /src \
  -e GITHUB_TOKEN=dryrun-not-a-real-token \
  -e HOMEBREW_TAP_TOKEN=dryrun-not-a-real-token \
  --entrypoint sh "$GORELEASER_IMAGE" -c '
    set -e
    go run ./tests/mockgh -addr 127.0.0.1:'"$PORT"' -out /out >/tmp/mock.log 2>&1 &
    # Wait for the socket to be bound rather than sleeping a guessed interval.
    i=0
    while [ $i -lt 300 ]; do
      if grep -q listening /tmp/mock.log 2>/dev/null; then break; fi
      i=$((i+1)); sleep 0.1
    done
    if ! grep -q listening /tmp/mock.log 2>/dev/null; then
      echo "mock never came up:"; cat /tmp/mock.log; exit 1
    fi
    # The clone is bind-mounted from the host, so its files are owned by a uid
    # the container does not know. git then refuses to read it and goreleaser
    # reports the confusing "current folder is not a git repository".
    git config --global --add safe.directory /src
    goreleaser release -f /dryrun.yaml --clean --release-notes=/notes.md
    cp /tmp/mock.log /out/mock.log 2>/dev/null || true
  ' >"$WORK/goreleaser.log" 2>&1 || rc=$?

if [ "$rc" -ne 0 ]; then
  echo "release-dryrun: goreleaser failed (exit $rc)"
  tail -40 "$WORK/goreleaser.log" | sed 's/^/  /'
  exit 1
fi

# ── Assertions on what goreleaser actually SENT ─────────────────────────────
fails=0
# Takes the command, so no $? juggling and no chance of reading a stale status.
check () {
  msg=$1; shift
  if "$@" >/dev/null 2>&1; then
    printf '  ok   %s\n' "$msg"
  else
    printf '  FAIL %s\n' "$msg"
    fails=$((fails+1))
  fi
}

check "goreleaser created a release" test -f "$WORK/out/release-create.json"

if [ -f "$WORK/out/release-create.json" ]; then
  # bytes, entries, and whether the body is exactly the notes we generated.
  read -r body_bytes body_entries body_matches <<EOF
$(python3 - "$WORK/out/release-create.json" "$WORK/notes.md" <<'PY'
import json, sys
body = (json.load(open(sys.argv[1], encoding="utf-8")).get("body") or "")
notes = open(sys.argv[2], encoding="utf-8").read()
entries = sum(1 for line in body.splitlines() if line.startswith("- "))
print(len(body), entries, body.strip() == notes.strip())
PY
)
EOF
  echo "  release body: ${body_bytes} bytes, ${body_entries} entries"
  # The assertion this whole harness exists for.
  check "the release body carries entries (this shipped empty twice)" \
    test "${body_entries:-0}" -ge 1
  check "the release body is exactly the generated notes" \
    test "${body_matches}" = "True"
fi

for a in "schriftsatz_${VERSION}_darwin_arm64.tar.gz" \
         "schriftsatz_${VERSION}_darwin_amd64.tar.gz" \
         "schriftsatz_${VERSION}_linux_arm64.tar.gz" \
         "schriftsatz_${VERSION}_linux_amd64.tar.gz" \
         "checksums.txt"; do
  check "uploaded $a" grep -qxF "$a" "$WORK/out/assets.log"
done

# Archive contents. goreleaser only WARNS on a `files` glob that matches
# nothing, so docs/**/* matched zero files and v0.1.0 shipped with no
# documentation in any tarball (#17). Enumerate the tracked docs rather than
# checking a count, which passes while a newly added doc goes missing.
arch="$WORK/src/dist/schriftsatz_${VERSION}_darwin_arm64.tar.gz"
if [ -f "$arch" ]; then
  tar tzf "$arch" >"$WORK/archive.list"
  for f in README.md LICENSE CHANGELOG.md; do
    check "archive carries $f" grep -qxF "$f" "$WORK/archive.list"
  done
  missing=0
  while IFS= read -r f; do
    if ! grep -qxF "$f" "$WORK/archive.list"; then
      echo "       missing from the archive: $f"
      missing=1
    fi
  done <<EOF
$(git -C "$REPO" ls-files 'docs/*')
EOF
  check "archive carries every tracked doc" test "$missing" -eq 0
else
  check "the darwin_arm64 archive was built" false
fi

# The cask, exactly as it would land in the tap.
cask=""
for f in "$WORK/out"/contents-*.rb.json; do
  if [ -f "$f" ]; then cask=$f; break; fi
done
if [ -n "$cask" ]; then
  python3 -c "
import base64, json, sys
print(base64.b64decode(json.load(open(sys.argv[1]))['content']).decode())" \
    "$cask" >"$WORK/cask.rb"
  check "the cask strips the quarantine attribute" \
    grep -q 'com.apple.quarantine' "$WORK/cask.rb"
  check "the cask carries version $VERSION" \
    grep -q "version \"$VERSION\"" "$WORK/cask.rb"
else
  check "the cask was pushed" false
fi

if [ -s "$WORK/out/unhandled.log" ]; then
  echo "  note endpoints the mock does not implement (rehearsal may diverge):"
  sort -u "$WORK/out/unhandled.log" | sed 's/^/       /'
fi

echo
if [ "$fails" -eq 0 ]; then
  echo "release-dryrun: $TAG would publish correctly"
else
  echo "release-dryrun: $fails check(s) failed — DO NOT TAG"
  exit 1
fi

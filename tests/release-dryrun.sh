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
# --version X.Y.Z rehearses a version other than the one CHANGELOG.md declares.
# Unused today; it is what the release workflow will call once the version comes
# from the commit history rather than from a tracked file.
VERSION_OVERRIDE=""
while [ $# -gt 0 ]; do
  case $1 in
    --keep)      KEEP=1 ;;
    --version)   shift; VERSION_OVERRIDE=${1:-} ;;
    --version=*) VERSION_OVERRIDE=${1#--version=} ;;
    *) echo "release-dryrun: unknown argument: $1"; exit 2 ;;
  esac
  shift
done

# Both pins come from .tool-versions, the same file goreleaser-action reads via
# `version-file:`. Rehearsing with a different goreleaser than the one that
# publishes would be theatre; git-cliff was previously not pinned here at all,
# which matters because it decides the version number and not only the prose.
tv () { awk -v k="$1" '$1 == k { print $2; exit }' .tool-versions; }
GORELEASER_VERSION=v$(tv goreleaser)
CLIFF_VERSION=$(tv git-cliff)
if [ "$GORELEASER_VERSION" = "v" ] || [ -z "$CLIFF_VERSION" ]; then
  echo "release-dryrun: .tool-versions must pin both goreleaser and git-cliff"
  exit 1
fi
GORELEASER_IMAGE=goreleaser/goreleaser:$GORELEASER_VERSION
CLIFF_IMAGE=orhunp/git-cliff:$CLIFF_VERSION
PORT=8099

if ! command -v docker >/dev/null; then
  echo "release-dryrun: docker is required"; exit 3
fi

# The version the release WOULD carry, from the single source of truth.
# The version this rehearsal publishes. No tracked file records a version any
# more — the commit history does, and git-cliff is the function from one to the
# other. The release workflow passes --version so the rehearsal runs at exactly
# the version it is about to cut; a rehearsal at a different version is theatre.
VERSION=$VERSION_OVERRIDE
SYNTHETIC=0
if [ -z "$VERSION" ]; then
  VERSION=$(docker run --rm -v "$REPO":/repo -w /repo "$CLIFF_IMAGE" \
              --bump --unreleased --context 2>/dev/null \
            | python3 "$REPO/tests/bumped-version.py" || true)
  # On a pull request the checkout is refs/pull/N/merge, whose branch commits
  # are not conventional-commit-linted — only the PR TITLE is, and that title
  # does not exist as a commit until the squash. A branch of "wip" commits
  # therefore yields nothing to bump and git-cliff echoes the current tag back.
  # Rehearsing an already-published version would be misleading, so fall back to
  # a synthetic patch bump and say so: what this proves is the MECHANICS of
  # publishing, and every assertion below is built from $VERSION.
  latest=$(git -C "$REPO" tag -l 'v[0-9]*' --sort=-v:refname | head -1 | sed 's/^v//')
  if [ -z "$VERSION" ] || { [ -n "$latest" ] && [ "$VERSION" = "$latest" ]; }; then
    if [ -n "$latest" ]; then
      VERSION="${latest%.*}.$(( ${latest##*.} + 1 ))"
    else
      # No tags at all. Without this the arithmetic below yields ".1", which
      # then fails the semver check with a confusing message.
      VERSION="0.0.1"
    fi
    SYNTHETIC=1
    echo "release-dryrun: nothing releasable here — rehearsing the mechanics at $VERSION"
  fi
fi
VERSION=${VERSION#v}
printf '%s' "$VERSION" | grep -qE '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' \
  || { echo "release-dryrun: not a plain MAJOR.MINOR.PATCH: '$VERSION'"; exit 1; }
TAG="v$VERSION"

# Deliberately inside build/, not mktemp -d. Docker Desktop on macOS shares only
# a few host paths, and the private temp directory mktemp returns is not one of
# them — the mount silently produces an empty directory rather than an error.
# build/ is already gitignored and already what `make clean` removes.
# A FRESH directory per run, not a fixed path. Reusing one meant `rm -rf`
# followed immediately by a bind mount of the same inode, and on macOS the
# container then sees the PREVIOUS run's tree — goreleaser dies with
# "readdirent dist: no such file or directory" or, worse, rehearses against
# stale files. Reproduced by running this twice in a row.
WORK=$REPO/build/dryrun/$$
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
  # Tidy the parent when this was the last run; harmless if another is active.
  rmdir "$REPO/build/dryrun" 2>/dev/null || true
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
# goreleaser refuses to release from a dirty tree, and the mock is now a TRACKED
# file, so .git/info/exclude no longer hides it — that only ever worked while it
# was untracked. --skip-worktree tells git to stop comparing these paths against
# the index, so the working copy can differ and the tree still reads clean,
# without modifying a tracked file or inventing a commit that would then appear
# in the release notes.
mkdir -p "$WORK/src/tests/mockgh"
cp "$REPO"/tests/mockgh/*.go "$WORK/src/tests/mockgh/"
for f in "$WORK/src"/tests/mockgh/*.go; do
  rel=${f#"$WORK/src/"}
  git -C "$WORK/src" ls-files --error-unmatch "$rel" >/dev/null 2>&1 \
    && git -C "$WORK/src" update-index --skip-worktree "$rel"
done
# Anything genuinely new (a file added to the harness but not yet committed)
# still needs excluding, since skip-worktree only applies to tracked paths.
echo "/tests/mockgh/" >>"$WORK/src/.git/info/exclude"

# The same command the release workflow runs, so a flag that breaks there breaks
# here too. --current is load-bearing; --unreleased silently yields nothing once
# the tag exists, which is bug #14.
# Retried. On macOS the FIRST container invocation immediately after a host-side
# git write intermittently fails inside libgit2 with "corrupted loose reference
# file: HEAD" — the bind mount has not settled, and .git/HEAD reads short. It
# succeeds on the next attempt. This sits on the path that determines the
# version, so a transient here would be read as "nothing to release".
# --latest when there is nothing releasable, --current otherwise.
#
# --current renders the release the CURRENT COMMIT is tagged for, and on the
# synthetic path there is no such release: HEAD is already the last one, so the
# range is empty and git-cliff exits with "No tag exists for the current
# commit". Running the rehearsal on main right after a release hit exactly that.
# --latest renders the previous release instead, which is the right content for
# a run whose purpose is proving the MECHANICS rather than the render.
if [ "$SYNTHETIC" -eq 1 ]; then
  cliff_range=--latest
else
  cliff_range=--current
fi

cliff_ok=0
for attempt in 1 2 3; do
  if docker run --rm -v "$WORK/src":/repo -w /repo "$CLIFF_IMAGE" \
       "$cliff_range" --strip header >"$WORK/notes.md" 2>"$WORK/cliff.err"; then
    cliff_ok=1; break
  fi
  # Retry ONLY the known transient. The first container invocation after a
  # host-side git write intermittently dies inside libgit2 with "corrupted loose
  # reference file"; that is worth a second attempt. Anything else is
  # deterministic, and retrying it three times turns a clear error message into
  # "failed after 3 attempts" — which is how a real bug reads as flakiness.
  if ! grep -qi 'corrupted loose reference\|could not read' "$WORK/cliff.err"; then
    echo "release-dryrun: git-cliff failed and this is not the known transient"
    sed 's/^/  /' "$WORK/cliff.err"
    exit 1
  fi
  echo "  git-cliff hit the libgit2 transient (attempt $attempt), retrying"
  sleep 1
done
if [ "$cliff_ok" -ne 1 ]; then
  echo "release-dryrun: git-cliff failed after 3 attempts"
  sed 's/^/  /' "$WORK/cliff.err"
  exit 1
fi
echo "  notes: $(wc -c <"$WORK/notes.md" | tr -d ' ') bytes, $(grep -c '^[-*] ' "$WORK/notes.md" || true) entries"

# CHANGELOG.md is generated at release time and shipped in the archives rather
# than committed, so a fresh clone does not have one.
#
# Measured, because the two cases differ and it matters: goreleaser only WARNS
# on a `files` GLOB that matches nothing — which is how docs/**/* shipped empty
# tarballs — but it hard-ERRORS on a missing literal filename:
#
#   failed to find files to archive: globbing failed for pattern CHANGELOG.md:
#   matching "./CHANGELOG.md": file does not exist
#
# So this is protected twice over: goreleaser refuses to build the archive at
# all, and the assertion below would catch it if that ever softened.
docker run --rm -v "$WORK/src":/repo -w /repo "$CLIFF_IMAGE" \
  --tag "$TAG" -o CHANGELOG.md >/dev/null 2>&1 || true
git -C "$WORK/src" update-index --skip-worktree CHANGELOG.md 2>/dev/null || true

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
#
# Parameterised by scenario so the same path can rehearse both a first publish
# (the mock 404s the tag: goreleaser creates) and a resume against a release
# that already exists (the mock 200s: goreleaser updates). The second is the
# only recovery a repository with immutable tags has, and it was previously
# untested configuration — every rehearsal took the create path.
rehearse () {
  scenario=$1; outdir=$2
  mkdir -p "$WORK/$outdir"
  docker run --rm \
    -v "$WORK/src":/src -v "$WORK/$outdir":/out \
    -v "$WORK/dryrun.yaml":/dryrun.yaml -v "$WORK/notes.md":/notes.md \
    -w /src \
    -e GITHUB_TOKEN=dryrun-not-a-real-token \
    -e HOMEBREW_TAP_TOKEN=dryrun-not-a-real-token \
    --entrypoint sh "$GORELEASER_IMAGE" -c '
      set -e
      go run ./tests/mockgh -addr 127.0.0.1:'"$PORT"' -scenario '"$scenario"' -out /out >/tmp/mock.log 2>&1 &
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
    ' >"$WORK/goreleaser-$scenario.log" 2>&1
}

rc=0
rehearse fresh out || rc=$?
if [ "$rc" -ne 0 ]; then
  echo "release-dryrun: goreleaser failed (exit $rc)"
  tail -40 "$WORK/goreleaser-fresh.log" | sed 's/^/  /'
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
entries = sum(1 for line in body.splitlines() if line[:2] in ("- ", "* "))
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
  if [ "$SYNTHETIC" -eq 1 ]; then
    # Be honest about what that last assertion proved here. With nothing
    # releasable, the notes are the PREVIOUS release's, so this compared the
    # mock's round-trip of them against themselves — it proves the payload
    # survives the wire, not that a render is correct. The real render is
    # exercised on main, where there is something to release.
    echo "  note synthetic version: the notes were not re-rendered, only round-tripped"
  fi
fi

# ── The ordering IS the safety property ─────────────────────────────────────
# goreleaser creates the release as a DRAFT, uploads every asset, and only then
# PATCHes draft:false — and it is that PATCH that makes GitHub create the git
# tag, at release.target_commitish. Probed directly against the API: a draft
# naming a nonexistent tag creates no tag; the un-draft creates it; deleting the
# draft leaves none behind. So everything that can fail, fails while the version
# number is still unspent.
#
# Ruleset release-tag-immutability has no bypass actor at all, so a tag cut in
# error is permanent for everyone including an org owner. If a goreleaser
# upgrade ever reorders these calls, that stops being true — and this is where
# it gets found out, in a rehearsal rather than on a real tag.
lineno () { grep -nE "$1" "$WORK/out/requests.log" | sed -n "$2"'p' | cut -d: -f1; }
create=$(lineno    '^POST .*/releases$'         1)
lastasset=$(lineno '/assets$'                   '$')
undraft=$(lineno   '^PATCH .*/releases/[0-9]+$' 1)
cask=$(lineno      '^PUT .*/contents/Casks/'    1)
check "the release is created before any asset is uploaded" \
  test "${create:-0}" -lt "${lastasset:-0}"
check "the release is un-drafted only after the last asset (the tag is cut here)" \
  test "${undraft:-0}" -gt "${lastasset:-0}"
check "the cask is pushed after the release is published" \
  test "${cask:-0}" -gt "${undraft:-0}"

if [ -f "$WORK/out/release-create.json" ] && [ -f "$WORK/out/release-update.json" ]; then
  read -r is_draft target undrafted <<EOF
$(python3 "$REPO/tests/inspect-release-payloads.py" \
    "$WORK/out/release-create.json" "$WORK/out/release-update.json")
EOF
  check "the release is created as a DRAFT, so no tag exists yet" test "$is_draft" = True
  check "it is un-drafted at the very end" test "$undrafted" = False
  # target_commitish is inert while the tag already exists (the API ignores it
  # then), so this asserts the field is being SET correctly ahead of the flow
  # that will depend on it. Without it the API default is "the default branch",
  # which would cut the tag at whatever main happened to be.
  if [ "$target" != "-" ]; then
    check "it names the exact commit the tag must be created from" \
      test "$target" = "$(git -C "$WORK/src" rev-parse HEAD)"
  fi
fi

# ── Nothing may create a git ref ────────────────────────────────────────────
# The assertions above constrain the calls goreleaser DOES make; they cannot
# prove the absence of one. The mock answers any unrecognised path with 200 {},
# so a future goreleaser that created the tag itself via POST /git/refs would
# sail through every check above and the harness would still report success —
# a false pass whose cost is a permanent tag.
no_git_ref_created () { ! grep -qE '/git/(refs|tags)' "$WORK/out/requests.log"; }
check "nothing created a git ref (the tag must come from the un-draft)" \
  no_git_ref_created
# Any silently-mocked endpoint is also a divergence between the rehearsal and
# the real thing, so surface it as a failure rather than a printed note.
check "the rehearsal hit no unimplemented endpoint" \
  test ! -s "$WORK/out/unhandled.log"

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

# ── The recovery path ───────────────────────────────────────────────────────
# A release that dies after its tag exists can only be recovered by re-running
# against that same tag: the tag can never be moved or deleted, because ruleset
# release-tag-immutability has no bypass actor. goreleaser then takes the UPDATE
# path, and release.mode decides whether the body is repaired or the broken one
# is kept — which is why this config sets `replace`. Until now that was untested
# configuration: the mock 404s the tag by design, so every rehearsal exercised
# only the create path, and `keep-existing` would have looked fine forever.
rc=0
rehearse existing-release out-resume || rc=$?
if [ "$rc" -ne 0 ]; then
  echo "release-dryrun: the resume rehearsal failed (exit $rc)"
  tail -40 "$WORK/goreleaser-existing-release.log" | sed 's/^/  /'
  exit 1
fi
check "a re-run against an existing release updates it rather than creating one" \
  test ! -f "$WORK/out-resume/release-create.json"
if [ -s "$WORK/out-resume/release-updates.jsonl" ]; then
  # The FIRST patch of a resumed run carries the body; the second only flips
  # draft:false. Reading the last one would always report zero entries.
  resume_entries=$(python3 "$REPO/tests/first-body-entries.py" \
    "$WORK/out-resume/release-updates.jsonl")
  echo "  resumed body: ${resume_entries} entries"
  check "a re-run REPLACES the stale body (release.mode)" \
    test "${resume_entries:-0}" -ge 1
else
  check "the resumed run updated the release" false
fi

echo
if [ "$fails" -eq 0 ]; then
  echo "release-dryrun: $TAG would publish correctly"
else
  echo "release-dryrun: $fails check(s) failed — DO NOT TAG"
  exit 1
fi

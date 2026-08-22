#!/usr/bin/env bash
# Hard gate: nothing traceable to the private setup this tool was extracted from
# may appear in the repository.
#
# WHY THIS FILE CONTAINS NO DENYLIST
#
# The obvious implementation — an array of the real names, addresses, register
# numbers and figures to grep for — publishes, in plaintext, precisely what it
# exists to keep out. A reader of the gate learns the address the gate protects.
# An earlier version of this file did exactly that, and it also excluded itself
# from its own scan, so it reported "clean" while being the largest disclosure
# in the repository.
#
# So this checks SHAPES, not instances. It names only synthetic placeholder
# values, which makes the file safe to publish and, as a bonus, catches leaks
# nobody thought to enumerate.
#
# Layer 2 — an exact-string list of the real data — lives OUTSIDE the repository
# and is applied when present. Required for a pre-publication run, optional
# otherwise, so that CI and forks stay green.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

fails=0
flag () {
  printf '\033[31mLEAK\033[0m %s\n' "$1"
  printf '%s\n' "$2" | head -6 | sed 's/^/       /'
  fails=$((fails+1))
}
# This scans ITSELF. An earlier version excluded itself, which was necessary
# while it carried a literal denylist — and was exactly how a real figure,
# written into a comment that explained a previous leak, reached the repository
# unnoticed. The file now contains only shape rules and synthetic placeholders,
# so there is nothing to hide and no reason for an exemption.
#
# Scan only what could actually be published: files git tracks, plus files that
# are untracked and NOT ignored — i.e. everything that is in the repository or
# one `git add` away from it. Recursing the working directory instead swept in
# gitignored build output, so `make check` turned red for anyone who had run
# goreleaser (it grepped dist/config.yaml and flagged goreleaser's own bot
# address) and stayed green in CI, which always runs on a fresh checkout. A gate
# whose result depends on whether you happened to build last is a gate people
# learn to ignore.
#
# -z / NUL separators so paths containing spaces or newlines survive.
publishable () {
  git ls-files --cached --others --exclude-standard -z 2>/dev/null
}
# xargs -0 for NUL safety, -r so empty input does not leave grep reading stdin
# forever, and -- so a path beginning with a dash is not taken as an option.
scan () { publishable | xargs -0 -r grep -InIE -- "$1" 2>/dev/null; }

# ── 1. Money ────────────────────────────────────────────────────────────────
# Real figures leak in EITHER notation. A previous leak reached this repository
# by translating a German statement into English and swapping "." for "," — the
# old denylist held the German spelling and never saw the English one. So match
# the SHAPE of a currency amount in both conventions and allow only the invented
# values the docs and fixtures are built from. Note the deliberate absence of a
# worked example here: writing one out would put a real figure in this file,
# which is the mistake being described.
ALLOWED_MONEY='1\.234\.567,89|1,234,567\.89|45\.678,90|45,678\.90|2\.345,67|2,345\.67|123,45|6\.789,01|1\.204,00|1,204\.00|6,789\.01'
# Two shapes, because the earlier single pattern required a thousands group and
# therefore could not match any amount below 1000 — and small amounts are the
# dominant shape in the source this was extracted from.
#
#   German:  optional dot-grouping, COMMA decimal   123,45 · 1.234.567,89
#   English: comma grouping REQUIRED, dot decimal   1,234,567.89
#
# Every example above is one of the synthetic values this repository is built
# from, and that is deliberate: an earlier comment in this very file illustrated
# the rule with a REAL figure, which is the leak it exists to prevent.
#
# The English form deliberately requires the grouping. Without it the rule would
# match ordinary decimals such as a scale factor or a line-spacing constant, and
# a rule that cries wolf gets switched off. The residual gap is an
# English-notation amount below one thousand, which shape alone cannot separate
# from a version number or a measurement; that case is covered by the
# exact-string layer below, not by this rule.
# Anchored on both sides, or the rule matches fragments: "2,10" inside 2,106
# and "1,12" inside a sed range like '1,12p'. Ungrouped German amounts also
# require two or three integer digits, so a sed range or an ordinal cannot look
# like an amount. Residual gap: an amount below ten with a comma decimal.
MONEY_DE='(^|[^0-9.,])([0-9]{1,3}(\.[0-9]{3})+|[0-9]{2,3}),[0-9]{2}([^0-9]|$)'
MONEY_EN='(^|[^0-9.,])[0-9]{1,3}(,[0-9]{3})+\.[0-9]{2}([^0-9]|$)'
money=$(scan "$MONEY_DE|$MONEY_EN" | grep -vE "$ALLOWED_MONEY" || true)
[ -n "$money" ] && flag "currency amount that is not one of the documented synthetic values" "$money"

# ── 2. German postcode + city, and street-with-number ────────────────────────
addr=$(scan '\b[0-9]{5}\s+[A-ZÄÖÜ][a-zäöüß]+' | grep -vE 'EX4 2MP|12345 Example' || true)
[ -n "$addr" ] && flag "what looks like a real postal address" "$addr"

# ── 3. German commercial register numbers ────────────────────────────────────
hrb=$(scan '\bHR[AB]\s*[0-9]+' | grep -vE '00000000|Example' || true)
[ -n "$hrb" ] && flag "commercial register number" "$hrb"

# ── 4. Absolute paths and machine-local identity ─────────────────────────────
paths=$(scan '/(Users|home)/[a-z]' || true)
[ -n "$paths" ] && flag "absolute path containing a user directory" "$paths"

# ── 5. Personal mail addresses ───────────────────────────────────────────────
# The published contact address is a role address on the company domain.
# bot@goreleaser.com is goreleaser's own published commit-author default. It
# reaches CHANGELOG.md legitimately: the changelog is generated from commit
# bodies, and the commit that fixed this scanner quoted its own output, which
# named that address. It is a documented role address of a tool this project
# uses — exactly what this rule's exemption is for — not a personal one.
mail=$(scan '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' \
       | grep -vE 'security@|noreply@|example\.(com|org)|@commitlint|bot@goreleaser\.com' || true)
[ -n "$mail" ] && flag "mail address that is not a documented role address" "$mail"

# ── 6. German bookkeeping account codes ──────────────────────────────────────
skr=$(scan '\bSKR\s?0[34]\b' || true)
[ -n "$skr" ] && flag "reference to a German chart of accounts" "$skr"

# ── 7. Obsidian and vault-shaped references ──────────────────────────────────
# The wikilink pattern excludes a leading ':' so that POSIX bracket
# expressions like [[:blank:]] in a shell script are not mistaken for one.
# Each trigger word below is written with one character bracketed, so the
# pattern matches the word without the file containing the word. Now that this
# script scans itself, a rule written plainly would match its own definition.
vault=$(scan 'obsidia[n]|\[\[[^]:][^]]*\]\]|frontmatte[r]:|okf_versio[n]' || true)
[ -n "$vault" ] && flag "reference to the private vault or its conventions" "$vault"

# ── 8. Unfinished-work markers ───────────────────────────────────────────────
todo=$(scan '\b(T[O]DO|FIXM[E]|XX[X]|HAC[K]|WI[P])\b' || true)
[ -n "$todo" ] && flag "unfinished-work marker" "$todo"

# ── 9. Git identity (the tree is not the only thing published) ───────────────
if git rev-parse --git-dir >/dev/null 2>&1; then
  # Assert the history carries ONE identity, rather than matching a specific
  # address. Naming the expected address here would put it in a published file,
  # which is the same mistake the denylist made. What actually needs catching is
  # a stray identity — a commit from another machine, a bot, or a misconfigured
  # clone — and that shows up as a second entry regardless of what it is.
  # GitHub's own identities are excluded: for a pull_request event, checkout
  # builds refs/pull/N/merge, and that merge commit is authored by GitHub. It is
  # not a stray identity and it is not private data — but without this the rule
  # fires on every PR, which is how a useful gate gets switched off.
  ids=$(git log --format='%an <%ae>%n%cn <%ce>' 2>/dev/null \
        | grep -vE '@users\.noreply\.github\.com>|<noreply@github\.com>|\[bot\]' \
        | sort -u || true)
  n=$(printf '%s\n' "$ids" | grep -c . || true)
  [ "$n" -gt 1 ] && flag "history carries more than one identity ($n)" "$ids"
  hist=$(git log --format='%s%n%b' 2>/dev/null | grep -inE 'draf[t]|not yet file[d]|scratc[h]|T[O]DO' || true)
  [ -n "$hist" ] && flag "commit message describing unfinished work" "$hist"
fi

# ── 10. Optional exact-string layer, kept outside the repository ─────────────
LIST="${SCHRIFTSATZ_DENYLIST:-$HOME/.config/schriftsatz/denylist.txt}"
if [ -f "$LIST" ]; then
  hits=$(publishable | xargs -0 -r grep -InIFf "$LIST" 2>/dev/null || true)
  [ -n "$hits" ] && flag "matched the private denylist at $LIST" "$hits"
  echo "no-leaks: exact-string layer applied ($(grep -c . "$LIST") entries)"
elif [ "${SCHRIFTSATZ_STRICT:-0}" = "1" ]; then
  flag "SCHRIFTSATZ_STRICT=1 but no denylist at $LIST" "Create it before publishing, or unset SCHRIFTSATZ_STRICT."
else
  echo "no-leaks: exact-string layer not applied (no list at $LIST) — shape rules only"
fi

if [ "$fails" -eq 0 ]; then
  echo "no-leaks: clean"
else
  echo "no-leaks: $fails check(s) failed — DO NOT PUBLISH"
  exit 1
fi

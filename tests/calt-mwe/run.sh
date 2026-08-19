#!/usr/bin/env bash
# Build every variant of the reproducer and assert what each extractor sees.
#
# This suite deliberately contains NEGATIVE CONTROLS: it asserts that the
# unfixed variants DO break. A test that only checks the fix works cannot tell
# you whether it is still testing anything.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fails=0

build () { # $1=name  $2=\def flag
  # -jobname is required: with a command-line \def the first argument is not a
  # filename, so xelatex would otherwise name everything "texput" and each
  # variant would silently overwrite the last.
  if ! xelatex -interaction=batchmode -output-directory="$TMP" -jobname="$1" \
       "\\def\\$2{}\\input{mwe.tex}" >/dev/null 2>&1; then
    printf '  BUILD FAILED: %s\n' "$1"; fails=$((fails+1)); return 1
  fi
  [ -f "$TMP/$1.pdf" ] || { printf '  NO PDF: %s\n' "$1"; fails=$((fails+1)); return 1; }
}

# Strip ALL whitespace before asserting. pypdf in particular injects spaces
# derived from glyph positioning ("−123 ,45"), which says nothing about whether
# the character is encoded correctly — and encoding is what is under test.
strip_ws () { tr -d '[:space:]'; }

extract_poppler () { pdftotext "$TMP/$1.pdf" - 2>/dev/null | strip_ws; }
# pypdf is the SECOND extractor, and the whole point of the finding is that the
# two disagree — so it has to come from somewhere without polluting the machine.
# uv fetches it into an ephemeral environment per invocation: no virtualenv to
# create or activate, no --user install leaking into ~/.local, nothing to clean
# up. Falls back to a system pypdf if uv is absent, and skips if neither exists,
# because this extractor is optional and must not turn into a hard dependency.
if command -v uv >/dev/null 2>&1; then
  PYRUN="uv run --quiet --with pypdf python"
elif python3 -c 'import pypdf' >/dev/null 2>&1; then
  PYRUN="python3"
else
  PYRUN=""
fi

extract_pypdf () {
  [ -n "$PYRUN" ] || return 9
  $PYRUN - "$TMP/$1.pdf" 2>/dev/null <<'PY' | strip_ws
import sys
try: from pypdf import PdfReader
except ImportError: sys.exit(9)
print(''.join(p.extract_text() for p in PdfReader(sys.argv[1]).pages))
PY
}

assert () { # $1=label $2=haystack $3=needle $4=want(present|absent)
  local got=absent
  case "$2" in *"$3"*) got=present ;; esac
  if [ "$got" = "$4" ]; then
    printf '  ok   %-46s %s %s\n' "$1" "$4" "$3"
  else
    printf '  FAIL %-46s want %s, got %s: %s\n' "$1" "$4" "$got" "$3"; fails=$((fails+1))
  fi
}

echo "building variants..."
build unfixed     NOTHING
build nocase      NOCASE
build nocalt      NOCALT
build actualtext  USEACTUALTEXT

echo
echo "poppler (pdftotext):"
u=$(extract_poppler unfixed);    assert "unfixed drops the minus (control)"      "$u" "−123,45" absent
c=$(extract_poppler nocase);     assert "-case does NOT fix it (control)"        "$c" "−123,45" absent
n=$(extract_poppler nocalt);     assert "-calt fixes it"                         "$n" "−123,45" present
                                 assert "-calt keeps the parenthesis"            "$n" "(Klammer)" present
a=$(extract_poppler actualtext); assert "actualtext fixes it under poppler"      "$a" "−123,45" present

echo
echo "pypdf:"
if p=$(extract_pypdf nocalt); then
  # The unfixed and -case cells are asserted here too. An earlier version of the
  # write-up got both of them wrong precisely because nothing checked them: the
  # PUA character is PRESENT in the unfixed PDF, so pypdf returns mojibake
  # rather than a silently-deleted character the way poppler does.
  pu=$(extract_pypdf unfixed); assert "unfixed: pypdf has no real minus (control)" "$pu" "−123,45" absent
  pc=$(extract_pypdf nocase);  assert "-case: pypdf has no real minus (control)"   "$pc" "−123,45" absent
  assert "-calt fixes it under pypdf too"                  "$p" "−123,45" present
  pa=$(extract_pypdf actualtext)
  assert "actualtext FAILS under pypdf (the whole point)"  "$pa" "−123,45" absent
else
  echo "  skip no pypdf (install uv, or pip install pypdf)"
fi

echo
if [ "$fails" -eq 0 ]; then echo "all assertions passed"; else echo "$fails assertion(s) failed"; exit 1; fi

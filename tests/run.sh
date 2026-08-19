#!/usr/bin/env bash
# Full suite. Run from anywhere.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(dirname "$HERE")"
fails=0
step () { printf '\n\033[1m%s\033[0m\n' "$1"; }

# --no-pdf runs only the assertions that need pandoc, skipping everything that
# builds a PDF. That split matters: the filter behaviour is what varies across
# pandoc versions, and it can be checked in seconds with no TeX at all, whereas
# a TeX Live install costs tens of minutes. CI therefore runs --no-pdf across
# the pandoc matrix and the full suite once.
PDF=1
case "${1:-}" in
  --no-pdf) PDF=0 ;;
  "") ;;
  *) printf 'usage: run.sh [--no-pdf]\n' >&2; exit 2 ;;
esac

# pandoc is always required. The extractors are required only when PDFs are
# built, and then they are REQUIRED, not optional: a missing extractor makes
# grep search an empty string, which reports "ok" for any assertion phrased as
# "X must be absent". A leak-detecting test that passes because its tool is
# missing is worse than no test, so fail loudly instead.
need="pandoc"
[ "$PDF" -eq 1 ] && need="pandoc xelatex pdftotext pdfinfo"
for tool in $need; do
  command -v "$tool" >/dev/null || {
    printf 'tests: %s is required and not installed\n' "$tool" >&2
    exit 3
  }
done
ok ()   { printf '  ok   %s\n' "$1"; }
bad ()  { printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }

if [ "$PDF" -eq 1 ]; then
step "calt / ToUnicode text-layer assertions"
"$HERE/calt-mwe/run.sh" || fails=$((fails+1))
fi

step "table-widths: LaTeX-only guard"
t=$(mktemp -d)
printf '| A | B |\n|:---|---:|\n| x | 1 |\n' > "$t/t.md"
# "No-op" means the filter changes NOTHING for this writer, so the honest test
# is a with/without comparison — not a search for width markup. docx and odt
# always carry column definitions of their own, so grepping for them reports a
# failure whether or not the filter ran, which an earlier version of this test
# did. HTML is checked the same way, plus a direct assertion that no width
# attribute appears.
for fmt in html docx odt; do
  case "$fmt" in
    html)
      a=$(pandoc "$t/t.md" -t html 2>/dev/null)
      b=$(pandoc "$t/t.md" --lua-filter "$ROOT/filters/table-widths.lua" -t html 2>/dev/null)
      w=$(printf '%s' "$b" | grep -c 'colgroup') ;;
    *)
      pandoc "$t/t.md" -t "$fmt" -o "$t/plain.$fmt" 2>/dev/null
      pandoc "$t/t.md" --lua-filter "$ROOT/filters/table-widths.lua" -t "$fmt" -o "$t/filt.$fmt" 2>/dev/null
      # Zip containers: compare the XML payload, not the archive, since zip
      # metadata carries timestamps that differ between two runs.
      a=$(unzip -p "$t/plain.$fmt" '*.xml' 2>/dev/null)
      b=$(unzip -p "$t/filt.$fmt"  '*.xml' 2>/dev/null)
      w=0 ;;
  esac
  if [ "$a" = "$b" ] && [ "${w:-0}" -eq 0 ]; then
    ok "no-op for $fmt"
  else
    bad "$fmt output changed when the filter ran"
  fi
done

step "table-widths: measures content, not dashes"
printf -- '---\ntitle: t\n---\n\n| %s | B | C |\n|:---|:---|:---|\n| %s | %s | %s |\n' \
  "Description of the position as recorded in the ledger" \
  "Provisions for onerous contracts arising from long-term supply agreements" \
  "Recognised in accordance with the applicable measurement basis" \
  "Kapitalertragsteuerbescheinigung" > "$t/wide.md"
w_off=$(pandoc "$t/wide.md" -t latex | grep -o 'real{[0-9.]*}' | tr '\n' ' ')
w_on=$(pandoc "$t/wide.md" --lua-filter "$ROOT/filters/table-widths.lua" -t latex | grep -o 'real{[0-9.]*}' | tr '\n' ' ')
if [ -n "$w_on" ] && [ "$w_off" != "$w_on" ]; then
  ok "widths change with the filter ($w_on)"
else
  bad "filter had no effect (off='$w_off' on='$w_on')"
fi
uniq_on=$(printf '%s' "$w_on" | tr ' ' '\n' | sort -u | grep -c .)
if [ "$uniq_on" -gt 1 ]; then ok "widths are not a flat split"
else bad "widths are uniform — content was not measured"; fi

step "table-widths: -M table-capacity is honoured"
a=$(pandoc "$t/wide.md" -M table-capacity=80 --lua-filter "$ROOT/filters/table-widths.lua" -t latex | grep -o 'real{[0-9.]*}' | tr '\n' ' ')
b=$(pandoc "$t/wide.md" -M table-capacity=40 --lua-filter "$ROOT/filters/table-widths.lua" -t latex | grep -o 'real{[0-9.]*}' | tr '\n' ' ')
if [ "$a" != "$b" ]; then ok "capacity changes allocation"; else bad "capacity ignored"; fi

step "linebreaks: body text yes, code spans no"
# The backticks are a Markdown code span in the fixture, not a shell expansion,
# and single quotes are exactly what keeps them literal.
# shellcheck disable=SC2016
printf 'Path foo/bar and `code/with/slash`.\n' > "$t/lb.md"
out=$(pandoc "$t/lb.md" --lua-filter "$ROOT/filters/linebreaks.lua" -t latex)
case "$out" in *'foo/\allowbreak{}bar'*) ok "break inserted in body text" ;; *) bad "no break in body text" ;; esac
case "$out" in *'code/\allowbreak{}with'*) bad "code span was modified" ;; *) ok "code span untouched" ;; esac

step "linebreaks: LaTeX-only guard"
n=$(pandoc "$t/lb.md" --lua-filter "$ROOT/filters/linebreaks.lua" -t html | grep -c 'allowbreak')
if [ "$n" -eq 0 ]; then ok "no-op for html"; else bad "allowbreak leaked into html"; fi

if [ "$PDF" -eq 1 ]; then
step "CLI: builds, writes where told, does not pollute its own tree"
# Keep the build log: "CLI build failed" with no reason cost several CI round
# trips to diagnose a missing babel language package.
if "$ROOT/bin/schriftsatz" "$ROOT/examples/minimal.md" -o "$t/out.pdf" >"$t/cli.log" 2>&1; then
  if [ -f "$t/out.pdf" ]; then ok "built to the requested path"; else bad "no PDF at the requested path"; fi
    # build/ is where output is SUPPOSED to go; excluding it is the point of
  # having a designated directory. This checks nothing leaks anywhere else.
  stray=$(find "$ROOT" -name '*.pdf' -not -path '*/docs/*' -not -path '*/build/*' | head -1)
  if [ -z "$stray" ]; then ok "tool tree clean"; else bad "wrote into its own tree: $stray"; fi
  if command -v qpdf >/dev/null 2>&1; then
    if qpdf --check "$t/out.pdf" >/dev/null 2>&1; then ok "qpdf structural check"; else bad "qpdf reports a malformed PDF"; fi
  else printf '  skip qpdf not installed\n'; fi
else bad "CLI build failed"; sed -n '1,12p' "$t/cli.log" | sed 's/^/       /'; fi

step "formal.tex: imprint is opt-in and never leaks"
# Use a document that does NOT redefine \docimprint. formal-document.md does,
# so without formal.tex it fails to build — and an earlier version of this test
# read the resulting absent PDF, found nothing, and reported "ok". It could
# never fail. Build a plain document and assert on a PDF that actually exists.
printf -- '---\ntitle: t\n---\n\nPlain document.\n' > "$t/plain.md"
if "$ROOT/bin/schriftsatz" "$t/plain.md" -o "$t/noimp.pdf" >"$t/plain.log" 2>&1 && [ -s "$t/noimp.pdf" ]; then
  if pdftotext "$t/noimp.pdf" - 2>/dev/null | grep -qE "Street|Directors:|Registry"; then
    bad "imprint appeared without formal.tex"
  else ok "no imprint without formal.tex"; fi
else bad "control build failed — assertion would be vacuous"; sed -n '1,12p' "$t/plain.log" | sed 's/^/       /'; fi
printf -- '---\ntitle: t\n---\n\nHello.\n' > "$t/bare.md"
"$ROOT/bin/schriftsatz" "$t/bare.md" --style "$ROOT/styles/formal.tex" -o "$t/bare.pdf" >/dev/null 2>&1
if pdftotext "$t/bare.pdf" - 2>/dev/null | grep -qE "Street|Directors:|Registry"; then
  bad "default \\docimprint is not empty"
else ok "default imprint is empty"; fi

step "formal.tex: imprint reaches page 1 (the plain-page-style trap)"
"$ROOT/bin/schriftsatz" "$ROOT/examples/formal-document.md" \
  --style "$ROOT/styles/text-layer.tex" --style "$ROOT/styles/linebreaking.tex" \
  --style "$ROOT/styles/formal.tex" -o "$t/formal.pdf" >/dev/null 2>&1
pages=$(pdfinfo "$t/formal.pdf" 2>/dev/null | awk '/^Pages:/{print $2}')
miss=0
for p in $(seq 1 "${pages:-1}"); do
  pdftotext -f "$p" -l "$p" "$t/formal.pdf" - 2>/dev/null | grep -q "1 Example Street" || miss=$((miss+1))
done
if [ "$miss" -eq 0 ]; then ok "imprint on all $pages pages"; else bad "$miss page(s) missing the imprint"; fi

step "formal.tex: signature block cannot be split by a page break"
dp=""; np=""
for p in $(seq 1 "${pages:-1}"); do
  txt=$(pdftotext -f "$p" -l "$p" "$t/formal.pdf" - 2>/dev/null)
  printf '%s' "$txt" | grep -q "Exampleton, 1 January 2026" && dp="$p"
  printf '%s' "$txt" | grep -q "A. Placeholder — Director"  && np="$p"
done
if [ -n "$dp" ] && [ "$dp" = "$np" ]; then ok "date and signature on the same page (p$dp)"
else bad "signature block split: date on p${dp:-?}, name on p${np:-?}"; fi

fi   # end PDF-only assertions

step "CLI: argument handling"
if "$ROOT/bin/schriftsatz" --nonsense >/dev/null 2>&1; then bad "bad option should not exit 0"
elif [ $? -eq 2 ]; then ok "bad option exits 2"; else bad "bad option wrong exit code"; fi
if "$ROOT/bin/schriftsatz" >/dev/null 2>&1; then bad "no input should not exit 0"
elif [ $? -eq 2 ]; then ok "no input exits 2"; else bad "no input wrong exit code"; fi
if "$ROOT/bin/schriftsatz" --help >/dev/null 2>&1; then ok "--help exits 0"; else bad "--help failed"; fi

rm -rf "$t"
printf '\n'
if [ "$fails" -eq 0 ]; then echo "ALL TESTS PASSED"; exit 0; else echo "$fails failure(s)"; exit 1; fi

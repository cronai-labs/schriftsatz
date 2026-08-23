#!/usr/bin/env bash
# Full suite. Run from anywhere.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(dirname "$HERE")"

# The tool under test is the compiled binary, not a script. Build it if it is
# not there, so `./tests/run.sh` works on a fresh clone without the caller
# having to know to run `make build` first.
SS="$ROOT/build/schriftsatz"
if [ ! -x "$SS" ]; then
  # `bin`, not `build`: building the examples needs a TeX distribution, and the
  # fast path of this suite deliberately runs without one. Do not discard the
  # error — a swallowed build failure here cost two CI round trips.
  if ! ( cd "$ROOT" && make -s bin 2>&1 ); then
    printf 'tests: could not compile %s\n' "$SS" >&2
    exit 3
  fi
fi
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
# Materialise the embedded styles, so the suite exercises what the binary
# actually ships rather than whatever is in the working tree.
for s in text-layer linebreaking formal; do
  "$SS" --print-asset "styles/$s.tex" > "$t/emb-$s.tex" 2>/dev/null || true
done
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
      # Compare ONLY the content part. Comparing every .xml includes
      # docProps/core.xml, whose <dcterms:created> is a wall-clock timestamp —
      # two runs a second apart differ with no filter involved at all, which
      # made this assertion pass or fail on timing rather than on behaviour.
      case "$fmt" in docx) part='word/document.xml' ;; *) part='content.xml' ;; esac
      a=$(unzip -p "$t/plain.$fmt" "$part" 2>/dev/null)
      b=$(unzip -p "$t/filt.$fmt"  "$part" 2>/dev/null)
      [ -n "$a" ] || bad "$fmt: could not read $part — comparison would be vacuous"
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
# Snapshot BEFORE the run. Searching the whole tree instead reported a leftover
# examples/minimal.pdf as though this run had produced it — and that file is
# written by following the documentation, which tells the reader to run
# `schriftsatz examples/minimal.md`. A gate whose verdict depends on what an
# earlier run left behind is one people learn to ignore.
#
# build/ is where output is SUPPOSED to go; excluding it is the point of having
# a designated directory.
find "$ROOT" -name '*.pdf' -not -path '*/build/*' | sort > "$t/pdfs-before"
if "$SS" "$ROOT/examples/minimal.md" -o "$t/out.pdf" >"$t/cli.log" 2>&1; then
  if [ -f "$t/out.pdf" ]; then ok "built to the requested path"; else bad "no PDF at the requested path"; fi
  find "$ROOT" -name '*.pdf' -not -path '*/build/*' | sort > "$t/pdfs-after"
  stray=$(comm -13 "$t/pdfs-before" "$t/pdfs-after" | head -1)
  if [ -z "$stray" ]; then ok "tool tree clean"; else bad "wrote into its own tree: $stray"; fi
  if command -v qpdf >/dev/null 2>&1; then
    if qpdf --check "$t/out.pdf" >/dev/null 2>&1; then ok "qpdf structural check"; else bad "qpdf reports a malformed PDF"; fi
  else printf '  skip qpdf not installed\n'; fi
else bad "CLI build failed"; sed -n '1,12p' "$t/cli.log" | sed 's/^/       /'; fi

step "examples: each builds with the command it documents"
# The gate used to build the examples with a style set only the Makefile knew:
# --style for text-layer, linebreaking and formal, on every example. So CI proved
# a command no reader was given, while `schriftsatz examples/formal-document.md`
# — the command the documentation implies — failed on an undefined \docimprint.
#
# Each example now carries its own build command, and this runs THAT, verbatim,
# from the repository root. The documentation is the gate, so the two cannot
# drift. Output goes to the default path on purpose: where a build lands is part
# of what the command promises.
for f in "$ROOT"/examples/*.md; do
  name=$(basename "$f" .md)
  cmd=$(grep -m1 '^schriftsatz ' "$f")
  if [ -z "$cmd" ]; then bad "$name documents no build command"; continue; fi
  out="$ROOT/examples/$name.pdf"
  rm -f "$out"
  # Deliberately unquoted: the documented command is a line of arguments, and
  # splitting it on spaces is the point.
  # shellcheck disable=SC2086
  if ( cd "$ROOT" && "$SS" ${cmd#schriftsatz } ) >"$t/ex-$name.log" 2>&1; then
    if [ -s "$out" ]; then ok "$name builds with the command it documents"
    else bad "$name reported success but wrote no PDF at $out"; fi
  else
    bad "$name does not build with the command it documents: $cmd"
    sed -n '1,10p' "$t/ex-$name.log" | sed 's/^/       /'
  fi
  rm -f "$out"
done

step "--style: names an embedded style from a directory that is not a clone"
# The trap this replaces: `--style styles/formal.tex` appeared to work, because
# that relative path exists in a clone. Run it somewhere it does not.
printf -- '---\ntitle: t\n---\n\nPlain.\n' > "$t/emb.md"
if ( cd "$t" && "$SS" "$t/emb.md" --style styles/formal.tex -o "$t/emb.pdf" ) >"$t/emb.log" 2>&1 \
   && [ -s "$t/emb.pdf" ]; then
  ok "embedded style resolved by name outside the repository"
else
  bad "embedded style could not be named outside the repository"
  sed -n '1,8p' "$t/emb.log" | sed 's/^/       /'
fi
# A name that is neither a file nor embedded must be a usage error, not a
# xelatex failure hundreds of lines later.
if ( cd "$t" && "$SS" "$t/emb.md" --style styles/nope.tex -o "$t/nope.pdf" ) >/dev/null 2>&1; then
  bad "an unknown style name did not fail"
elif [ $? -eq 2 ]; then ok "an unknown style name exits 2 (control)"
else bad "an unknown style name exited with the wrong code"; fi

step "--style adds to the defaults rather than replacing them"
# The regression: --style used to DROP the default set, so `--style
# styles/formal.tex` — the documented way to add a footer — built without
# text-layer.tex and silently reintroduced the calt defect.
#
# The font is set in a header passed AFTER the styles, which is the ordering
# where \defaultfontfeatures reaches it. A font set in front matter is a
# different ordering and a separate defect; see the issue linked from
# styles/text-layer.tex.
cat > "$t/setfont.tex" <<'SFEOF'
\usepackage{fontspec}
\setmainfont{Inter-Regular.otf}
SFEOF
printf -- '---\ntitle: t\n---\n\nMaterialaufwand −123,45\n' > "$t/add.md"
if "$SS" "$t/add.md" --style styles/formal.tex --style "$t/setfont.tex" -o "$t/add.pdf" >/dev/null 2>&1 \
   && [ -s "$t/add.pdf" ]; then
  got=$(pdftotext "$t/add.pdf" - 2>/dev/null | tr -d '[:space:]')
  case "$got" in *"−123,45"*) ok "text-layer fix survives adding a style" ;;
                 *) bad "adding a style dropped the text-layer fix" ;; esac
  # Negative control: --no-default-style must still drop them, or the flag is a
  # no-op and this assertion proves nothing.
  "$SS" "$t/add.md" --no-default-style --style "$t/setfont.tex" -o "$t/nodef.pdf" >/dev/null 2>&1
  none=$(pdftotext "$t/nodef.pdf" - 2>/dev/null | tr -d '[:space:]')
  case "$none" in *"−123,45"*) bad "control: --no-default-style did not drop the defaults" ;;
                  *) ok "control: --no-default-style drops them" ;; esac
else
  printf '  skip Inter not installed — cannot exercise the style ordering\n'
fi

step "the document decides: front matter beats the CLI's defaults"
# Every one of these was forced with -V, which overrides a document's own front
# matter. A file declaring `lang: de-DE` was typeset with British hyphenation and
# shipped a catalogue /Lang of en-GB. The defaults now travel by
# --metadata-file, which pandoc lets the document override.
printf -- '---\ntitle: t\nlang: de-DE\n---\n\nHallo Welt.\n' > "$t/de.md"
"$SS" "$t/de.md" --keep-tex -o "$t/de.pdf" >/dev/null 2>&1
if grep -q 'ngerman' "$t/de.tex" 2>/dev/null; then ok "front matter lang is honoured"
else bad "front matter lang was overridden by the CLI default"; fi
# Control: the flag must still win, or --lang has become decorative.
"$SS" "$t/de.md" --lang fr-FR --keep-tex -o "$t/fr.pdf" >/dev/null 2>&1
if grep -q 'french' "$t/fr.tex" 2>/dev/null; then ok "control: an explicit --lang still beats the document"
else bad "--lang no longer overrides the document"; fi

# report, not scrartcl: the PDF is built before the .tex is written, so a class
# that is not installed would fail the build and leave nothing to assert on.
printf -- '---\ntitle: t\ndocumentclass: report\nfontsize: 12pt\n---\n\nx\n' > "$t/dc.md"
"$SS" "$t/dc.md" --keep-tex -o "$t/dc.pdf" >/dev/null 2>&1
if grep -q '{report}' "$t/dc.tex" 2>/dev/null && grep -q '12pt' "$t/dc.tex" 2>/dev/null; then
  ok "documentclass and fontsize come from the document"
else bad "documentclass/fontsize are still forced by the CLI"; fi

step "paper size: A4 by default, and the document may still choose"
paper () { pdfinfo "$1" 2>/dev/null | sed -n 's/^Page size:.*(\(.*\))$/\1/p'; }
"$SS" "$t/de.md" -o "$t/a4.pdf" >/dev/null 2>&1
got=$(paper "$t/a4.pdf")
# Everything here already assumes A4: table-widths.lua measured its capacity for
# it and formal.tex sets a4paper. The tool shipped US Letter regardless.
if [ "$got" = "A4" ]; then ok "default paper is A4"; else bad "default paper is '$got', not A4"; fi
printf -- '---\ntitle: t\npapersize: letter\n---\n\nx\n' > "$t/lt.md"
"$SS" "$t/lt.md" -o "$t/lt.pdf" >/dev/null 2>&1
got=$(paper "$t/lt.pdf")
if [ "$got" = "letter" ]; then ok "control: a document may still choose its own paper"
else bad "papersize in the document was ignored (got '$got')"; fi

step "indent: the default is block paragraphs, not first-line indentation"
# -V indent=false set the non-empty STRING "false", which pandoc's template
# language treats as TRUE — so the setting that says it disables indentation was
# switching it on. parskip is loaded only on the not-indented branch.
printf -- '---\ntitle: t\n---\n\nOne.\n\nTwo.\n' > "$t/ind.md"
"$SS" "$t/ind.md" --keep-tex -o "$t/ind.pdf" >/dev/null 2>&1
if grep -q 'usepackage{parskip}' "$t/ind.tex" 2>/dev/null; then ok "block paragraphs by default"
else bad "the indent default is inverted — paragraphs are first-line indented"; fi
printf -- '---\ntitle: t\nindent: true\n---\n\nOne.\n\nTwo.\n' > "$t/ind2.md"
"$SS" "$t/ind2.md" --keep-tex -o "$t/ind2.pdf" >/dev/null 2>&1
if grep -q 'usepackage{parskip}' "$t/ind2.tex" 2>/dev/null; then
  bad "control: indent: true did not switch indentation on"
else ok "control: indent: true switches indentation on"; fi

step "--keep-tex writes the source of the PDF beside it"
# The .tex run never carried -M table-capacity, so --capacity changed the PDF and
# not the .tex sitting next to it. Both invocations are now built by one function.
"$SS" "$ROOT/examples/minimal.md" --capacity 40 --keep-tex -o "$t/c40.pdf" >/dev/null 2>&1
"$SS" "$ROOT/examples/minimal.md" --capacity 80 --keep-tex -o "$t/c80.pdf" >/dev/null 2>&1
w40=$(grep -o 'real{[0-9.]*}' "$t/c40.tex" 2>/dev/null | tr '\n' ' ')
w80=$(grep -o 'real{[0-9.]*}' "$t/c80.tex" 2>/dev/null | tr '\n' ' ')
if [ -n "$w40" ] && [ "$w40" != "$w80" ]; then ok "--capacity reaches the .tex ($w40)"
else bad "--keep-tex ignored --capacity (40='$w40' 80='$w80')"; fi
# Control: a failure must be reported, not discarded. A directory where the .tex
# belongs is a write pandoc cannot make.
mkdir -p "$t/kt/blocked.tex"
if "$SS" "$ROOT/examples/minimal.md" --keep-tex -o "$t/kt/blocked.pdf" >/dev/null 2>&1; then
  bad "control: --keep-tex swallowed a write failure and exited 0"
else ok "control: a --keep-tex failure is reported"; fi

step "text-layer.tex applies the fix, not just a comment about it"
# This is the assertion the project most needs and least obviously needs: the
# LaTeX default font never exhibits the defect, so a fragment that documents the
# fix without applying it passes every other test in this suite. Use a font that
# DOES exhibit it, and check the extracted text.
cat > "$t/tl.tex" <<'TLEOF'
\usepackage{fontspec}
\setmainfont{Inter-Regular.otf}[Numbers={Proportional,Lining}]
TLEOF
printf -- '---\ntitle: t\n---\n\nMaterialaufwand −123,45 · (Klammer) −42\n' > "$t/tl.md"
if pandoc "$t/tl.md" --pdf-engine=xelatex \
     -H "$t/emb-text-layer.tex" -H "$t/tl.tex" -o "$t/tl.pdf" >/dev/null 2>&1; then
  got=$(pdftotext "$t/tl.pdf" - 2>/dev/null | tr -d '[:space:]')
  case "$got" in *"−123,45"*) ok "minus survives with a user-set Inter" ;;
                 *) bad "minus LOST — text-layer.tex is not applying -calt" ;; esac
  case "$got" in *"(Klammer)"*) ok "parentheses survive" ;;
                 *) bad "parentheses lost" ;; esac
  # Negative control: without the fragment the defect must reappear, or this
  # test is measuring nothing.
  pandoc "$t/tl.md" --pdf-engine=xelatex -H "$t/tl.tex" -o "$t/tl-none.pdf" >/dev/null 2>&1
  none=$(pdftotext "$t/tl-none.pdf" - 2>/dev/null | tr -d '[:space:]')
  case "$none" in *"−123,45"*) bad "control: defect did not reproduce without the fragment" ;;
                  *) ok "control: without the fragment the minus is lost" ;; esac
else
  printf '  skip Inter not installed — cannot exercise the text-layer fix\n'
fi

step "verify: usable by a reader on their own PDF"
if pandoc "$t/tl.md" --pdf-engine=xelatex -H "$t/tl.tex" -o "$t/tl-bad.pdf" >/dev/null 2>&1 \
   && [ -s "$t/tl.pdf" ]; then
  if "$SS" verify "$t/tl.pdf" >/dev/null 2>&1; then
    ok "verify passes a faithful PDF"
  else bad "verify rejected a faithful PDF"; fi
  # Negative control: it must FAIL the defective one, or it asserts nothing.
  if "$SS" verify "$t/tl-bad.pdf" >/dev/null 2>&1; then
    bad "verify passed a PDF with Private Use Area codepoints"
  else ok "verify rejects a defective PDF (control)"; fi
else
  printf '  skip Inter not installed — cannot exercise verify\n'
fi

step "verify: a table document is not a false positive"
# The composition nothing tested: the flagship feature (tables) and the flagship
# check (verify) in one document. verify compared the two extractions as
# SEQUENCES, and poppler walks a table column by column while pypdf walks it row
# by row — so verify rejected every table document, this project's own examples
# included. Deliberately font-independent: reading order has nothing to do with
# which font is installed, so this runs everywhere rather than only where Inter
# is present. The negative control for encoding faults lives in
# cmd/schriftsatz/verify_test.go, which does not need a font at all.
{
  printf -- '---\ntitle: t\n---\n\n'
  printf -- '| Item | Reference | Amount |\n|---|---|---|\n'
  printf -- '| Consulting services rendered | INV-2026-0042/A | 1.204,00 |\n'
  printf -- '| Licence, annual | INV-2026-0043/B | 123,45 |\n'
} > "$t/tbl.md"
if "$SS" "$t/tbl.md" -o "$t/tbl.pdf" >/dev/null 2>&1; then
  if "$SS" verify "$t/tbl.pdf" >/dev/null 2>&1; then
    ok "verify accepts a document containing a table"
  else
    bad "verify rejected a table document"
    "$SS" verify "$t/tbl.pdf" 2>&1 | sed 's/^/       /'
  fi
else
  printf '  skip could not build the table document\n'
fi

step "formal.tex: imprint is opt-in and never leaks"
# Use a document that does NOT redefine \docimprint. formal-document.md does,
# so without formal.tex it fails to build — and an earlier version of this test
# read the resulting absent PDF, found nothing, and reported "ok". It could
# never fail. Build a plain document and assert on a PDF that actually exists.
printf -- '---\ntitle: t\n---\n\nPlain document.\n' > "$t/plain.md"
if "$SS" "$t/plain.md" -o "$t/noimp.pdf" >"$t/plain.log" 2>&1 && [ -s "$t/noimp.pdf" ]; then
  if pdftotext "$t/noimp.pdf" - 2>/dev/null | grep -qE "Street|Directors:|Registry"; then
    bad "imprint appeared without formal.tex"
  else ok "no imprint without formal.tex"; fi
else bad "control build failed — assertion would be vacuous"; sed -n '1,12p' "$t/plain.log" | sed 's/^/       /'; fi
printf -- '---\ntitle: t\n---\n\nHello.\n' > "$t/bare.md"
"$SS" "$t/bare.md" --style "$t/emb-formal.tex" -o "$t/bare.pdf" >/dev/null 2>&1
if pdftotext "$t/bare.pdf" - 2>/dev/null | grep -qE "Street|Directors:|Registry"; then
  bad "default \\docimprint is not empty"
else ok "default imprint is empty"; fi

step "formal.tex: imprint reaches page 1 (the plain-page-style trap)"
"$SS" "$ROOT/examples/formal-document.md" \
  --style "$t/emb-text-layer.tex" --style "$t/emb-linebreaking.tex" \
  --style "$t/emb-formal.tex" -o "$t/formal.pdf" >/dev/null 2>&1
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

step "version: one source of truth, no drift"
# The git tag is the source. scripts/version.sh is the only thing that reads it,
# the Makefile injects what that script says through -ldflags, and goreleaser
# derives {{ .Version }} from the same tag by the same rule (tag minus leading
# v). Nothing in the source records a version, so there is nowhere for one to
# drift to — these assertions are what keeps that true.
v=$("$ROOT/scripts/version.sh")
if [ -n "$v" ]; then ok "scripts/version.sh prints a version ($v)"
else bad "scripts/version.sh printed nothing"; fi

# Rebuild first: the version now changes with every commit rather than once per
# release, so a binary left from the previous commit reports a stale value and
# this would fail for a reason unrelated to drift.
make -C "$ROOT" -s bin >/dev/null 2>&1 || true
# An EXACT field comparison, not `grep -q "$v"`. The substring form matched
# "0.1.1" inside "0.1.1-dev.5+abc1234" just as happily, so it could not see the
# drift most likely to happen now that dev versions exist.
reported=$("$SS" --version 2>/dev/null | awk '{print $NF}')
if [ "$reported" = "$v" ]; then ok "the binary reports exactly that"
else bad "binary reports '${reported:-}', version.sh says '$v'"; fi

if [ "$(make -C "$ROOT" -s version 2>/dev/null)" = "$v" ]; then
  ok "make version agrees"
else bad "make version disagrees"; fi

# A negative control. The three above all pass if the injection path is dead and
# every reader independently reports the same wrong thing; this one fails in
# that case, because it forces a value nothing could derive.
tv="$t/versioned"
if make -C "$ROOT" -s bin VERSION=9.9.9-drift BIN="$tv" >/dev/null 2>&1 \
   && [ "$("$tv" --version 2>/dev/null)" = "schriftsatz 9.9.9-drift" ]; then
  ok "an explicit VERSION reaches the binary (the release path in miniature)"
else bad "VERSION= did not reach the binary — ldflags injection is broken"; fi

# One source of truth means one implementation. The two shapes a second one
# takes are asking git directly and parsing a heading out of a changelog; both
# were real here, with the same sed copied into four files.
#
# The exemption those two files carried until #30 landed is gone with the
# readers it covered: nothing parses a version out of CHANGELOG.md any more.
#
# What this forbids is a second way to derive the BUILD version — `git describe`
# outside version.sh, or parsing a `## [x.y.z]` heading. It deliberately does
# not forbid `git tag -l`: asking which tag is newest is a different question
# from deriving a version, and the release workflow legitimately does it while
# verifying what it published. So this is narrower than its name suggests, and
# saying so is better than an assertion people believe covers more than it does.
# A subshell with an explicit exit rather than `cd X && ... || true`, which
# SC2015 flags on the 0.9.0 that CI runs but not on newer local versions.
# (Do not start that explanation with the linter's name at the beginning of a
# comment line — it is parsed as a directive and errors with SC1073.)
# Hoisted out of the command substitution: the escaped `##` inside a quoted
# argument in a $( ) is mis-parsed by the 0.9.0 that CI runs, which then reports
# an unrelated "couldn't find fi" hundreds of lines later.
stray_re='git describe|s/\^## '
stray_known='^(scripts/version\.sh|tests/run\.sh)$'
strays=$(
  cd "$ROOT" || exit 0
  git grep -lE "$stray_re" -- Makefile scripts tests .github 2>/dev/null \
    | grep -vE "$stray_known" \
    || true
)
if [ -z "$strays" ]; then ok "no second place computes a version"
else bad "these compute a version of their own: $(printf '%s' "$strays" | tr '\n' ' ')"; fi

# A development version must sort ABOVE the release it follows and BELOW the
# next one. It did neither: version.sh based it on the LAST tag, so 0.2.1-dev.3
# — work done after v0.2.1 — sorted below v0.2.1, because SemVer §11 puts a
# pre-release below its normal version. Nothing caught it because the assertions
# above compare strings, and a string comparison cannot see an ordering bug.
last=$(git -C "$ROOT" describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null | sed 's/^v//' || true)
if [ -n "$last" ]; then
  # A commit that is not the tag, so version.sh takes the development path.
  dev=$(cd "$ROOT" && git stash list >/dev/null 2>&1; ./scripts/version.sh)
  case "$dev" in
    *-dev.*)
      nextminor="${last%%.*}.$(( $(printf '%s' "$last" | cut -d. -f2) + 1 )).0"
      if python3 "$ROOT/tests/semver-order.py" "$last" "$dev" "$nextminor" >/dev/null 2>&1; then
        ok "a dev version sorts between $last and $nextminor ($dev)"
      else
        bad "dev version $dev does not sort between $last and $nextminor"
      fi ;;
    *)
      printf '  skip HEAD is exactly a release, so there is no dev version here\n' ;;
  esac
fi

# A --depth 1 clone fetches no tags, and bare `git describe --tags` exits 128
# there with "No names found" — which $(shell ...) swallows into an empty
# -X main.version= and a binary reporting nothing. ci.yml checks out shallow in
# the filters and pdf jobs, so a version script that dies there would break
# `make bin` across most of CI with no error surfaced.
t2="$t/shallow"
if git clone -q --depth 1 "file://$ROOT" "$t2" >/dev/null 2>&1; then
  # Copy the script in rather than relying on the clone to carry it: a clone
  # only has committed files, so otherwise this could not run until the script
  # was committed — and a test you must commit before you can run is a test
  # people stop running. What is under test is the script's behaviour where
  # there are no tags, not whether git cloned it.
  mkdir -p "$t2/scripts"
  cp "$ROOT/scripts/version.sh" "$t2/scripts/version.sh"
  chmod +x "$t2/scripts/version.sh"
  sv=$(
    cd "$t2" || exit 0
    ./scripts/version.sh 2>/dev/null || true
  )
  if [ -n "$sv" ]; then ok "version.sh survives a shallow clone with no tags ($sv)"
  else bad "version.sh printed nothing in a --depth 1 clone"; fi
else
  printf '  skip could not make a shallow clone\n'
fi

step "CLI: argument handling"
if "$SS" --nonsense >/dev/null 2>&1; then bad "bad option should not exit 0"
elif [ $? -eq 2 ]; then ok "bad option exits 2"; else bad "bad option wrong exit code"; fi
if "$SS" >/dev/null 2>&1; then bad "no input should not exit 0"
elif [ $? -eq 2 ]; then ok "no input exits 2"; else bad "no input wrong exit code"; fi
if "$SS" --help >/dev/null 2>&1; then ok "--help exits 0"; else bad "--help failed"; fi

rm -rf "$t"
printf '\n'
if [ "$fails" -eq 0 ]; then echo "ALL TESTS PASSED"; exit 0; else echo "$fails failure(s)"; exit 1; fi

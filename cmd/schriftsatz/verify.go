package main

import (
	"fmt"
	"os"
	"os/exec"
	"sort"
	"strings"
	"unicode"
)

// puaRange is Unicode's Basic Multilingual Plane Private Use Area. A codepoint
// in here is, by definition, meaningful only inside the font that produced it —
// which is exactly the defect this tool exists to catch. Doing the scan natively
// is one of the reasons the CLI is compiled: the shell version shelled out to
// python for it, and an earlier attempt at a shell bracket expression was
// written as literal bytes and passed by accident.
var puaRange = &unicode.RangeTable{
	R16: []unicode.Range16{{Lo: 0xE000, Hi: 0xF8FF, Stride: 1}},
}

func verify(pdf string) int {
	if _, err := os.Stat(pdf); err != nil {
		fmt.Fprintf(os.Stderr, "schriftsatz: not found: %s\n", pdf)
		return exitUsage
	}
	if _, err := exec.LookPath("pdftotext"); err != nil {
		fmt.Fprintln(os.Stderr, "schriftsatz: pdftotext (poppler) is required for verify")
		return exitMissing
	}

	poppler, err := exec.Command("pdftotext", pdf, "-").Output()
	if err != nil {
		fmt.Fprintf(os.Stderr, "schriftsatz: could not extract text from %s\n", pdf)
		return exitBuild
	}

	rc := exitOK

	if hits := findPUA(string(poppler)); len(hits) > 0 {
		fmt.Printf("FAIL  %s: text layer contains Private Use Area codepoints (%s)\n",
			pdf, strings.Join(hits, " "))
		fmt.Println("      the font mapped glyphs to codepoints that carry no meaning")
		fmt.Println("      outside it — see docs/inter-calt-tounicode.md")
		rc = exitFinding
	}

	// A second extractor is the sharper test: the two disagreeing is the
	// signature of this defect, because poppler discards PUA codepoints while
	// others pass them through.
	if second, ok := extractWithPypdf(pdf); ok {
		switch d := compare(string(poppler), second); d.kind {
		case agree:
			fmt.Println("ok    two extractors agree")
		case hyphenation:
			// Not a finding. XeLaTeX puts a real hyphen at a hyphenated line
			// break; pypdf reports it, poppler rejoins the word and drops it.
			// Both are defensible readings of a correctly encoded PDF, and the
			// only way to make them agree is to stop hyphenating.
			fmt.Printf("note  extractors differ by %d line-break hyphen(s) only\n", d.hyphens)
			fmt.Println("      that is hyphenation, not an encoding fault")
		default:
			fmt.Printf("FAIL  %s: extractors disagree on characters (poppler vs pypdf)\n", pdf)
			fmt.Println("      a text layer that depends on the reader is not a text layer")
			for _, line := range d.detail {
				fmt.Printf("      %s\n", line)
			}
			rc = exitFinding
		}
	} else {
		fmt.Println("note  only one extractor available; install uv for a cross-check")
	}

	reportStructure(pdf)

	if rc == exitOK {
		fmt.Printf("ok    %s: text layer is faithful\n", pdf)
	}
	return rc
}

// reportStructure says what a machine that is not a text extractor can get from
// this PDF: reading order, table structure, and any declared conformance level.
//
// Always a note, never a finding. An untagged PDF is the overwhelming norm and
// is not a defect in itself, so failing on it would make `verify` useless
// against the documents people actually bring to it. But a faithful text layer
// is only half of "machine readable", and the other half should be visible
// rather than assumed — which is the whole reason this reports at all.
func reportStructure(pdf string) {
	tagged, known := isTagged(pdf)
	missing, err := pdfDeclares(pdf, []string{"xpacket"})
	hasXMP := err == nil && len(missing) == 0

	switch {
	case !known:
		fmt.Println("note  pdfinfo not found; cannot tell whether this PDF is tagged")
		return
	case tagged:
		what := "tagged: a structure tree is present"
		if std := declaredStandard(pdf); std != "" {
			what += ", declaring " + std
		} else if hasXMP {
			what += ", with XMP metadata"
		}
		fmt.Printf("ok    %s\n", what)
	default:
		fmt.Println("note  not tagged: no structure tree, so reading order and table")
		fmt.Println("      structure are not available to a machine. Rebuild with")
		fmt.Println("      --tagged, or --pdf-standard for an archival conformance level.")
	}
}

// isTagged asks poppler. /MarkInfo and /StructTreeRoot live in the catalogue,
// which is inside a compressed object stream, so unlike the XMP markers they
// cannot be found by scanning bytes. The second return reports whether the
// question could be answered at all — pdfinfo is optional here, as pypdf is.
func isTagged(pdf string) (tagged, known bool) {
	if _, err := exec.LookPath("pdfinfo"); err != nil {
		return false, false
	}
	out, err := exec.Command("pdfinfo", pdf).Output()
	if err != nil {
		return false, false
	}
	for _, line := range strings.Split(string(out), "\n") {
		if strings.HasPrefix(line, "Tagged:") {
			return strings.Contains(line, "yes"), true
		}
	}
	return false, false
}

// declaredStandard reports the conformance level the file's XMP claims, reading
// exactly the markers the build-time check writes.
func declaredStandard(pdf string) string {
	for _, name := range pdfStandardNames() {
		std := pdfStandards[name]
		if missing, err := pdfDeclares(pdf, std.declares); err == nil && len(missing) == 0 {
			return std.label
		}
	}
	return ""
}

func findPUA(s string) []string {
	seen := map[rune]bool{}
	for _, r := range s {
		if unicode.Is(puaRange, r) {
			seen[r] = true
		}
	}
	out := make([]string, 0, len(seen))
	for r := range seen {
		out = append(out, fmt.Sprintf("U+%04X", r))
	}
	sort.Strings(out)
	return out
}

// extractWithPypdf uses uv to supply pypdf ephemerally, falling back to a system
// interpreter. It is optional by design: pypdf is the cross-check, not the tool.
func extractWithPypdf(pdf string) (string, bool) {
	const script = `import sys
from pypdf import PdfReader
print("".join(p.extract_text() for p in PdfReader(sys.argv[1]).pages))`

	if _, err := exec.LookPath("uv"); err == nil {
		cmd := exec.Command("uv", "run", "--quiet", "--with", "pypdf", "python", "-", pdf)
		cmd.Stdin = strings.NewReader(script)
		if out, err := cmd.Output(); err == nil {
			return string(out), true
		}
	}
	if _, err := exec.LookPath("python3"); err == nil {
		cmd := exec.Command("python3", "-", pdf)
		cmd.Stdin = strings.NewReader(script)
		if out, err := cmd.Output(); err == nil {
			return string(out), true
		}
	}
	return "", false
}

// What the cross-check found. Encoding is what is under test, so the comparison
// deliberately ignores everything that is a matter of layout interpretation.
type diffKind int

const (
	agree diffKind = iota
	hyphenation
	characters
)

type diff struct {
	kind    diffKind
	hyphens int
	detail  []string
}

// hyphen-like runes a typesetter may insert at a line break.
func isHyphen(r rune) bool {
	return r == '-' || r == '\u00ad' || r == '\u2010'
}

// compare tests whether two extractions carry the same CHARACTERS, as a
// multiset — not the same sequence.
//
// Comparing sequences looks stricter and is simply wrong here. The two
// extractors disagree about reading order in any multi-column layout: poppler
// walks a table column by column, pypdf row by row. Identical characters, and
// an earlier version of this function called that a failure, so `verify`
// rejected this project's own examples — every document with a table, which is
// the feature the project is mostly about.
//
// A multiset keeps the detection power that matters. The defect under test is a
// character being dropped or substituted: poppler discards Private Use Area
// codepoints while pypdf passes them through, and either changes the multiset.
// Order carries no information about encoding.
func compare(a, b string) diff {
	ca, cb := census(a), census(b)

	missing := map[rune]int{}
	for r, n := range ca {
		if d := n - cb[r]; d > 0 {
			missing[r] = d
		}
	}
	for r, n := range cb {
		if d := n - ca[r]; d > 0 {
			missing[r] += d
		}
	}
	if len(missing) == 0 {
		return diff{kind: agree}
	}

	onlyHyphens, count := true, 0
	for r, n := range missing {
		if isHyphen(r) {
			count += n
			continue
		}
		onlyHyphens = false
	}
	if onlyHyphens {
		return diff{kind: hyphenation, hyphens: count}
	}

	// Name the offending characters. "extractors disagree" with no detail sends
	// the reader to a diff of two extractions they have to produce themselves.
	runes := make([]rune, 0, len(missing))
	for r := range missing {
		runes = append(runes, r)
	}
	sort.Slice(runes, func(i, j int) bool { return runes[i] < runes[j] })

	detail := make([]string, 0, len(runes))
	for i, r := range runes {
		if i == 8 {
			detail = append(detail, fmt.Sprintf("… and %d more", len(runes)-8))
			break
		}
		where := "poppler"
		if cb[r] > ca[r] {
			where = "pypdf"
		}
		detail = append(detail, fmt.Sprintf("U+%04X %q ×%d, seen only by %s", r, r, missing[r], where))
	}
	return diff{kind: characters, detail: detail}
}

// census counts non-whitespace runes. pypdf reconstructs gaps from glyph
// positioning and inserts spaces poppler does not, which says nothing about
// whether a character is encoded correctly.
func census(s string) map[rune]int {
	m := map[rune]int{}
	for _, r := range s {
		if !unicode.IsSpace(r) {
			m[r]++
		}
	}
	return m
}

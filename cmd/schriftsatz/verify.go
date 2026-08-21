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
		if squash(string(poppler)) != squash(second) {
			fmt.Printf("FAIL  %s: extractors disagree (poppler vs pypdf)\n", pdf)
			fmt.Println("      a text layer that depends on the reader is not a text layer")
			rc = exitFinding
		} else {
			fmt.Println("ok    two extractors agree")
		}
	} else {
		fmt.Println("note  only one extractor available; install uv for a cross-check")
	}

	if rc == exitOK {
		fmt.Printf("ok    %s: text layer is faithful\n", pdf)
	}
	return rc
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

// squash removes all whitespace. pypdf reconstructs gaps from glyph positioning
// and inserts spaces poppler does not, which says nothing about whether a
// character is encoded correctly — and encoding is what is under test.
func squash(s string) string {
	return strings.Map(func(r rune) rune {
		if unicode.IsSpace(r) {
			return -1
		}
		return r
	}, s)
}

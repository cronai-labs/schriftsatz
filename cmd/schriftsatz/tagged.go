package main

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"sort"
	"strings"
)

// A tagged PDF carries a structure tree: /Document, /Sect, /Table, /TR, /TH.
// Without one a reader has glyphs and positions and nothing else — no reading
// order, no table structure, no way to tell a heading from a caption. That is
// the half of "machine readable" a faithful text layer does not give you.
//
// pandoc's templates/document-metadata.latex emits \DocumentMetadata from a
// `pdfstandard` metadata key. Its own comment says the feature requires
// LuaLaTeX; measured on TeX Live 2026 that is not true of the tagging path, and
// XeLaTeX produces a real structure tree through this project's whole pipeline —
// fontspec, the -calt fix, both Lua filters, longtable, fancyhdr and a minipage.

// pdfStandard is a conformance level this tool is willing to ask for.
type pdfStandard struct {
	id      string // as pandoc's pdfstandard.standards wants it
	version string // PDF header version the standard requires
	label   string // for messages
	// declares are XMP markers that must appear in the output. They are what
	// turns "we asked for it" into "the file says so".
	declares []string
}

// pdfStandards deliberately lists only what has been VALIDATED against veraPDF
// through this pipeline. Two obvious candidates are absent, and stay absent
// until they pass:
//
//	PDF/A-2b — fails rule 6.8-5. LaTeX's tagging support attaches
//	           latex-list-css.html and latex-align-css.html as associated files;
//	           PDF/A-3 permits arbitrary associated files, PDF/A-2 does not.
//	PDF/A-4  — fails 6.1.3-4, 6.1.3-5 and 6.9-3.
//
// Offering them would ship a file declaring a conformance it does not honour,
// which is worse than not offering them: a declaration is what a downstream
// system trusts instead of checking.
var pdfStandards = map[string]pdfStandard{
	// The header version is not cosmetic. \DocumentMetadata defaults to PDF 2.0,
	// and PDF/A-1/2/3 require a header of 1.7 or lower — rule 6.1.2-1, which was
	// the ONLY failure for A-3b before the version was pinned.
	"a-3b": {id: "A-3b", version: "1.7", label: "PDF/A-3b",
		declares: []string{"pdfaid:part>3", "pdfaid:conformance>B"}},
	// PDF/UA-2 is built on PDF 2.0. dc:title is not a marker of the standard
	// having been applied but a REQUIREMENT of it — veraPDF rule 8.11.1-1, the
	// only failure for a document whose front matter carries an empty title. It
	// is listed here so the caller is told at build time, by name, rather than
	// discovering it from a validator later or not at all.
	"ua-2": {id: "UA-2", version: "2.0", label: "PDF/UA-2",
		declares: []string{"pdfuaid:part>2", "dc:title"}},
}

// markerHints explain a missing marker in terms of what the author has to
// change. Without this a caller is handed an XMP path and left to work out that
// their document needs a title.
var markerHints = map[string]string{
	"dc:title": "PDF/UA requires a document title — set `title:` in the front matter",
}

// pdfStandardNames lists the accepted values, for help and error messages.
func pdfStandardNames() []string {
	out := make([]string, 0, len(pdfStandards))
	for k := range pdfStandards {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

// taggingMetadata renders the pdfstandard block pandoc's partial reads. A nil
// standard means tagging and XMP without asking for a conformance level, which
// leaves the header version to LaTeX (PDF 2.0).
func taggingMetadata(std *pdfStandard) string {
	var b strings.Builder
	b.WriteString("pdfstandard:\n")
	if std != nil {
		fmt.Fprintf(&b, "  version: '%s'\n", std.version)
		fmt.Fprintf(&b, "  standards: ['%s']\n", std.id)
	}
	b.WriteString("  tagging: true\n")
	return b.String()
}

// pdfDeclares reports which of the given XMP markers are absent from the file.
//
// A byte scan rather than a PDF parser, and it is sound rather than merely
// convenient: PDF/A requires the XMP packet to be unfiltered, and LaTeX writes
// it uncompressed for plain tagging too. Measured — `pdfaid:part` and `xpacket`
// are greppable in the raw bytes, while /MarkInfo and /StructTreeRoot are not,
// because the catalogue lives in a compressed object stream. So this covers
// exactly the claims that can be checked without poppler.
func pdfDeclares(path string, markers []string) ([]string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var missing []string
	for _, m := range markers {
		if !bytes.Contains(b, []byte(m)) {
			missing = append(missing, m)
		}
	}
	return missing, nil
}

// confirmTagging checks that the PDF just built carries what was asked for.
//
// The failure this exists for is quiet: pandoc lets a document's own front
// matter override a metadata file, so a file setting `pdfstandard` itself wins
// over the flag. Without this the caller is told nothing and ships a PDF that is
// not what they asked for. The pandoc version guard covers the other way this
// can go wrong — a pandoc too old to know the key at all.
func confirmTagging(out string, std *pdfStandard) error {
	markers := []string{"xpacket"}
	what := "a tagged PDF with XMP metadata"
	if std != nil {
		markers = append(markers, std.declares...)
		what = std.label
	}
	missing, err := pdfDeclares(out, markers)
	if err != nil {
		return fmt.Errorf("could not read back %s: %w", out, err)
	}
	if len(missing) > 0 {
		var b strings.Builder
		fmt.Fprintf(&b, "%s was requested but %s does not declare it", what, out)
		fmt.Fprintf(&b, "\n  missing: %s", strings.Join(missing, ", "))
		explained := false
		for _, m := range missing {
			if h, ok := markerHints[m]; ok {
				fmt.Fprintf(&b, "\n  %s", h)
				explained = true
			}
		}
		if !explained {
			b.WriteString("\n  a `pdfstandard:` key in the document's own front matter overrides the flag")
		}
		return errors.New(b.String())
	}
	return nil
}

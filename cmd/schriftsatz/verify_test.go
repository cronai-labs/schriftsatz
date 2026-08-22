package main

import "testing"

// The bug these guard against: `verify` compared the two extractions as
// SEQUENCES, so it rejected every document containing a table — including this
// project's own examples. poppler walks a table column by column and pypdf row
// by row, which changes the order and not one character.
//
// These cases are strings rather than PDFs on purpose. The real extractors need
// a font, a TeX distribution and pypdf, none of which are present everywhere,
// and the thing under test is the comparison rather than the extraction.
func TestCompare(t *testing.T) {
	// A PUA codepoint: poppler drops these, pypdf passes them through, and that
	// asymmetry is the defect the whole tool exists to catch.
	const pua = ""

	for _, tc := range []struct {
		name    string
		a, b    string
		want    diffKind
		hyphens int
	}{
		{
			name: "identical",
			a:    "Total 1.204,00", b: "Total 1.204,00",
			want: agree,
		},
		{
			name: "whitespace only — pypdf reconstructs gaps from glyph positions",
			a:    "DIN A4, EORI", b: "DIN A4 , EORI",
			want: agree,
		},
		{
			// The regression. Same cells, different reading order.
			name: "table read column-major vs row-major",
			a:    "Item\nReference\nAmount\nConsulting\nLicence\nINV-1\nINV-2\n1.204,00\n123,45",
			b:    "Item Reference Amount\nConsulting INV-1 1.204,00\nLicence INV-2 123,45",
			want: agree,
		},
		{
			name: "line-break hyphens: reported, not failed",
			a:    "compare the Overfull hbox lines",
			b:    "com-\npare the Overfull hbox lines",
			want: hyphenation, hyphens: 1,
		},
		{
			name: "two line-break hyphens",
			a:    "comparethirty",
			b:    "com-pare\nthirty-",
			want: hyphenation, hyphens: 2,
		},
		{
			// The control. If this ever returns anything but `characters`, the
			// check has stopped detecting the one thing it is for.
			name: "PUA codepoint seen by only one extractor",
			a:    "Materialaufwand 123,45",
			b:    "Materialaufwand " + pua + "123,45",
			want: characters,
		},
		{
			name: "a character is dropped entirely",
			a:    "Materialaufwand −123,45",
			b:    "Materialaufwand 123,45",
			want: characters,
		},
		{
			name: "a character is substituted",
			a:    "Größe", b: "Gr0ße",
			want: characters,
		},
		{
			// A multiset must still count repeats, or "aab" and "ab" match.
			name: "same character set, different counts",
			a:    "aab", b: "ab",
			want: characters,
		},
		{
			name: "hyphen difference alongside a real one is NOT excused",
			a:    "com-pare 123",
			b:    "compare " + pua + "123",
			want: characters,
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got := compare(tc.a, tc.b)
			if got.kind != tc.want {
				t.Errorf("kind = %v, want %v (detail: %v)", got.kind, tc.want, got.detail)
			}
			if tc.want == hyphenation && got.hyphens != tc.hyphens {
				t.Errorf("hyphens = %d, want %d", got.hyphens, tc.hyphens)
			}
			if tc.want == characters && len(got.detail) == 0 {
				t.Error("a character mismatch must name the characters; detail was empty")
			}
		})
	}
}

// compare must be symmetric: which extractor ran first cannot change the
// verdict. The counting is done in two passes over two maps, which is exactly
// the shape that silently loses one direction.
func TestCompareIsSymmetric(t *testing.T) {
	for _, tc := range []struct{ a, b string }{
		{"Materialaufwand −123,45", "Materialaufwand 123,45"},
		{"com-pare", "compare"},
		{"aab", "ab"},
		{"Item\nAmount", "Item Amount"},
	} {
		ab, ba := compare(tc.a, tc.b), compare(tc.b, tc.a)
		if ab.kind != ba.kind {
			t.Errorf("compare(%q,%q).kind = %v but reversed = %v", tc.a, tc.b, ab.kind, ba.kind)
		}
		if ab.hyphens != ba.hyphens {
			t.Errorf("compare(%q,%q).hyphens = %d but reversed = %d", tc.a, tc.b, ab.hyphens, ba.hyphens)
		}
	}
}

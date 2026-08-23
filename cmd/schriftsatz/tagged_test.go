package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// Every standard offered has to name the header version it requires. Getting
// this wrong is not cosmetic: PDF/A-3b failed veraPDF on rule 6.1.2-1 and
// nothing else, purely because \DocumentMetadata defaults to a PDF 2.0 header.
func TestPDFStandardsAreComplete(t *testing.T) {
	for name, std := range pdfStandards {
		if std.id == "" || std.version == "" || std.label == "" || len(std.declares) == 0 {
			t.Errorf("%s: incomplete definition %+v", name, std)
		}
		if strings.ToLower(name) != name {
			t.Errorf("%s: keys are matched after strings.ToLower, so must be lower case", name)
		}
	}
	for _, want := range []string{"a-3b", "ua-2"} {
		if _, ok := pdfStandards[want]; !ok {
			t.Errorf("%s is validated against veraPDF and must stay offered", want)
		}
	}
	// A-2b and A-4 do not pass through this pipeline. Offering either would ship
	// a declaration the file does not honour.
	for _, unwanted := range []string{"a-2b", "a-4"} {
		if _, ok := pdfStandards[unwanted]; ok {
			t.Errorf("%s is offered but has never passed veraPDF here", unwanted)
		}
	}
}

func TestTaggingMetadata(t *testing.T) {
	plain := taggingMetadata(nil)
	if !strings.Contains(plain, "tagging: true") {
		t.Errorf("tagging not requested: %q", plain)
	}
	if strings.Contains(plain, "standards:") || strings.Contains(plain, "version:") {
		t.Errorf("no standard was asked for, so none should be declared: %q", plain)
	}

	std := pdfStandards["a-3b"]
	got := taggingMetadata(&std)
	for _, want := range []string{"tagging: true", "standards: ['A-3b']", "version: '1.7'"} {
		if !strings.Contains(got, want) {
			t.Errorf("missing %q in:\n%s", want, got)
		}
	}
}

func TestConfirmTagging(t *testing.T) {
	dir := t.TempDir()
	write := func(name, content string) string {
		p := filepath.Join(dir, name)
		if err := os.WriteFile(p, []byte(content), 0o600); err != nil {
			t.Fatal(err)
		}
		return p
	}
	std := pdfStandards["a-3b"]

	// The declaration lives in an unfiltered XMP packet, so a byte scan sees it.
	good := write("good.pdf", "%PDF-1.7\n<?xpacket begin?><pdfaid:part>3</pdfaid:part>"+
		"<pdfaid:conformance>B</pdfaid:conformance>")
	if err := confirmTagging(good, &std); err != nil {
		t.Errorf("a conforming declaration was rejected: %v", err)
	}
	if err := confirmTagging(good, nil); err != nil {
		t.Errorf("plain tagging only needs the XMP packet: %v", err)
	}

	// The regression this guards: a document's own `pdfstandard:` key overrides
	// the flag, so the build succeeds and the file is not what was asked for.
	overridden := write("overridden.pdf", "%PDF-2.0\n<?xpacket begin?>no standard here")
	if err := confirmTagging(overridden, &std); err == nil {
		t.Error("a PDF declaring no standard was accepted as PDF/A-3b")
	} else if !strings.Contains(err.Error(), "pdfaid:part>3") {
		t.Errorf("the error should name what is missing, got: %v", err)
	}

	// Wrong conformance level is not close enough.
	wrong := write("wrong.pdf", "%PDF-1.7\n<?xpacket begin?><pdfaid:part>2</pdfaid:part>")
	if err := confirmTagging(wrong, &std); err == nil {
		t.Error("PDF/A-2 was accepted as PDF/A-3b")
	}

	// Not tagged at all.
	untagged := write("untagged.pdf", "%PDF-1.7\nnothing")
	if err := confirmTagging(untagged, nil); err == nil {
		t.Error("an untagged PDF was accepted")
	}

	if err := confirmTagging(filepath.Join(dir, "absent.pdf"), nil); err == nil {
		t.Error("a missing file should be an error, not a pass")
	}
}

// declaredStandard is what `verify` reports, so it must agree with what
// confirmTagging accepts — otherwise the tool contradicts itself about the same
// file.
func TestDeclaredStandardAgreesWithConfirm(t *testing.T) {
	dir := t.TempDir()
	for name, std := range pdfStandards {
		body := "%PDF\n<?xpacket begin?>" + strings.Join(std.declares, "")
		p := filepath.Join(dir, name+".pdf")
		if err := os.WriteFile(p, []byte(body), 0o600); err != nil {
			t.Fatal(err)
		}
		std := std
		if err := confirmTagging(p, &std); err != nil {
			t.Errorf("%s: confirmTagging rejected its own markers: %v", name, err)
		}
		if got := declaredStandard(p); got != std.label {
			t.Errorf("%s: verify reports %q, confirmTagging accepts %q", name, got, std.label)
		}
	}
}

package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestResolveStyle(t *testing.T) {
	dir := t.TempDir()
	onDisk := filepath.Join(dir, "mine.tex")
	if err := os.WriteFile(onDisk, []byte("% mine\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	// A working directory that happens to hold a styles/ tree, which is what
	// made `--style styles/formal.tex` look as though it already worked: from a
	// clone it resolves, from anywhere else it does not.
	local := filepath.Join(dir, "styles")
	if err := os.MkdirAll(local, 0o755); err != nil {
		t.Fatal(err)
	}
	shadow := filepath.Join(local, "formal.tex")
	if err := os.WriteFile(shadow, []byte("% local\n"), 0o600); err != nil {
		t.Fatal(err)
	}

	embedded := map[string]string{
		"styles/formal.tex":      "/materialised/styles/formal.tex",
		"styles/text-layer.tex":  "/materialised/styles/text-layer.tex",
		"filters/linebreaks.lua": "/materialised/filters/linebreaks.lua",
	}

	for _, tc := range []struct {
		name, in, want string
		ok             bool
	}{
		{name: "a path on disk is used as given", in: onDisk, want: onDisk, ok: true},
		{name: "an embedded name resolves", in: "styles/formal.tex", want: embedded["styles/formal.tex"], ok: true},
		{name: "a file on disk wins over the embedded copy", in: shadow, want: shadow, ok: true},
		// The regression this function exists for: not a path, not embedded.
		{name: "an unknown name is a usage error", in: "styles/nope.tex", ok: false},
		{name: "a bare stem is not accepted", in: "formal", ok: false},
		// A filter is not a header. Accepting it here would produce a xelatex
		// error about a file the caller never wrote.
		{name: "a filter is not a style", in: "filters/linebreaks.lua", ok: false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got, ok := resolveStyle(tc.in, embedded)
			if ok != tc.ok {
				t.Fatalf("resolveStyle(%q) ok = %v, want %v", tc.in, ok, tc.ok)
			}
			if ok && got != tc.want {
				t.Errorf("resolveStyle(%q) = %q, want %q", tc.in, got, tc.want)
			}
		})
	}
}

package assets

import (
	"os"
	"path/filepath"
	"testing"
)

// The //go:embed directive cannot reach outside its own package directory, so
// the filters and styles exist twice: canonically at the repository root,
// where a reader clones or copies them and where the docs point, and again
// here to be embedded.
//
// Two copies of anything drift. This test is the thing that stops it, and it is
// the reason `make build` regenerates the embedded copies rather than trusting
// anyone to remember.
func TestEmbeddedAssetsMatchRepositoryRoot(t *testing.T) {
	root := filepath.Join("..", "..")
	for _, name := range List() {
		name := name
		t.Run(name, func(t *testing.T) {
			embedded, err := Read(name)
			if err != nil {
				t.Fatalf("read embedded %s: %v", name, err)
			}
			canonical, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(name)))
			if err != nil {
				t.Fatalf("read canonical %s: %v — the embedded copy has no counterpart "+
					"at the repository root", name, err)
			}
			if string(embedded) != string(canonical) {
				t.Errorf("%s: embedded copy differs from the repository root.\n"+
					"Run `make build` to resync, and commit the result.", name)
			}
		})
	}
}

// A caller that asks for a default style must get one that exists, or the
// binary ships a broken default and nobody notices until a user runs it.
func TestDefaultStylesAndFiltersAreEmbedded(t *testing.T) {
	for _, n := range append(append([]string{}, DefaultStyles...), Filters...) {
		if _, err := Read(n); err != nil {
			t.Errorf("declared asset %s is not embedded: %v", n, err)
		}
	}
}

func TestMaterialiseWritesEveryAsset(t *testing.T) {
	dir := t.TempDir()
	paths, err := Materialise(dir)
	if err != nil {
		t.Fatalf("Materialise: %v", err)
	}
	if len(paths) != len(List()) {
		t.Fatalf("materialised %d assets, embedded %d", len(paths), len(List()))
	}
	for name, p := range paths {
		if _, err := os.Stat(p); err != nil {
			t.Errorf("%s: materialised path does not exist: %v", name, err)
		}
	}
}

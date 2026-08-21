// Package assets carries the Lua filters and LaTeX fragments inside the binary.
//
// This is the whole reason the tool is a compiled binary rather than a script.
// The shell version located its assets relative to its own path, which works
// from a clone and breaks the moment a package manager installs the executable
// somewhere else — Homebrew puts it in the Cellar, where the sibling
// directories do not exist. Embedding removes the problem instead of working
// around it with a wrapper.
package assets

import (
	"embed"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
)

//go:embed filters/*.lua styles/*.tex
var files embed.FS

// Names of the assets, so callers do not hardcode paths.
const (
	FilterTableWidths = "filters/table-widths.lua"
	FilterLinebreaks  = "filters/linebreaks.lua"
	StyleTextLayer    = "styles/text-layer.tex"
	StyleLineBreaking = "styles/linebreaking.tex"
	StyleFormal       = "styles/formal.tex"
)

// DefaultStyles are included unless the caller opts out. formal.tex is not among
// them: it adds page furniture that a plain document should not get by default.
var DefaultStyles = []string{StyleTextLayer, StyleLineBreaking}

// Filters always run, in this order. linebreaks must come after table-widths so
// the width measurement sees undivided tokens.
var Filters = []string{FilterTableWidths, FilterLinebreaks}

// Materialise writes every embedded asset into dir, preserving layout, and
// returns a map from asset name to its absolute path.
//
// pandoc takes filesystem paths for --lua-filter and -H, so the assets have to
// exist as real files for the length of one run.
func Materialise(dir string) (map[string]string, error) {
	out := map[string]string{}
	err := fs.WalkDir(files, ".", func(p string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return err
		}
		b, err := files.ReadFile(p)
		if err != nil {
			return fmt.Errorf("read embedded %s: %w", p, err)
		}
		dst := filepath.Join(dir, filepath.FromSlash(p))
		if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
			return err
		}
		if err := os.WriteFile(dst, b, 0o644); err != nil {
			return fmt.Errorf("write %s: %w", dst, err)
		}
		out[p] = dst
		return nil
	})
	return out, err
}

// Read returns one embedded asset, for callers that want to print it.
func Read(name string) ([]byte, error) { return files.ReadFile(name) }

// List returns every embedded asset name, sorted by fs.WalkDir order.
func List() []string {
	var names []string
	_ = fs.WalkDir(files, ".", func(p string, d fs.DirEntry, err error) error {
		if err == nil && !d.IsDir() {
			names = append(names, p)
		}
		return err
	})
	return names
}

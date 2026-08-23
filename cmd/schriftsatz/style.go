package main

import (
	"os"
	"path/filepath"
	"strings"
)

// resolveStyle maps one --style value to a path pandoc can read.
//
// A file on disk wins, so a caller can always point at their own header — or at
// a modified copy of a shipped one sitting in the working directory. Failing
// that, the value is looked up among the embedded styles under exactly the name
// --list-assets prints.
//
// That second branch is the whole point. Before it, the styles the binary
// carries could not be named at all: --style took a filesystem path, so
// formal.tex was reachable only by writing it out with --print-asset first, and
// examples/formal-document.md — the one document that demonstrates it — could
// not be built by anyone who had not cloned the repository.
//
// embedded maps asset name to materialised path, as returned by
// assets.Materialise.
func resolveStyle(v string, embedded map[string]string) (string, bool) {
	if _, err := os.Stat(v); err == nil {
		return v, true
	}
	// Styles only. A Lua filter is not a LaTeX header, and accepting
	// `--style filters/linebreaks.lua` here would defer the complaint to
	// xelatex, which reports it as a syntax error in a file the caller did not
	// write.
	name := filepath.ToSlash(v)
	if !strings.HasPrefix(name, "styles/") {
		return "", false
	}
	p, ok := embedded[name]
	return p, ok
}

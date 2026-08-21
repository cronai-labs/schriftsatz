// Command schriftsatz renders Markdown to a print-ready PDF via pandoc and
// XeLaTeX, and verifies that the result's text layer is faithful to the source.
package main

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/cronai-labs/schriftsatz/internal/assets"
)

// version is injected at build time: -ldflags "-X main.version=1.2.3".
// It is deliberately not a constant in the source, so there is no second place
// for the version to drift out of step with the tag.
var version = "dev"

// Exit codes, kept identical to the shell implementation this replaces so that
// anything scripting the tool keeps working.
const (
	exitOK = 0
	// exitFinding is for `verify` reporting a problem with the PDF it was
	// given. That is a finding, not a failure of this tool, so it is neither a
	// usage error nor a build error.
	exitFinding = 1
	exitUsage   = 2
	exitMissing = 3
	exitBuild   = 4
)

const usage = `schriftsatz — Markdown to print-ready PDF via pandoc and XeLaTeX

USAGE
  schriftsatz [options] <input.md>     build a PDF
  schriftsatz verify <file.pdf>        check that the PDF's text layer is faithful

OPTIONS
  -o, --output FILE    Output path (default: <input>.pdf, next to the input)
      --style FILE     LaTeX header to include (repeatable).
                       Default: the embedded text-layer and line-breaking styles
      --no-default-style  Use only the --style files you pass
      --lang CODE      Document language, e.g. de-DE, en-GB (default: en-GB)
      --capacity N     Characters per table line for the width filter
                       (default 80; lower for narrower type areas)
      --keep-tex       Also write the intermediate .tex next to the output
      --print-asset N  Write one embedded asset to stdout (see --list-assets)
      --list-assets    List the embedded filters and styles
  -h, --help           This message
      --version        Print version

ENVIRONMENT
  SCHRIFTSATZ_STYLE    Default style file, overrides the built-in default

EXIT CODES
  0 ok · 1 verify found a problem · 2 bad arguments
  3 missing dependency · 4 build failure
`

func main() { os.Exit(run(os.Args[1:])) }

func run(argv []string) int {
	if len(argv) > 0 && argv[0] == "verify" {
		if len(argv) != 2 {
			fmt.Fprintln(os.Stderr, "usage: schriftsatz verify <file.pdf>")
			return exitUsage
		}
		return verify(argv[1])
	}

	var (
		in, out, capacity string
		lang              = "en-GB"
		styles            []string
		noDefault, keepTex bool
	)

	for i := 0; i < len(argv); i++ {
		a := argv[i]
		next := func(flag string) (string, bool) {
			if i+1 >= len(argv) {
				fmt.Fprintf(os.Stderr, "schriftsatz: %s needs a value\n", flag)
				return "", false
			}
			i++
			return argv[i], true
		}
		switch a {
		case "-h", "--help":
			fmt.Print(usage)
			return exitOK
		case "--version":
			fmt.Println("schriftsatz", version)
			return exitOK
		case "--list-assets":
			for _, n := range assets.List() {
				fmt.Println(n)
			}
			return exitOK
		case "--print-asset":
			n, ok := next(a)
			if !ok {
				return exitUsage
			}
			b, err := assets.Read(n)
			if err != nil {
				fmt.Fprintf(os.Stderr, "schriftsatz: no such embedded asset: %s\n", n)
				return exitUsage
			}
			os.Stdout.Write(b)
			return exitOK
		case "-o", "--output":
			v, ok := next(a)
			if !ok {
				return exitUsage
			}
			out = v
		case "--style":
			v, ok := next(a)
			if !ok {
				return exitUsage
			}
			styles = append(styles, v)
		case "--lang":
			v, ok := next(a)
			if !ok {
				return exitUsage
			}
			lang = v
		case "--capacity":
			v, ok := next(a)
			if !ok {
				return exitUsage
			}
			if _, err := strconv.Atoi(v); err != nil {
				fmt.Fprintf(os.Stderr, "schriftsatz: --capacity needs a number, got %q\n", v)
				return exitUsage
			}
			capacity = v
		case "--no-default-style":
			noDefault = true
		case "--keep-tex":
			keepTex = true
		case "--":
			if i+1 >= len(argv) {
				fmt.Fprintln(os.Stderr, "schriftsatz: no input file after --")
				return exitUsage
			}
			in = argv[i+1]
			i = len(argv)
		default:
			if strings.HasPrefix(a, "-") {
				fmt.Fprintf(os.Stderr, "schriftsatz: unknown option: %s\n", a)
				return exitUsage
			}
			if in != "" {
				fmt.Fprintln(os.Stderr, "schriftsatz: more than one input file given")
				return exitUsage
			}
			in = a
		}
	}

	if in == "" {
		fmt.Fprint(os.Stderr, usage)
		return exitUsage
	}
	if _, err := os.Stat(in); err != nil {
		fmt.Fprintf(os.Stderr, "schriftsatz: input not found: %s\n", in)
		return exitUsage
	}
	if code := preflight(); code != exitOK {
		return code
	}
	return build(in, out, lang, capacity, styles, noDefault, keepTex)
}

// preflight fails early with an actionable message rather than letting pandoc
// produce something obscure about a missing pdf-engine.
func preflight() int {
	missing := false
	if _, err := exec.LookPath("pandoc"); err != nil {
		fmt.Fprintln(os.Stderr, "schriftsatz: pandoc not found")
		fmt.Fprintln(os.Stderr, "  macOS:  brew install pandoc")
		fmt.Fprintln(os.Stderr, "  Debian: sudo apt install pandoc")
		missing = true
	}
	if _, err := exec.LookPath("xelatex"); err != nil {
		fmt.Fprintln(os.Stderr, "schriftsatz: xelatex not found")
		fmt.Fprintln(os.Stderr, "  macOS:  brew install texlive")
		fmt.Fprintln(os.Stderr, "  Debian: sudo apt install texlive-xetex texlive-latex-recommended")
		missing = true
	}
	if missing {
		return exitMissing
	}
	if err := checkPandocVersion(); err != nil {
		fmt.Fprintf(os.Stderr, "schriftsatz: %v\n", err)
		return exitMissing
	}
	return exitOK
}

// minPandoc is 2.17, not the 2.10 that introduced the Table AST: the Lua
// bindings for Row.cells and Cell.col_span only arrived in 2.17, and the width
// filter dies with "attempt to index a nil value" on anything older.
var minPandoc = [2]int{2, 17}

func checkPandocVersion() error {
	outB, err := exec.Command("pandoc", "--version").Output()
	if err != nil {
		return fmt.Errorf("could not run pandoc: %w", err)
	}
	fields := strings.Fields(strings.SplitN(string(outB), "\n", 2)[0])
	if len(fields) < 2 {
		return errors.New("could not parse pandoc --version")
	}
	got := fields[1]
	parts := strings.Split(got, ".")
	if len(parts) < 2 {
		return fmt.Errorf("could not parse pandoc version %q", got)
	}
	maj, _ := strconv.Atoi(parts[0])
	min, _ := strconv.Atoi(parts[1])
	if maj < minPandoc[0] || (maj == minPandoc[0] && min < minPandoc[1]) {
		return fmt.Errorf("pandoc >= %d.%d required for the table-width filter (found %s)",
			minPandoc[0], minPandoc[1], got)
	}
	return nil
}

func build(in, out, lang, capacity string, styles []string, noDefault, keepTex bool) int {
	tmp, err := os.MkdirTemp("", "schriftsatz-")
	if err != nil {
		fmt.Fprintf(os.Stderr, "schriftsatz: %v\n", err)
		return exitBuild
	}
	defer os.RemoveAll(tmp)

	paths, err := assets.Materialise(tmp)
	if err != nil {
		fmt.Fprintf(os.Stderr, "schriftsatz: %v\n", err)
		return exitBuild
	}

	// Output goes next to the INPUT, never into the tool's own directory.
	if out == "" {
		out = strings.TrimSuffix(in, filepath.Ext(in)) + ".pdf"
	}
	if d := filepath.Dir(out); d != "" {
		if err := os.MkdirAll(d, 0o755); err != nil {
			fmt.Fprintf(os.Stderr, "schriftsatz: %v\n", err)
			return exitBuild
		}
	}

	if len(styles) == 0 && !noDefault {
		if env := os.Getenv("SCHRIFTSATZ_STYLE"); env != "" {
			styles = []string{env}
		} else {
			for _, s := range assets.DefaultStyles {
				styles = append(styles, paths[s])
			}
		}
	}
	for _, s := range styles {
		if _, err := os.Stat(s); err != nil {
			fmt.Fprintf(os.Stderr, "schriftsatz: style file not found: %s\n", s)
			return exitUsage
		}
	}

	args := []string{in, "--pdf-engine=xelatex"}
	for _, f := range assets.Filters {
		args = append(args, "--lua-filter", paths[f])
	}
	args = append(args,
		"-V", "lang="+lang,
		"-V", "fontsize=11pt",
		"-V", "documentclass=article",
		"-V", "indent=false",
	)
	for _, s := range styles {
		args = append(args, "-H", s)
	}
	if capacity != "" {
		args = append(args, "-M", "table-capacity="+capacity)
	}
	args = append(args, "-o", out)

	cmd := exec.Command("pandoc", args...)
	cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
	if err := cmd.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "schriftsatz: pandoc/xelatex failed building %s\n", in)
		return exitBuild
	}

	if keepTex {
		texOut := strings.TrimSuffix(out, filepath.Ext(out)) + ".tex"
		targs := []string{in, "-s", "-t", "latex"}
		for _, f := range assets.Filters {
			targs = append(targs, "--lua-filter", paths[f])
		}
		targs = append(targs, "-V", "lang="+lang)
		for _, s := range styles {
			targs = append(targs, "-H", s)
		}
		targs = append(targs, "-o", texOut)
		_ = exec.Command("pandoc", targs...).Run()
	}

	fmt.Println(out)
	return exitOK
}

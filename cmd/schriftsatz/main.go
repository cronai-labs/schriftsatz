// Command schriftsatz renders Markdown to a print-ready PDF via pandoc and
// XeLaTeX, and verifies that the result's text layer is faithful to the source.
package main

import (
	"bytes"
	"errors"
	"fmt"
	"io"
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
      --style STYLE    LaTeX header to include (repeatable). Either a path to
                       your own file, or an embedded style under the name
                       --list-assets prints, e.g. styles/formal.tex
                       Default: the embedded text-layer and line-breaking styles
      --no-default-style  Drop the defaults; use only the --style files you pass
      --lang CODE      Document language, e.g. de-DE, en-GB. Overrides the
                       document's own lang: field. Without it the document
                       decides, falling back to en-GB.
      --capacity N     Characters per table line for the width filter
                       (default 80; lower for narrower type areas)
      --tagged         Produce a TAGGED PDF: structure tree plus XMP metadata,
                       so the document is machine readable and not merely
                       extractable. Needs pandoc >= 3.9
      --pdf-standard S Conformance level, implies --tagged: a-3b | ua-2
                       (validated against veraPDF; others are not offered)
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
		// Empty means "not given on the command line", which is a different
		// thing from en-GB: the default belongs in documentDefaults, where the
		// document can override it, while this flag has to beat the document.
		lang               string
		styles             []string
		stdName            string
		noDefault, keepTex bool
		tagged             bool
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
			// A short write to stdout is a real failure — a truncated asset
			// piped into a file looks like a complete one. Reporting exitOK
			// after it would be a lie the caller cannot detect.
			if _, err := os.Stdout.Write(b); err != nil {
				fmt.Fprintf(os.Stderr, "schriftsatz: writing %s: %v\n", n, err)
				return exitBuild
			}
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
		case "--tagged":
			tagged = true
		case "--pdf-standard":
			v, ok := next(a)
			if !ok {
				return exitUsage
			}
			stdName = v
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
	var standard *pdfStandard
	if stdName != "" {
		found, ok := pdfStandards[strings.ToLower(stdName)]
		if !ok {
			fmt.Fprintf(os.Stderr, "schriftsatz: unknown PDF standard: %s\n", stdName)
			fmt.Fprintf(os.Stderr, "  validated standards: %s\n", strings.Join(pdfStandardNames(), ", "))
			fmt.Fprintln(os.Stderr, "  others are deliberately not offered; see docs/decisions/tagged-pdf.md")
			return exitUsage
		}
		standard = &found
		tagged = true
	}

	if code := preflight(); code != exitOK {
		return code
	}
	if tagged {
		if code := checkTaggingSupport(); code != exitOK {
			return code
		}
	}
	return build(buildOptions{
		in: in, out: out, lang: lang, capacity: capacity,
		styles: styles, noDefault: noDefault, keepTex: keepTex,
		tagged: tagged, standard: standard,
	})
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

// taggingKeyUnknown is what an older LaTeX kernel says when \DocumentMetadata
// does not know the `tagging` key. Matched to turn a message about an internal
// key path into one about the reader's TeX distribution.
//
// A version check would be the obvious alternative and is worse: there is no
// cheap, portable way to ask a TeX distribution for its kernel date, and the
// answer would still have to be mapped to which keys exist. The engine's own
// complaint is the authority.
const taggingKeyUnknown = "document/metadata/tagging"

// minPandocTagging is 3.9. templates/document-metadata.latex — the partial that
// emits \DocumentMetadata — first ships there (released 2026-02-04,
// jgm/pandoc#11407). Older pandoc does not know the `pdfstandard` key and
// ignores it in silence, producing an ordinary untagged PDF from a command that
// asked for a tagged one. That is the failure mode this project refuses
// everywhere else, so it is an error and not a downgrade.
var minPandocTagging = [2]int{3, 9}

// pandocVersion returns the running pandoc's major and minor version, plus the
// string it reported so a caller can name it.
func pandocVersion() ([2]int, string, error) {
	outB, err := exec.Command("pandoc", "--version").Output()
	if err != nil {
		return [2]int{}, "", fmt.Errorf("could not run pandoc: %w", err)
	}
	fields := strings.Fields(strings.SplitN(string(outB), "\n", 2)[0])
	if len(fields) < 2 {
		return [2]int{}, "", errors.New("could not parse pandoc --version")
	}
	got := fields[1]
	parts := strings.Split(got, ".")
	if len(parts) < 2 {
		return [2]int{}, got, fmt.Errorf("could not parse pandoc version %q", got)
	}
	maj, _ := strconv.Atoi(parts[0])
	min, _ := strconv.Atoi(parts[1])
	return [2]int{maj, min}, got, nil
}

func atLeast(v, want [2]int) bool {
	return v[0] > want[0] || (v[0] == want[0] && v[1] >= want[1])
}

func checkPandocVersion() error {
	v, got, err := pandocVersion()
	if err != nil {
		return err
	}
	if !atLeast(v, minPandoc) {
		return fmt.Errorf("pandoc >= %d.%d required for the table-width filter (found %s)",
			minPandoc[0], minPandoc[1], got)
	}
	return nil
}

// checkTaggingSupport refuses rather than quietly producing an untagged PDF.
func checkTaggingSupport() int {
	v, got, err := pandocVersion()
	if err != nil {
		fmt.Fprintf(os.Stderr, "schriftsatz: %v\n", err)
		return exitMissing
	}
	if !atLeast(v, minPandocTagging) {
		fmt.Fprintf(os.Stderr,
			"schriftsatz: --tagged needs pandoc >= %d.%d, found %s\n",
			minPandocTagging[0], minPandocTagging[1], got)
		fmt.Fprintln(os.Stderr,
			"  the template partial that emits \\DocumentMetadata first ships in 3.9.")
		fmt.Fprintln(os.Stderr,
			"  older pandoc ignores the request in silence, so this refuses rather")
		fmt.Fprintln(os.Stderr,
			"  than handing you an untagged PDF that looks like what you asked for.")
		return exitMissing
	}
	return exitOK
}

// buildOptions is a struct rather than nine positional parameters, which is
// what this had grown to.
type buildOptions struct {
	in, out, lang, capacity string
	styles                  []string
	noDefault, keepTex      bool
	tagged                  bool
	standard                *pdfStandard // nil means tagging without a conformance level
}

func build(opt buildOptions) int {
	in, out, lang, capacity := opt.in, opt.out, opt.lang, opt.capacity
	styles, noDefault, keepTex := opt.styles, opt.noDefault, opt.keepTex
	tmp, err := os.MkdirTemp("", "schriftsatz-")
	if err != nil {
		fmt.Fprintf(os.Stderr, "schriftsatz: %v\n", err)
		return exitBuild
	}
	// Explicitly discarded: this is best-effort cleanup of a temporary
	// directory, and there is nothing useful to do if it fails.
	defer func() { _ = os.RemoveAll(tmp) }()

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

	// The defaults are ADDED TO by --style, not replaced by it, and they come
	// first so a caller's own header can override them.
	//
	// They used to be dropped the moment any --style was given. That made
	// --no-default-style redundant — its help text already promised "use only
	// the --style files you pass" — and it meant `--style styles/formal.tex`
	// built without text-layer.tex, so the documented way to add a footer
	// silently reintroduced the calt defect this project exists to prevent.
	//
	// Resolved straight from paths rather than through resolveStyle: a working
	// directory that happens to contain a styles/ tree must not change what the
	// default set means.
	if !noDefault {
		var defaults []string
		if env := os.Getenv("SCHRIFTSATZ_STYLE"); env != "" {
			defaults = []string{env}
		} else {
			for _, s := range assets.DefaultStyles {
				defaults = append(defaults, paths[s])
			}
		}
		styles = append(defaults, styles...)
	}
	resolved := make([]string, 0, len(styles))
	for _, s := range styles {
		p, ok := resolveStyle(s, paths)
		if !ok {
			fmt.Fprintf(os.Stderr, "schriftsatz: style not found: %s\n", s)
			fmt.Fprintln(os.Stderr, "  no file at that path, and not an embedded style. Embedded:")
			for _, n := range assets.Styles() {
				fmt.Fprintf(os.Stderr, "    %s\n", n)
			}
			return exitUsage
		}
		resolved = append(resolved, p)
	}
	styles = resolved

	// Recover the document's own header-includes, and give it the last word.
	//
	// --include-in-header REPLACES that template variable rather than appending
	// to it, and the default styles mean -H is always passed — so a document's
	// own header-includes silently never reached the preamble. The build
	// succeeded, the package went unloaded, and a command the document defined
	// was undefined where the body used it, which reads as an error in the
	// document rather than in the tool.
	//
	// Only when something is actually being passed with -H. With none, the
	// variable is intact and adding the file too would render it twice.
	if len(styles) > 0 {
		p, err := documentHeaderIncludes(in, tmp, paths[assets.TemplateHeaderIncludes])
		if err != nil {
			fmt.Fprintf(os.Stderr, "schriftsatz: %v\n", err)
			return exitBuild
		}
		if p != "" {
			// Last, so the document overrides the tool's styles rather than the
			// other way round — the same precedence as documentDefaults.
			styles = append(styles, p)
		}
	}

	defaults := filepath.Join(tmp, "defaults.yaml")
	if err := os.WriteFile(defaults, []byte(documentDefaults), 0o600); err != nil {
		fmt.Fprintf(os.Stderr, "schriftsatz: %v\n", err)
		return exitBuild
	}
	metaFiles := []string{defaults}

	if opt.tagged {
		// A second metadata file rather than a line in the defaults: this one is
		// asked for on the command line, so it is written separately and the
		// output is checked afterwards. See confirmTagging.
		p := filepath.Join(tmp, "tagging.yaml")
		if err := os.WriteFile(p, []byte(taggingMetadata(opt.standard)), 0o600); err != nil {
			fmt.Fprintf(os.Stderr, "schriftsatz: %v\n", err)
			return exitBuild
		}
		metaFiles = append(metaFiles, p)
	}

	var filters []string
	for _, f := range assets.Filters {
		filters = append(filters, paths[f])
	}
	common := pandocArgs(in, metaFiles, lang, capacity, filters, styles)

	args := append(common, "--pdf-engine=xelatex", "-o", out)
	cmd := exec.Command("pandoc", args...)
	// Tee stderr when tagging: the LaTeX kernel can be too old for
	// \DocumentMetadata even when pandoc is new enough, and the error it emits
	// names an internal key path that tells a caller nothing. Keep streaming it
	// so nothing is hidden, and read it back to add the sentence that helps.
	var log bytes.Buffer
	if opt.tagged {
		cmd.Stderr = io.MultiWriter(os.Stderr, &log)
	} else {
		cmd.Stderr = os.Stderr
	}
	cmd.Stdout = os.Stdout
	if err := cmd.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "schriftsatz: pandoc/xelatex failed building %s\n", in)
		if opt.tagged && strings.Contains(log.String(), taggingKeyUnknown) {
			fmt.Fprintln(os.Stderr, "  the LaTeX kernel is too old for tagged output.")
			fmt.Fprintln(os.Stderr, "  \\DocumentMetadata gained the `tagging` key in the 2024-11-01")
			fmt.Fprintln(os.Stderr, "  release; Debian 13 and Ubuntu 24.04 ship an older TeX Live.")
			fmt.Fprintln(os.Stderr, "  Update your TeX distribution, or drop --tagged/--pdf-standard.")
		}
		return exitBuild
	}

	// Read back what was actually produced. pandoc lets a document's own front
	// matter override a metadata file, so a file carrying its own `pdfstandard:`
	// key silently wins over the flag — and a caller told nothing would ship a
	// PDF that is not what they asked for.
	if opt.tagged {
		if err := confirmTagging(out, opt.standard); err != nil {
			fmt.Fprintf(os.Stderr, "schriftsatz: %v\n", err)
			return exitBuild
		}
	}

	if keepTex {
		texOut := strings.TrimSuffix(out, filepath.Ext(out)) + ".tex"
		targs := append(pandocArgs(in, metaFiles, lang, capacity, filters, styles),
			"-s", "-t", "latex", "-o", texOut)
		if err := exec.Command("pandoc", targs...).Run(); err != nil {
			fmt.Fprintf(os.Stderr, "schriftsatz: could not write %s: %v\n", texOut, err)
			return exitBuild
		}
		fmt.Println(texOut)
	}

	fmt.Println(out)
	return exitOK
}

// documentDefaults are applied only where the document is silent about them.
//
// They travel by --metadata-file rather than -V, and that is the entire point:
// pandoc lets a document's own front matter override a metadata file, while -V
// overrides the document. As -V, a file declaring `lang: de-DE` was typeset with
// British hyphenation and shipped a catalogue /Lang of en-GB, and a file asking
// for `documentclass: scrartcl` got article regardless.
//
// papersize is a4 because everything in this project already assumes it:
// filters/table-widths.lua states its capacity was measured for A4 at 11pt, and
// styles/formal.tex sets a4paper. Without it pandoc's own default applies and
// the tool shipped US Letter, so adding page furniture silently changed the
// paper size of a document.
//
// indent is a real YAML boolean here, and has to be. As `-V indent=false` it was
// the non-empty STRING "false", which pandoc's template language treats as true
// — so the setting that says it disables first-line indentation was switching it
// on, and every document this tool has built carried it.
const documentDefaults = `lang: en-GB
fontsize: 11pt
documentclass: article
papersize: a4
indent: false
`

// pandocArgs assembles the invocation shared by the PDF build and the --keep-tex
// dump.
//
// One builder rather than two lists written out separately, because they drifted:
// the --keep-tex list never carried -M table-capacity, so the .tex it produced
// ignored --capacity and was therefore not the source of the PDF sitting next to
// it. A debugging aid that hands you the wrong source is worse than none.
func pandocArgs(in string, metaFiles []string, lang, capacity string, filters, styles []string) []string {
	args := []string{in}
	for _, m := range metaFiles {
		args = append(args, "--metadata-file", m)
	}
	for _, f := range filters {
		args = append(args, "--lua-filter", f)
	}
	if lang != "" {
		// -M, not the defaults file. An explicit --lang has to beat the
		// document, while the default has to lose to it; those are opposite
		// precedences and pandoc spells them with different flags.
		args = append(args, "-M", "lang="+lang)
	}
	for _, s := range styles {
		args = append(args, "-H", s)
	}
	if capacity != "" {
		args = append(args, "-M", "table-capacity="+capacity)
	}
	return args
}

// documentHeaderIncludes renders the document's own header-includes to a file
// and returns its path, or "" if the document declares none.
//
// A second pandoc pass, deliberately with no -H, using a template that renders
// that variable and nothing else. It costs no TeX run. The LaTeX writer does
// the escaping, so nothing here has to quote anything by hand.
//
// A caution for anyone testing this by hand: pandoc's latex_macros extension
// expands \newcommand definitions itself, so a macro defined in header-includes
// appears to work even when the preamble never received it. Test with
// \usepackage or \typeout instead.
func documentHeaderIncludes(in, tmp, template string) (string, error) {
	out, err := exec.Command("pandoc", in, "-t", "latex", "--template", template).Output()
	if err != nil {
		return "", fmt.Errorf("could not read header-includes from %s: %w", in, err)
	}
	if len(strings.TrimSpace(string(out))) == 0 {
		return "", nil
	}
	p := filepath.Join(tmp, "document-header-includes.tex")
	if err := os.WriteFile(p, out, 0o600); err != nil {
		return "", err
	}
	return p, nil
}

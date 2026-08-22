// Command mockgh is a stand-in GitHub API for rehearsing a release locally.
//
// Why this exists: three separate bugs shipped to real users because nothing
// could exercise the publish path without publishing. `goreleaser --snapshot`
// skips publishing entirely, so it never computes a release body — and an empty
// body was exactly the bug, twice. The only assertion that would have caught it
// is one made against what goreleaser actually SENDS.
//
// goreleaser's `github_urls.api` is templated and passed to go-github's
// WithEnterpriseURLs, so pointing it at this process makes a complete release
// run happen against a socket instead of github.com. Every request is recorded;
// tests/release-dryrun.sh then asserts on the recordings.
//
// This is a test double, not a GitHub implementation. It returns the minimum
// each endpoint needs to let goreleaser proceed.
package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync/atomic"
)

var (
	// go-github appends /api/v3/ for enterprise hosts, so match on the tail of
	// the path rather than anchoring at the root.
	reReleaseByTag = regexp.MustCompile(`/repos/([^/]+)/([^/]+)/releases/tags/(.+)$`)
	reReleases     = regexp.MustCompile(`/repos/([^/]+)/([^/]+)/releases$`)
	reReleaseByID  = regexp.MustCompile(`/repos/([^/]+)/([^/]+)/releases/(\d+)$`)
	reAssets       = regexp.MustCompile(`/repos/([^/]+)/([^/]+)/releases/(\d+)/assets$`)
	reContents     = regexp.MustCompile(`/repos/([^/]+)/([^/]+)/contents/(.+)$`)
	reRepo         = regexp.MustCompile(`/repos/([^/]+)/([^/]+)$`)
	reRateLimit    = regexp.MustCompile(`/rate_limit$`)
)

type server struct {
	out       string
	scenario  string
	baseURL   string
	assets    atomic.Int64
	unhandled atomic.Int64
}

func main() {
	addr := flag.String("addr", "127.0.0.1:8099", "listen address")
	out := flag.String("out", "", "directory to record requests into")
	scenario := flag.String("scenario", "fresh", `"fresh" (404 on the tag: create path) or "existing-release" (200: update path)`)
	flag.Parse()
	if *out == "" {
		log.Fatal("mockgh: -out is required")
	}
	if err := os.MkdirAll(*out, 0o755); err != nil {
		log.Fatalf("mockgh: %v", err)
	}

	s := &server{out: *out, scenario: *scenario, baseURL: "http://" + *addr}
	ln, err := listen(*addr)
	if err != nil {
		log.Fatalf("mockgh: %v", err)
	}
	// The orchestrating script waits for this line rather than sleeping, so a
	// slow start cannot turn into a flaky "connection refused".
	fmt.Println("mockgh: listening on", *addr)
	_ = os.Stdout.Sync()
	log.Fatal(http.Serve(ln, s))
}

func (s *server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	body, _ := io.ReadAll(r.Body)
	s.record("requests.log", []byte(r.Method+" "+r.URL.Path+"\n"), true)

	switch {
	case reRateLimit.MatchString(r.URL.Path):
		s.json(w, 200, map[string]any{
			"resources": map[string]any{
				"core": map[string]any{"limit": 5000, "remaining": 5000, "reset": 0},
			},
		})

	// Two scenarios, chosen with -scenario.
	//
	// "fresh" (the default) answers 404, which forces the CREATE path — what a
	// first publish does.
	//
	// "existing-release" answers 200 with a deliberately WRONG body, which
	// forces the UPDATE path — what a RESUMED run meets after its own earlier
	// attempt already published this tag. Tags here are immutable, so that
	// re-run is the only recovery there is, and release.mode is what decides
	// whether it repairs the body or preserves the broken one. Untested, that
	// setting is the shape of bug #23.
	case reReleaseByTag.MatchString(r.URL.Path):
		if s.scenario == "existing-release" {
			rel := s.release(1)
			rel["body"] = "stale body from the attempt that failed\n"
			s.json(w, 200, rel)
			return
		}
		s.json(w, 404, map[string]any{"message": "Not Found"})

	case r.Method == http.MethodPost && reReleases.MatchString(r.URL.Path):
		// The payload the whole rehearsal exists to inspect.
		s.record("release-create.json", body, false)
		s.json(w, 201, s.release(1))

	case r.Method == http.MethodPatch && reReleaseByID.MatchString(r.URL.Path):
		// A resumed run sends TWO patches: the update that carries the body,
		// then the publish that only flips draft. Recording both to one file
		// truncated the first with the second and made the body look empty, so
		// keep an ordered log as well as the last one.
		s.record("release-update.json", body, false)
		s.record("release-updates.jsonl", append(compact(body), '\n'), true)
		s.json(w, 200, s.release(1))

	case reAssets.MatchString(r.URL.Path):
		if r.Method == http.MethodGet {
			s.json(w, 200, []any{})
			return
		}
		name := r.URL.Query().Get("name")
		s.record("assets.log", []byte(name+"\n"), true)
		s.json(w, 201, map[string]any{"id": s.assets.Add(1), "name": name})

	case reContents.MatchString(r.URL.Path):
		// The Homebrew cask lands here.
		m := reContents.FindStringSubmatch(r.URL.Path)
		if r.Method == http.MethodGet {
			s.json(w, 404, map[string]any{"message": "Not Found"})
			return
		}
		s.record("contents-"+filepath.Base(m[3])+".json", body, false)
		s.record("contents.log", []byte(m[1]+"/"+m[2]+" "+m[3]+"\n"), true)
		s.json(w, 201, map[string]any{"content": map[string]any{"path": m[3]}})

	case reRepo.MatchString(r.URL.Path):
		m := reRepo.FindStringSubmatch(r.URL.Path)
		s.json(w, 200, map[string]any{
			"name": m[2], "full_name": m[1] + "/" + m[2], "default_branch": "main",
			"owner": map[string]any{"login": m[1]},
		})

	default:
		// Loud rather than silent: an endpoint answered by accident would make
		// the rehearsal diverge from the real thing without anyone noticing.
		s.unhandled.Add(1)
		s.record("unhandled.log", []byte(r.Method+" "+r.URL.Path+"\n"), true)
		log.Printf("mockgh: UNHANDLED %s %s", r.Method, r.URL.Path)
		s.json(w, 200, map[string]any{})
	}
}

// compact renders JSON on a single line so one request is one line of the log.
func compact(body []byte) []byte {
	var buf bytes.Buffer
	if err := json.Compact(&buf, body); err != nil {
		return bytes.TrimSpace(body)
	}
	return buf.Bytes()
}

func (s *server) release(id int64) map[string]any {
	return map[string]any{
		"id": id, "tag_name": "dryrun", "draft": false,
		"html_url":   s.baseURL + "/release/" + fmt.Sprint(id),
		"upload_url": s.baseURL + "/repos/o/r/releases/" + fmt.Sprint(id) + "/assets{?name,label}",
	}
}

func (s *server) json(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func (s *server) record(name string, data []byte, appendMode bool) {
	p := filepath.Join(s.out, name)
	flags := os.O_CREATE | os.O_WRONLY
	if appendMode {
		flags |= os.O_APPEND
	} else {
		flags |= os.O_TRUNC
	}
	f, err := os.OpenFile(p, flags, 0o644) //nolint:gosec
	if err != nil {
		log.Printf("mockgh: record %s: %v", name, err)
		return
	}
	defer func() { _ = f.Close() }()
	if _, err := f.Write(data); err != nil {
		log.Printf("mockgh: write %s: %v", name, err)
	}
	if !appendMode && !strings.HasSuffix(string(data), "\n") {
		_, _ = f.Write([]byte("\n"))
	}
}

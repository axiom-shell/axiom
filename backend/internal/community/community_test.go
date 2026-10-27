package community

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

const body = `{"a": 1}`

func bodySum() string { s := sha256.Sum256([]byte(body)); return hex.EncodeToString(s[:]) }

// server serves /a.json, a redirect to it, one to a file: URL, and a
// file claiming to be too large; anything else is a 404.
func server(t *testing.T) *httptest.Server {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/a.json":
			_, _ = w.Write([]byte(body))
		case "/moved":
			http.Redirect(w, r, "/a.json", http.StatusFound)
		case "/to-file":
			http.Redirect(w, r, "file:///etc/hostname", http.StatusFound)
		case "/huge":
			w.Header().Set("Content-Length", strconv.Itoa(maxSize+1))
			_, _ = w.Write([]byte(strings.Repeat("x", 1024)))
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(srv.Close)
	return srv
}

func TestFetch(t *testing.T) {
	t.Parallel()
	srv := server(t)
	for _, tc := range []struct {
		name   string
		cached string // already at dest
		url    string
		sha    string
		dest   string // relative to the root; "" for "a.json"
		err    string // "" for a file that lands holding body
	}{
		{name: "checked", url: "/a.json", sha: bodySum(), dest: "sub/a.json"},
		{name: "upper-case hash", url: "/a.json", sha: strings.ToUpper(bodySum())},
		{name: "unchecked", url: "/a.json"},
		{name: "redirect", url: "/moved", sha: bodySum()},
		{name: "a cached file isn't fetched again", cached: body, url: "/missing", sha: bodySum()},
		{name: "a stale cached file is replaced", cached: "old", url: "/a.json", sha: bodySum()},
		{name: "unchecked is always fetched", cached: "old", url: "/a.json"},
		{name: "bad checksum", url: "/a.json", sha: strings.Repeat("0", 64), err: "checksum mismatch"},
		{name: "missing", url: "/missing", err: "HTTP 404"},
		{name: "too large", url: "/huge", err: "larger than 20 MB"},
		{name: "only http", url: "file:///etc/hostname", err: "only http(s) is fetched"},
		{name: "redirect off http", url: "/to-file", err: "isn't http(s)"},
		{name: "outside the roots", url: "/a.json", dest: "../elsewhere.json", err: "not a folder"},
		{name: "the root itself", url: "/a.json", dest: ".", err: "not a folder"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			dir := t.TempDir()
			root := filepath.Join(dir, "root")
			rel := tc.dest
			if rel == "" {
				rel = "a.json"
			}
			dest := filepath.Join(root, rel)
			if tc.cached != "" {
				if err := os.MkdirAll(root, 0o755); err != nil {
					t.Fatal(err)
				}
				if err := os.WriteFile(dest, []byte(tc.cached), 0o644); err != nil {
					t.Fatal(err)
				}
			}
			u := tc.url
			if strings.HasPrefix(u, "/") {
				u = srv.URL + u
			}
			got := New(Options{Roots: []string{root}}).Fetch(context.Background(), []File{{URL: u, Dest: dest, SHA256: tc.sha}})
			if len(got) != 1 || got[0].Dest != dest {
				t.Fatalf("got %+v", got)
			}
			data, readErr := os.ReadFile(dest)
			if tc.err == "" {
				want := body
				if tc.cached != "" && tc.url == "/missing" {
					want = tc.cached
				}
				if got[0].Error != "" || string(data) != want {
					t.Errorf("error %q, file %q", got[0].Error, data)
				}
				return
			}
			if !strings.Contains(got[0].Error, tc.err) {
				t.Errorf("error %q, want %q", got[0].Error, tc.err)
			}
			if tc.cached == "" && readErr == nil {
				t.Errorf("a failed download left %q", data)
			}
			// Nothing half-written beside it
			if entries, _ := os.ReadDir(filepath.Dir(dest)); len(entries) > 0 && tc.cached == "" {
				t.Errorf("left %d files", len(entries))
			}
		})
	}
}

func TestFetchKeepsOrder(t *testing.T) {
	t.Parallel()
	srv := server(t)
	root := t.TempDir()
	var files []File
	for i := range 10 {
		path := "/a.json"
		if i%3 == 0 {
			path = "/missing"
		}
		files = append(files, File{URL: srv.URL + path, Dest: filepath.Join(root, strconv.Itoa(i))})
	}
	for i, r := range New(Options{Roots: []string{root}}).Fetch(context.Background(), files) {
		if r.Dest != files[i].Dest || (r.Error != "") != (i%3 == 0) {
			t.Errorf("%d: %+v", i, r)
		}
	}
}

func TestWithin(t *testing.T) {
	t.Parallel()
	roots := []string{"/c/community/", "/d/themes"}
	for _, tc := range []struct {
		dest string
		want bool
	}{
		{"/c/community/index.json", true},
		{"/c/community/thumbs/a.webp", true},
		{"/d/themes/x.json", true},
		{"/c/community", false},
		{"/c/community/../config.json", false},
		{"/c/communityx/a", false},
		{"c/community/a", false},
		{"/elsewhere", false},
	} {
		if got := Within(roots, tc.dest); got != tc.want {
			t.Errorf("%q: %v", tc.dest, got)
		}
	}
}

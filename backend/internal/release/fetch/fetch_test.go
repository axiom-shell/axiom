package fetch

import (
	"context"
	"crypto/sha256"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// serve publishes files[tag/name] under a test server, with each tag's
// SHA256SUMS listing them (or sums[tag], when given) and returns its url.
func serve(t *testing.T, files map[string]string, sums map[string]string) string {
	t.Helper()
	listing := map[string]string{}
	for path, data := range files {
		tag, name, _ := strings.Cut(path, "/")
		listing[tag] += fmt.Sprintf("%x  %s\n", sha256.Sum256([]byte(data)), name)
	}
	for tag, s := range sums {
		listing[tag] = s
	}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		path := strings.TrimPrefix(r.URL.Path, "/")
		tag, name, _ := strings.Cut(path, "/")
		if name == "SHA256SUMS" {
			if s, ok := listing[tag]; ok {
				fmt.Fprint(w, s)
				return
			}
		}
		if data, ok := files[path]; ok {
			fmt.Fprint(w, data)
			return
		}
		http.NotFound(w, r)
	}))
	t.Cleanup(srv.Close)
	return srv.URL
}

func TestBinary(t *testing.T) {
	t.Parallel()
	base := serve(t, map[string]string{
		"v1.0.0/axiom-linux-amd64": "bin",
		"v1.0.1/axiom-linux-amd64": "bin",
	}, map[string]string{"v1.0.1": strings.Repeat("0", 64) + "  axiom-linux-amd64\n"})
	f := New(Options{Base: base})
	for _, tc := range []struct {
		name, tag, arch string
		want            error
	}{
		{"published", "v1.0.0", "amd64", nil},
		{"no such release", "v9.9.9", "amd64", ErrMissing},
		{"no binary for the machine", "v1.0.0", "arm64", ErrMissing},
		{"an architecture never built", "v1.0.0", "riscv64", ErrMissing},
		{"a tag leaving its folder", "../x", "amd64", ErrMissing},
		{"a sum that doesn't match", "v1.0.1", "amd64", ErrMismatch},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			data, err := f.Binary(context.Background(), tc.tag, tc.arch)
			if !errors.Is(err, tc.want) || (tc.want == nil) != (string(data) == "bin") {
				t.Fatalf("Binary = %q, %v; want %v", data, err, tc.want)
			}
		})
	}
}

func TestEdgeCommit(t *testing.T) {
	t.Parallel()
	commit := "0123456789abcdef0123456789abcdef01234567"
	for _, tc := range []struct {
		name  string
		files map[string]string
		sums  map[string]string
		want  error
	}{
		{"published", map[string]string{"edge/COMMIT": commit + "\n"}, nil, nil},
		{"no edge build", nil, nil, ErrMissing},
		{"not listed", map[string]string{"edge/COMMIT": commit + "\n"}, map[string]string{"edge": ""}, ErrMismatch},
		{"not a commit", map[string]string{"edge/COMMIT": "main\n"}, nil, ErrMismatch},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			got, err := New(Options{Base: serve(t, tc.files, tc.sums)}).EdgeCommit(context.Background())
			if !errors.Is(err, tc.want) || (tc.want == nil) != (got == commit) {
				t.Fatalf("EdgeCommit = %q, %v; want %v", got, err, tc.want)
			}
		})
	}
}

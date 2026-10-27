package daemon

import (
	"context"
	"crypto/sha256"
	"fmt"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/release"
	"github.com/axiom-shell/axiom/backend/internal/release/fetch"
)

func TestReplaceInstalled(t *testing.T) {
	t.Parallel()
	builds := `printf '#!/bin/sh\necho axiom\n' > "$3"; chmod +x "$3"`
	const released = "#!/bin/sh\necho axiom released\n"
	head := strings.Repeat("1", 40)
	asset, ok := release.Asset(runtime.GOARCH)
	if !ok {
		t.Skip("no official binary for", runtime.GOARCH)
	}
	replaceable := func(t *testing.T) string { return writeBin(t, t.TempDir(), 0o755) }
	for _, tc := range []struct {
		name, channel string
		published     map[string]string // the releases' files (tag/name), SHA256SUMS made from them
		sums          string            // edge's SHA256SUMS line for its binary instead, when set
		build         string            // the fake go's build ("" for no go)
		installed     func(t *testing.T) string
		source        string // where the new binary came from ("" none)
		failed        bool
	}{
		{"a release's", "tags", map[string]string{"v1.1.0/" + asset: released}, "", builds, replaceable, "release", false},
		{"no release binary: built", "tags", nil, "", builds, replaceable, "built", false},
		{"main's newest build of head", "main", map[string]string{"edge/" + asset: released, "edge/COMMIT": head + "\n"}, "", builds, replaceable, "edge", false},
		{"main's newest build of another commit: built", "main",
			map[string]string{"edge/" + asset: released, "edge/COMMIT": strings.Repeat("2", 40) + "\n"}, "", builds, replaceable, "built", false},
		{"a build its sums don't match: built", "main", map[string]string{"edge/" + asset: released, "edge/COMMIT": head + "\n"},
			strings.Repeat("0", 64) + "  " + asset + "\n", builds, replaceable, "built", false},
		{"none installed", "tags", map[string]string{"v1.1.0/" + asset: released}, "", builds, func(t *testing.T) string { return "" }, "", false},
		{"read-only (a package's)", "tags", map[string]string{"v1.1.0/" + asset: released}, "", builds, func(t *testing.T) string { return writeBin(t, t.TempDir(), 0o555) }, "", false},
		{"no build and doesn't compile", "tags", nil, "", `echo 'main.go:1: syntax error' >&2; exit 1`, replaceable, "", true},
		{"no build and no go", "tags", nil, "", "", replaceable, "", true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			if tc.name == "read-only (a package's)" && os.Geteuid() == 0 {
				t.Skip("root writes anywhere")
			}
			tree := t.TempDir()
			os.MkdirAll(filepath.Join(tree, "backend"), 0o755)
			goBin := filepath.Join(t.TempDir(), "no-go")
			if tc.build != "" {
				goBin = fakeGo(t, tc.build)
			}
			base := serveReleases(t, tc.published, tc.sums)
			d := &Daemon{opts: Options{Tree: tree, Go: goBin, Log: slog.New(slog.DiscardHandler)}}
			d.installed = tc.installed(t)
			before, _ := os.ReadFile(d.installed)
			rebuilt, source, reason := d.replaceInstalled(context.Background(), fetch.New(fetch.Options{Base: base}), tc.channel, "v1.1.0", head)
			if rebuilt != (tc.source != "") || source != tc.source || (reason != "") != tc.failed {
				t.Fatalf("rebuilt %v from %q, reason %q", rebuilt, source, reason)
			}
			after, _ := os.ReadFile(d.installed)
			if (string(before) != string(after)) != rebuilt || (tc.source == "release" || tc.source == "edge") != (string(after) == released) {
				t.Errorf("binary now %q", after)
			}
		})
	}
}

// serveReleases serves files (tag/name), each tag's SHA256SUMS listing
// them; binary, when set, is edge's line for its binary instead.
func serveReleases(t *testing.T, files map[string]string, binary string) string {
	t.Helper()
	asset, _ := release.Asset(runtime.GOARCH)
	listing := map[string]string{}
	for path, data := range files {
		tag, name, _ := strings.Cut(path, "/")
		line := fmt.Sprintf("%x  %s\n", sha256.Sum256([]byte(data)), name)
		if tag == release.Edge && name == asset && binary != "" {
			line = binary
		}
		listing[tag] += line
	}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		path := strings.TrimPrefix(r.URL.Path, "/")
		if tag, name, _ := strings.Cut(path, "/"); name == "SHA256SUMS" && listing[tag] != "" {
			fmt.Fprint(w, listing[tag])
		} else if data, ok := files[path]; ok {
			fmt.Fprint(w, data)
		} else {
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(srv.Close)
	return srv.URL
}

// writeBin is an installed binary in dir, with mode.
func writeBin(t *testing.T, dir string, mode os.FileMode) string {
	t.Helper()
	path := filepath.Join(dir, "axiom")
	if err := os.WriteFile(path, []byte("#!/bin/sh\necho old\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(path, mode); err != nil {
		t.Fatal(err)
	}
	return path
}

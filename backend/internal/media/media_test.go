package media

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

func TestArt(t *testing.T) {
	t.Parallel()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/art.jpg":
			w.Write([]byte("jpeg"))
		case "/empty.jpg":
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(srv.Close)
	src := filepath.Join(t.TempDir(), "cover.png")
	if err := os.WriteFile(src, []byte("png"), 0o644); err != nil {
		t.Fatal(err)
	}
	cases := []struct {
		name, url, file string
		want            string // the file's content after, "" for none
		kind            axerr.Kind
	}{
		{"http", srv.URL + "/art.jpg", "a.jpg", "jpeg", ""},
		{"file", "file://" + src, "b.jpg", "png", ""},
		{"not found", srv.URL + "/gone.jpg", "c.jpg", "", axerr.Unavailable},
		{"empty", srv.URL + "/empty.jpg", "d.jpg", "", axerr.Unavailable},
		{"scheme", "data:image/png;base64,AAAA", "e.jpg", "", axerr.BadRequest},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			dir := filepath.Join(t.TempDir(), "axiom", "media-art")
			path := filepath.Join(dir, tc.file)
			err := Art(context.Background(), Options{Dir: dir, Client: srv.Client()}, tc.url, path)
			if axerr.KindOf(err) != tc.kind && !(tc.kind == "" && err == nil) {
				t.Fatalf("err %v, want kind %q", err, tc.kind)
			}
			got, _ := os.ReadFile(path)
			if string(got) != tc.want {
				t.Errorf("file %q, want %q", got, tc.want)
			}
			if _, err := os.Stat(path + ".part"); err == nil {
				t.Errorf("left a .part behind")
			}
		})
	}
}

func TestArtKeepsWhatIsThere(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	path := filepath.Join(dir, "a.jpg")
	os.WriteFile(path, []byte("cached"), 0o600)
	// An unreachable URL: nothing is fetched for art already there
	if err := Art(context.Background(), Options{Dir: dir}, "http://127.0.0.1:1/x", path); err != nil {
		t.Fatal(err)
	}
	if got, _ := os.ReadFile(path); string(got) != "cached" {
		t.Errorf("got %q", got)
	}
}

// Art is written only directly in its folder
func TestArtRefusesOtherPaths(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	for _, path := range []string{
		filepath.Join(filepath.Dir(dir), "elsewhere.jpg"),
		filepath.Join(dir, "..", "up.jpg"),
		filepath.Join(dir, "sub", "deeper.jpg"),
		dir,
		"relative.jpg",
	} {
		if err := Art(context.Background(), Options{Dir: dir}, "file:///etc/hostname", path); axerr.KindOf(err) != axerr.Refused {
			t.Errorf("%s: %v, want refused", path, err)
		}
	}
	if err := Art(context.Background(), Options{}, "file:///etc/hostname", "/tmp/x.jpg"); axerr.KindOf(err) != axerr.Refused {
		t.Errorf("no folder: %v, want refused", err)
	}
}

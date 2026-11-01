package files

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

func TestList(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	for _, name := range []string{"b.PNG", "a.jpg", "notes.txt", ".hidden.png", "sub/c.png", "sub/deep/d.jpeg", ".cache/e.png", "empty/x.txt"} {
		path := filepath.Join(dir, name)
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, nil, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.Symlink(filepath.Join(dir, "a.jpg"), filepath.Join(dir, "link.jpg")); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Join(dir, "sub"), filepath.Join(dir, "loop")); err != nil {
		t.Fatal(err)
	}
	abs := func(names ...string) []string {
		out := []string{}
		for _, n := range names {
			out = append(out, filepath.Join(dir, n))
		}
		return out
	}
	cases := []struct {
		name      string
		recursive bool
		want      Listing
	}{
		{"the folder alone", false, Listing{Files: abs("a.jpg", "b.PNG", "link.jpg"), Folders: []string{}}},
		{"and every folder under it", true, Listing{Files: abs("a.jpg", "b.PNG", "link.jpg", "sub/c.png", "sub/deep/d.jpeg"), Folders: []string{"sub", "sub/deep"}}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			got, err := List(dir, []string{"jpg", "jpeg", ".png"}, c.recursive)
			if err != nil {
				t.Fatal(err)
			}
			if !reflect.DeepEqual(got, c.want) {
				t.Errorf("got %+v, want %+v", got, c.want)
			}
		})
	}
	// A folder reached through a link lists under the link's path
	link := filepath.Join(t.TempDir(), "wallpapers")
	if err := os.Symlink(dir, link); err != nil {
		t.Fatal(err)
	}
	if got, err := List(link, []string{"jpg"}, false); err != nil || !reflect.DeepEqual(got.Files, []string{filepath.Join(link, "a.jpg"), filepath.Join(link, "link.jpg")}) {
		t.Errorf("a linked folder: %+v, %v", got, err)
	}
	if _, err := List(filepath.Join(dir, "missing"), nil, false); axerr.KindOf(err) != axerr.NotFound {
		t.Errorf("a missing folder: %v", err)
	}
	if _, err := List("relative", nil, false); axerr.KindOf(err) != axerr.BadRequest {
		t.Errorf("a relative path: %v", err)
	}
}

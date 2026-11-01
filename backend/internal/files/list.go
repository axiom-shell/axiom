package files

import (
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

// Listing is a folder's files of some kinds (file.list): their absolute
// paths, and the folders under it holding any, as paths inside it ("a",
// "a/b"), each sorted by name, case aside.
type Listing struct {
	Files   []string `json:"files"`
	Folders []string `json:"folders"`
	// More than MaxListed files: the rest were left out
	Truncated bool `json:"truncated"`
}

// MaxListed bounds a listing (a home folder picked by mistake).
const MaxListed = 20000

// List is dir's regular files (links to them too) whose extension is one
// of exts (without the dot, any case), and with recursive those of every
// folder under it, hidden ones and links to folders left out. A missing
// dir is NotFound.
func List(dir string, exts []string, recursive bool) (Listing, error) {
	root, err := clean(dir)
	if err != nil {
		return Listing{}, err
	}
	info, err := os.Stat(root)
	if err != nil || !info.IsDir() {
		return Listing{}, axerr.New(axerr.NotFound, "%s isn't a folder", root)
	}
	want := map[string]bool{}
	for _, e := range exts {
		want["."+strings.ToLower(strings.TrimPrefix(e, "."))] = true
	}
	out := Listing{Files: []string{}, Folders: []string{}}
	folders := map[string]bool{}
	walk := func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			// An unreadable folder inside is skipped, not the whole list
			if path == root {
				return err
			}
			return fs.SkipDir
		}
		name := d.Name()
		if d.IsDir() {
			if path == root {
				return nil
			}
			if !recursive || strings.HasPrefix(name, ".") {
				return fs.SkipDir
			}
			return nil
		}
		if strings.HasPrefix(name, ".") || !want[strings.ToLower(filepath.Ext(name))] {
			return nil
		}
		// A link counts when it leads to a regular file
		if d.Type()&fs.ModeSymlink != 0 {
			if target, err := os.Stat(path); err != nil || !target.Mode().IsRegular() {
				return nil
			}
		} else if !d.Type().IsRegular() {
			return nil
		}
		if len(out.Files) >= MaxListed {
			out.Truncated = true
			return fs.SkipAll
		}
		out.Files = append(out.Files, path)
		if rel, err := filepath.Rel(root, filepath.Dir(path)); err == nil && rel != "." {
			for p := rel; p != "." && p != "/"; p = filepath.Dir(p) {
				folders[p] = true
			}
		}
		return nil
	}
	if err := filepath.WalkDir(root, walk); err != nil {
		return Listing{}, axerr.Wrap(axerr.Unavailable, err, "listing %s", root)
	}
	for f := range folders {
		out.Folders = append(out.Folders, f)
	}
	byName := func(list []string) {
		sort.SliceStable(list, func(i, j int) bool {
			a, b := strings.ToLower(list[i]), strings.ToLower(list[j])
			if a != b {
				return a < b
			}
			return list[i] < list[j]
		})
	}
	byName(out.Files)
	byName(out.Folders)
	return out, nil
}

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

// ListOptions widen a listing.
type ListOptions struct {
	// Every folder under dir too
	Recursive bool
	// Every folder listed in Folders, empty ones and links to folders too
	// (the notes browser), not only those holding files
	Folders bool
	// Hidden files and folders too
	Hidden bool
}

// List is dir's regular files (links to them too) whose extension is one
// of exts (without the dot, any case), and with o.Recursive those of every
// folder under it, hidden ones and links to folders left out unless o
// says (dir itself may be a link: its files are listed under dir). A
// missing dir is NotFound.
func List(dir string, exts []string, o ListOptions) (Listing, error) {
	root, err := clean(dir)
	if err != nil {
		return Listing{}, err
	}
	info, err := os.Stat(root)
	if err != nil || !info.IsDir() {
		return Listing{}, axerr.New(axerr.NotFound, "%s isn't a folder", root)
	}
	// WalkDir doesn't follow a link it starts at: walk where it leads
	walked, err := filepath.EvalSymlinks(root)
	if err != nil {
		return Listing{}, axerr.Wrap(axerr.Unavailable, err, "listing %s", root)
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
			if path == walked {
				return err
			}
			return fs.SkipDir
		}
		name := d.Name()
		if path == walked || (!o.Hidden && strings.HasPrefix(name, ".")) {
			if d.IsDir() && path != walked {
				return fs.SkipDir
			}
			return nil
		}
		if d.IsDir() {
			if o.Folders {
				folders[strings.TrimPrefix(path, walked+"/")] = true
			}
			if !o.Recursive {
				return fs.SkipDir
			}
			return nil
		}
		// A link counts when it leads to a regular file (or a folder, with
		// o.Folders)
		if d.Type()&fs.ModeSymlink != 0 {
			target, err := os.Stat(path)
			if err == nil && target.IsDir() && o.Folders {
				folders[strings.TrimPrefix(path, walked+"/")] = true
			}
			if err != nil || !target.Mode().IsRegular() {
				return nil
			}
		} else if !d.Type().IsRegular() {
			return nil
		}
		if !want[strings.ToLower(filepath.Ext(name))] {
			return nil
		}
		if len(out.Files) >= MaxListed {
			out.Truncated = true
			return fs.SkipAll
		}
		rel, err := filepath.Rel(walked, path)
		if err != nil {
			return nil
		}
		out.Files = append(out.Files, filepath.Join(root, rel))
		for p := filepath.Dir(rel); p != "." && p != "/"; p = filepath.Dir(p) {
			folders[p] = true
		}
		return nil
	}
	if err := filepath.WalkDir(walked, walk); err != nil {
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

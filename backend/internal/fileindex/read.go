package fileindex

import (
	"os"
	"path/filepath"
	"slices"
	"strings"
	"unicode/utf8"

	"github.com/axiom-shell/axiom/backend/internal/filesearch"
	"golang.org/x/sys/unix"
)

// alwaysSkipped are never crawled, whatever the roots: kernel and runtime
// folders that aren't files
var alwaysSkipped = []string{"/proc", "/sys", "/dev", "/run"}

// filter decides what goes in the index: the entries under a root, not
// excluded, not hidden (unless asked), not in a skipped folder, and on
// their root's own device.
type filter struct {
	roots    []string // clean and absolute, longest first
	excludes filesearch.Excludes
	skip     []string
	hidden   bool
	devs     map[string]uint64 // a root's device, as its last read found it
}

func newFilter(roots, excludes, skip []string, hidden bool) *filter {
	f := &filter{excludes: filesearch.ParseExcludes(excludes), hidden: hidden, devs: map[string]uint64{}}
	f.roots = slices.Clone(roots)
	slices.SortFunc(f.roots, func(a, b string) int { return len(b) - len(a) })
	f.skip = append(slices.Clone(alwaysSkipped), skip...)
	return f
}

// within: path is dir or below it
func within(path, dir string) bool {
	if dir == "/" {
		return strings.HasPrefix(path, "/")
	}
	return path == dir || strings.HasPrefix(path, dir) && path[len(dir)] == '/'
}

// rootOf is the root path is under ("" for none).
func (f *filter) rootOf(path string) string {
	for _, r := range f.roots {
		if within(path, r) {
			return r
		}
	}
	return ""
}

// keep says whether the entry at path (under root) goes in the index.
// A name that isn't UTF-8 never does: JSON would carry another path.
func (f *filter) keep(root, path, name string) bool {
	if !f.hidden && name[0] == '.' || !utf8.ValidString(name) {
		return false
	}
	for _, s := range f.skip {
		if within(path, s) && !within(root, s) {
			return false
		}
	}
	rel := strings.TrimPrefix(strings.TrimPrefix(path, root), "/")
	return !f.excludes.Skip(rel)
}

// rootDev is a root's device (ok false when it's no folder).
func (f *filter) rootDev(root string) (uint64, bool) {
	if d, ok := f.devs[root]; ok {
		return d, true
	}
	var st unix.Stat_t
	if unix.Stat(root, &st) != nil || st.Mode&unix.S_IFMT != unix.S_IFDIR {
		return 0, false
	}
	f.devs[root] = st.Dev
	return st.Dev, true
}

// rootOn says whether root is on device dev, as it is now: the device
// kept for it is stale when a disk was mounted again at the root and a
// folder below is read first.
func (f *filter) rootOn(root string, dev uint64) bool {
	delete(f.devs, root)
	d, ok := f.rootDev(root)
	return ok && d == dev
}

// folder is one folder read from the disk.
type folder struct {
	mtime int64
	kids  []filesearch.Child
}

func join(dir, name string) string {
	if strings.HasSuffix(dir, "/") {
		return dir + name
	}
	return dir + "/" + name
}

func statTime(st *unix.Stat_t) int64 { return st.Mtim.Sec*1e9 + st.Mtim.Nsec }

// read reads the folder at path, under root: never through a link (but
// the root itself, which the user named), never onto another device.
func (f *filter) read(root, path string) (folder, error) {
	dev, ok := f.rootDev(root)
	if !ok {
		return folder{}, os.ErrNotExist
	}
	flags := unix.O_RDONLY | unix.O_DIRECTORY | unix.O_CLOEXEC
	if path != root {
		flags |= unix.O_NOFOLLOW
	}
	fd, err := unix.Open(path, flags, 0)
	if err != nil {
		return folder{}, &os.PathError{Op: "open", Path: path, Err: err}
	}
	var st unix.Stat_t
	if err := unix.Fstat(fd, &st); err != nil || path != root && st.Dev != dev && !f.rootOn(root, st.Dev) {
		unix.Close(fd)
		return folder{}, os.ErrNotExist
	}
	if path == root {
		// A disk mounted again at the root may have another device
		dev, f.devs[root] = st.Dev, st.Dev
	}
	file := os.NewFile(uintptr(fd), path)
	defer file.Close()
	names, err := file.Readdirnames(-1)
	if err != nil && len(names) == 0 {
		return folder{}, err
	}
	out := folder{mtime: statTime(&st), kids: make([]filesearch.Child, 0, len(names))}
	for _, name := range names {
		if !f.keep(root, join(path, name), name) {
			continue
		}
		var cst unix.Stat_t
		if unix.Fstatat(fd, name, &cst, unix.AT_SYMLINK_NOFOLLOW) != nil {
			continue
		}
		kid := filesearch.Child{Name: []byte(name), Mtime: statTime(&cst)}
		switch cst.Mode & unix.S_IFMT {
		case unix.S_IFDIR:
			if cst.Dev != dev {
				continue // a mount point: another device
			}
			kid.Dir = true
		case unix.S_IFLNK:
			kid.Link = true
		case unix.S_IFREG:
		default:
			continue // sockets, pipes, devices
		}
		out.kids = append(out.kids, kid)
	}
	return out, nil
}

// cleanRoots are the roots as the index takes them: absolute, clean, each
// once, none inside another.
func cleanRoots(roots []string) []string {
	var out []string
	for _, r := range roots {
		if !filepath.IsAbs(r) {
			continue
		}
		out = append(out, filepath.Clean(r))
	}
	slices.Sort(out)
	out = slices.Compact(out)
	var kept []string
	for _, r := range out {
		if !slices.ContainsFunc(kept, func(k string) bool { return within(r, k) }) {
			kept = append(kept, r)
		}
	}
	return kept
}

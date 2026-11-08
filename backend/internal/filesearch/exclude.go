package filesearch

import (
	"path"
	"strings"
)

// Excludes are the folders and files a crawl leaves out: a pattern
// without "/" is a glob matched against a name (".git", "*.pyc"), one with
// "/" a path's last segments, each a glob (".local/share/Trash" below the
// root, or "go/pkg" anywhere).
type Excludes struct {
	names []string
	paths [][]string
}

// ParseExcludes reads the patterns; an empty one, or one that isn't a
// valid glob, is left out.
func ParseExcludes(patterns []string) Excludes {
	var x Excludes
	for _, p := range patterns {
		p = strings.Trim(strings.TrimSpace(p), "/")
		if p == "" {
			continue
		}
		segs := strings.Split(p, "/")
		valid := true
		for _, s := range segs {
			if _, err := path.Match(s, ""); err != nil || s == "" {
				valid = false
			}
		}
		if !valid {
			continue
		}
		if len(segs) == 1 {
			x.names = append(x.names, p)
		} else {
			x.paths = append(x.paths, segs)
		}
	}
	return x
}

// Skip says whether an entry is excluded; rel is its path below its root
// ("a/b/name").
func (x Excludes) Skip(rel string) bool {
	name := rel[strings.LastIndexByte(rel, '/')+1:]
	for _, p := range x.names {
		if ok, _ := path.Match(p, name); ok {
			return true
		}
	}
	if len(x.paths) == 0 {
		return false
	}
	segs := strings.Split(rel, "/")
	for _, p := range x.paths {
		if len(p) > len(segs) {
			continue
		}
		tail, all := segs[len(segs)-len(p):], true
		for i, s := range p {
			if ok, _ := path.Match(s, tail[i]); !ok {
				all = false
				break
			}
		}
		if all {
			return true
		}
	}
	return false
}

package mimeapps

import (
	"bufio"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
)

// Globs is shared-mime-info's globs2, its icon lists and its type
// hierarchy, read once: what type a file's name says it is, the icons a
// type shows, and the types it's a kind of. A plain
// "*.ext" or literal pattern (nearly all of them) is a map lookup, so the
// launcher can ask for every result; only the rest are matched in turn.
type Globs struct {
	ext      map[string]glob // "tar.gz" → *.tar.gz, case ignored
	extCased map[string]glob
	literal  map[string]glob // "readme" → README, case ignored
	litCased map[string]glob
	other    []glob
	icons    map[string]string   // mime/icons
	generic  map[string]string   // mime/generic-icons
	alias    map[string]string   // mime/aliases: an alias → its type
	aliases  map[string][]string // a type → its aliases
	parents  map[string][]string // mime/subclasses: a type → the types it's a kind of
}

// glob is one of shared-mime-info's globs2 lines
type glob struct {
	weight  int
	mime    string
	pattern string
	cased   bool // matched as written ("cs")
	order   int  // its place, for a tie
}

// beats: heavier, then longer, then earlier
func (g glob) beats(o glob) bool {
	if o.mime == "" {
		return true
	}
	if g.weight != o.weight {
		return g.weight > o.weight
	}
	if len(g.pattern) != len(o.pattern) {
		return len(g.pattern) > len(o.pattern)
	}
	return g.order < o.order
}

const globMeta = "*?[\\"

// LoadGlobs reads the mime/globs2, mime/icons, mime/generic-icons,
// mime/aliases and mime/subclasses of each data folder, most important
// first ($XDG_DATA_HOME, then $XDG_DATA_DIRS).
func LoadGlobs(dataDirs []string) *Globs {
	g := &Globs{ext: map[string]glob{}, extCased: map[string]glob{}, literal: map[string]glob{}, litCased: map[string]glob{},
		icons: map[string]string{}, generic: map[string]string{},
		alias: map[string]string{}, aliases: map[string][]string{}, parents: map[string][]string{}}
	order := 0
	for _, d := range dataDirs {
		eachLine(filepath.Join(d, "mime", "globs2"), func(line string) {
			parts := strings.SplitN(line, ":", 4)
			if len(parts) < 3 {
				return
			}
			w, err := strconv.Atoi(parts[0])
			if err != nil {
				return
			}
			gl := glob{weight: w, mime: parts[1], pattern: parts[2], cased: len(parts) == 4 && strings.Contains(parts[3], "cs"), order: order}
			order++
			g.addGlob(gl)
		})
		for file, into := range map[string]map[string]string{"icons": g.icons, "generic-icons": g.generic} {
			eachLine(filepath.Join(d, "mime", file), func(line string) {
				if mime, icon, ok := strings.Cut(line, ":"); ok {
					if _, seen := into[mime]; !seen {
						into[mime] = icon
					}
				}
			})
		}
		eachLine(filepath.Join(d, "mime", "aliases"), func(line string) {
			if alias, mime, ok := strings.Cut(line, " "); ok && alias != mime {
				if _, seen := g.alias[alias]; !seen {
					g.alias[alias] = mime
					g.aliases[mime] = append(g.aliases[mime], alias)
				}
			}
		})
		eachLine(filepath.Join(d, "mime", "subclasses"), func(line string) {
			if child, parent, ok := strings.Cut(line, " "); ok && !slices.Contains(g.parents[child], parent) {
				g.parents[child] = append(g.parents[child], parent)
			}
		})
	}
	return g
}

// Canonical is the type an alias stands for (mime/aliases), else mime.
func (g *Globs) Canonical(mime string) string {
	if m, ok := g.alias[mime]; ok {
		return m
	}
	return mime
}

// Lineage is the types to look an app up by for a type, nearest first
// (the MIME Applications spec: with no app for a type, its parents'):
// the type itself (an alias as its type), each followed by its aliases
// (lists and entries may name either), then its parents level by level
// (mime/subclasses, and text/plain for every other text/*), each once,
// so a cycle in the files ends. "" has none.
func (g *Globs) Lineage(mime string) []string {
	if mime == "" {
		return nil
	}
	var out []string
	seen := map[string]bool{}
	queue := []string{g.Canonical(mime)}
	for len(queue) > 0 {
		t := queue[0]
		queue = queue[1:]
		if seen[t] {
			continue
		}
		seen[t] = true
		out = append(out, t)
		for _, a := range g.aliases[t] {
			if !seen[a] {
				seen[a] = true
				out = append(out, a)
			}
		}
		for _, p := range g.parents[t] {
			queue = append(queue, g.Canonical(p))
		}
		if strings.HasPrefix(t, "text/") && t != "text/plain" {
			queue = append(queue, "text/plain")
		}
	}
	return out
}

func (g *Globs) addGlob(gl glob) {
	keep := func(m map[string]glob, key string) {
		if old, ok := m[key]; !ok || gl.beats(old) {
			m[key] = gl
		}
	}
	p := gl.pattern
	switch {
	case strings.HasPrefix(p, "*.") && !strings.ContainsAny(p[2:], globMeta):
		if gl.cased {
			keep(g.extCased, p[2:])
		} else {
			keep(g.ext, strings.ToLower(p[2:]))
		}
	case !strings.ContainsAny(p, globMeta):
		if gl.cased {
			keep(g.litCased, p)
		} else {
			keep(g.literal, strings.ToLower(p))
		}
	default:
		g.other = append(g.other, gl)
	}
}

func eachLine(path string, fn func(string)) {
	f, err := os.Open(path)
	if err != nil {
		return
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		if line := sc.Text(); line != "" && line[0] != '#' {
			fn(line)
		}
	}
}

// TypeOfName is the type a file's name says it is (the heaviest, then
// longest, pattern matching), "" when none does.
func (g *Globs) TypeOfName(name string) string {
	lower := strings.ToLower(name)
	var best glob
	consider := func(gl glob, ok bool) {
		if ok && gl.beats(best) {
			best = gl
		}
	}
	consider(g.literal[lower], g.literal[lower].mime != "")
	consider(g.litCased[name], g.litCased[name].mime != "")
	// Every extension the name ends in: "a.tar.gz" is *.tar.gz and *.gz
	// (the dots found in each: a lower case may be shorter, as the Kelvin
	// sign's "k")
	for i := 0; i < len(lower); i++ {
		if lower[i] == '.' {
			if gl, ok := g.ext[lower[i+1:]]; ok {
				consider(gl, true)
			}
		}
	}
	for i := 0; i < len(name); i++ {
		if name[i] == '.' {
			if gl, ok := g.extCased[name[i+1:]]; ok {
				consider(gl, true)
			}
		}
	}
	for _, gl := range g.other {
		subject, pattern := name, gl.pattern
		if !gl.cased {
			subject, pattern = lower, strings.ToLower(pattern)
		}
		if ok, _ := filepath.Match(pattern, subject); ok {
			consider(gl, true)
		}
	}
	return best.mime
}

// IconOf is the icon names a type shows, most specific first: its own
// icon (mime/icons, else the type with "/" as "-"), then its generic one
// (mime/generic-icons, else "<media>-x-generic"). A folder is "folder".
func (g *Globs) IconOf(mime string) []string {
	if mime == "inode/directory" {
		return []string{"folder"}
	}
	if mime == "" {
		return nil
	}
	own := g.icons[mime]
	if own == "" {
		own = strings.Replace(mime, "/", "-", 1)
	}
	generic := g.generic[mime]
	if generic == "" {
		media, _, _ := strings.Cut(mime, "/")
		generic = media + "-x-generic"
	}
	if generic == own {
		return []string{own}
	}
	return []string{own, generic}
}

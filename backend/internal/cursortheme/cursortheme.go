// Package cursortheme decides the cursor theme XCursor readers get (the
// compositor's xcursor-theme, XCURSOR_THEME, GTK's cursor-theme), for
// CursorThemeManager through the daemon's `cursor.theme`.
//
// Many themes name their cursors only the X11 way (left_ptr, hand2,
// sb_h_double_arrow) and don't say what they inherit. A lookup by a
// standard name ("default", "pointer", "ew-resize": what the cursor-shape
// protocol and toolkits ask for) then falls back to the "default" theme,
// often Adwaita, before any reader tries the X11 name: the arrow comes
// from another theme. For such a theme Resolve writes a companion theme,
// axiom-cursor-<theme> in $XDG_DATA_HOME/icons/, inheriting it, with each
// standard name it lacks linked to its own X11 cursor. Each theme's
// companion has its own name, so a switch from one to another changes the
// name readers get, and they load the cursors again.
//
// What a theme lacks and what a companion holds are decided by the pure
// functions (Links, CompanionName, indexText, inherits); Resolve walks the
// icon folders and writes.
package cursortheme

import (
	"context"
	"maps"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"sync"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/xdg"
)

// Prefix starts every companion theme's name (the shell leaves such
// themes out of the ones to pick).
const Prefix = "axiom-cursor"

// marker is in every companion's index.theme: a folder without it isn't
// axiom's, and is never replaced or removed.
const marker = "X-Axiom-Generated=true"

// aliases are the standard (CSS / cursor-spec) names and the X11 names
// themes use for them instead, most likely first.
var aliases = map[string][]string{
	"default":     {"left_ptr", "arrow", "top_left_arrow", "left_arrow"},
	"pointer":     {"hand2", "pointing_hand", "hand1", "hand"},
	"help":        {"question_arrow", "whats_this", "left_ptr_help"},
	"progress":    {"left_ptr_watch", "half-busy"},
	"wait":        {"watch"},
	"text":        {"xterm", "ibeam"},
	"crosshair":   {"cross", "tcross", "cross_reverse"},
	"cell":        {"plus"},
	"alias":       {"link", "dnd-link"},
	"copy":        {"dnd-copy"},
	"move":        {"fleur", "dnd-move", "size_all"},
	"no-drop":     {"dnd-no-drop", "circle", "forbidden"},
	"not-allowed": {"crossed_circle", "circle", "forbidden"},
	"grab":        {"openhand", "hand1"},
	"grabbing":    {"closedhand", "fleur"},
	"all-scroll":  {"fleur", "size_all"},
	"col-resize":  {"sb_h_double_arrow", "split_h", "size_hor"},
	"row-resize":  {"sb_v_double_arrow", "split_v", "size_ver"},
	"n-resize":    {"top_side", "size_ver"},
	"e-resize":    {"right_side", "size_hor"},
	"s-resize":    {"bottom_side", "size_ver"},
	"w-resize":    {"left_side", "size_hor"},
	"ne-resize":   {"top_right_corner", "size_bdiag"},
	"nw-resize":   {"top_left_corner", "size_fdiag"},
	"se-resize":   {"bottom_right_corner", "size_fdiag"},
	"sw-resize":   {"bottom_left_corner", "size_bdiag"},
	"ew-resize":   {"sb_h_double_arrow", "h_double_arrow", "size_hor"},
	"ns-resize":   {"sb_v_double_arrow", "v_double_arrow", "size_ver"},
	"nesw-resize": {"fd_double_arrow", "size_bdiag"},
	"nwse-resize": {"bd_double_arrow", "size_fdiag"},
	"zoom-in":     {"zoom_in"},
	"zoom-out":    {"zoom_out"},
}

// Result is the theme XCursor readers are to get.
type Result struct {
	// The companion's name, or the theme's own when it needs none or has
	// no XCursor cursors (a hyprcursor-only theme)
	Theme string `json:"theme"`
	// How many standard names the companion links
	Filled int `json:"filled"`
}

// Options are where themes are looked for and how GTK is told.
type Options struct {
	Getenv func(string) string
	// GSettings runs gsettings with args and returns its output; nil
	// leaves GTK's settings alone. An error (gsettings missing, or without
	// GNOME's schema) skips them.
	GSettings func(ctx context.Context, args ...string) (string, error)
}

// Resolver writes companion themes, one call at a time.
type Resolver struct {
	opts Options
	mu   sync.Mutex
}

// New returns a Resolver.
func New(opts Options) *Resolver { return &Resolver{opts: opts} }

// Resolve makes sure theme's companion is as it should be (written, or
// left as it is when it already is), removes other themes' companions,
// sets GTK's cursor-theme (and cursor-size, when size > 0) to the result,
// and returns it. A folder at the companion's place that isn't axiom's is
// left alone: a Conflict.
func (r *Resolver) Resolve(ctx context.Context, theme string, size int) (Result, error) {
	if theme == "" || theme == "." || theme == ".." || strings.Contains(theme, "/") || strings.HasPrefix(theme, Prefix) {
		return Result{}, axerr.New(axerr.BadRequest, "not a cursor theme to wrap: %q", theme)
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	icons := filepath.Join(xdg.ResolveBases(r.opts.Getenv).Data, "icons")
	dest := filepath.Join(icons, CompanionName(theme))
	have := r.cursors(theme, map[string]bool{})
	result := Result{Theme: theme}
	if len(have) > 0 {
		if links := Links(have); len(links) > 0 {
			if !holds(dest, theme, links) {
				if _, err := os.Lstat(dest); err == nil && !ours(dest) {
					return Result{}, axerr.New(axerr.Conflict, "%s isn't axiom's: left as it is", dest)
				}
				if err := write(dest, theme, links); err != nil {
					return Result{}, axerr.Wrap(axerr.Unavailable, err, "writing %s", dest)
				}
			}
			result = Result{Theme: filepath.Base(dest), Filled: len(links)}
		}
	}
	// Other themes' companions, and the one this theme no longer needs
	others, _ := filepath.Glob(filepath.Join(icons, Prefix+"*"))
	for _, other := range others {
		if filepath.Base(other) != result.Theme && ours(other) {
			_ = os.RemoveAll(other)
		}
	}
	r.setGTK(ctx, result.Theme, size)
	return result, nil
}

// searchPaths are where XCursor readers look for themes without
// XCURSOR_PATH, as libXcursor and xcursor-rs do.
func (r *Resolver) searchPaths() []string {
	data := xdg.SearchDirs(r.opts.Getenv)
	paths := []string{filepath.Join(data[0], "icons"), filepath.Join(xdg.ResolveBases(r.opts.Getenv).Home, ".icons")}
	for _, d := range data[1:] {
		paths = append(paths, filepath.Join(d, "icons"))
	}
	return append(paths, "/usr/share/pixmaps")
}

// cursors are the cursors theme has, its own and what it inherits by
// name (not the implicit "default"): name → file, the nearest winning.
// Companions are never walked into.
func (r *Resolver) cursors(theme string, walked map[string]bool) map[string]string {
	if walked[theme] || strings.HasPrefix(theme, Prefix) {
		return nil
	}
	walked[theme] = true
	found := map[string]string{}
	var parents []string
	for _, base := range r.searchPaths() {
		folder := filepath.Join(base, theme)
		if fi, err := os.Stat(folder); err != nil || !fi.IsDir() {
			continue
		}
		entries, _ := os.ReadDir(filepath.Join(folder, "cursors"))
		for _, e := range entries {
			path := filepath.Join(folder, "cursors", e.Name())
			if _, taken := found[e.Name()]; !taken {
				// A dangling link is no cursor
				if _, err := os.Stat(path); err == nil {
					found[e.Name()] = path
				}
			}
		}
		if index, err := os.ReadFile(filepath.Join(folder, "index.theme")); err == nil {
			for _, p := range inherits(string(index)) {
				if !slices.Contains(parents, p) {
					parents = append(parents, p)
				}
			}
		}
	}
	for _, parent := range parents {
		for name, path := range r.cursors(parent, walked) {
			if _, taken := found[name]; !taken {
				found[name] = path
			}
		}
	}
	return found
}

// setGTK sets GTK's cursor settings where gsettings knows them, only what
// differs.
func (r *Resolver) setGTK(ctx context.Context, theme string, size int) {
	if r.opts.GSettings == nil {
		return
	}
	const schema = "org.gnome.desktop.interface"
	wanted := [][2]string{{"cursor-theme", theme}}
	if size > 0 {
		wanted = append(wanted, [2]string{"cursor-size", strconv.Itoa(size)})
	}
	for _, kv := range wanted {
		got, err := r.opts.GSettings(ctx, "get", schema, kv[0])
		if err != nil {
			return
		}
		if strings.Trim(strings.TrimSpace(got), "'") != kv[1] {
			_, _ = r.opts.GSettings(ctx, "set", schema, kv[0], kv[1])
		}
	}
}

// holds: dest is the companion of theme with exactly links.
func holds(dest, theme string, links map[string]string) bool {
	index, err := os.ReadFile(filepath.Join(dest, "index.theme"))
	if err != nil || string(index) != indexText(theme) {
		return false
	}
	entries, err := os.ReadDir(filepath.Join(dest, "cursors"))
	if err != nil {
		return false
	}
	got := map[string]string{}
	for _, e := range entries {
		if e.Type()&os.ModeSymlink != 0 {
			target, err := os.Readlink(filepath.Join(dest, "cursors", e.Name()))
			if err != nil {
				return false
			}
			got[e.Name()] = target
		}
	}
	return maps.Equal(got, links)
}

// ours: dest's index.theme carries the marker.
func ours(dest string) bool {
	index, err := os.ReadFile(filepath.Join(dest, "index.theme"))
	return err == nil && strings.Contains(string(index), marker)
}

// write puts the companion at dest: built beside it, then swapped in, so
// a reader never sees half of one.
func write(dest, theme string, links map[string]string) (err error) {
	parent := filepath.Dir(dest)
	if err := os.MkdirAll(parent, 0o755); err != nil {
		return err
	}
	staged, err := os.MkdirTemp(parent, "."+filepath.Base(dest)+".")
	if err != nil {
		return err
	}
	defer func() {
		if err != nil {
			_ = os.RemoveAll(staged)
		}
	}()
	if err := os.Mkdir(filepath.Join(staged, "cursors"), 0o755); err != nil {
		return err
	}
	for name, target := range links {
		if err := os.Symlink(target, filepath.Join(staged, "cursors", name)); err != nil {
			return err
		}
	}
	if err := os.WriteFile(filepath.Join(staged, "index.theme"), []byte(indexText(theme)), 0o644); err != nil {
		return err
	}
	if err := os.Chmod(staged, 0o755); err != nil {
		return err
	}
	old := ""
	if _, err := os.Lstat(dest); err == nil {
		old = filepath.Join(parent, "."+filepath.Base(dest)+".old")
		_ = os.RemoveAll(old)
		if err := os.Rename(dest, old); err != nil {
			return err
		}
	}
	if err := os.Rename(staged, dest); err != nil {
		return err
	}
	if old != "" {
		_ = os.RemoveAll(old)
	}
	return nil
}

// Links are the standard names a theme with cursors have (name → file)
// lacks, each linked to the file of its first X11 alias the theme has.
func Links(have map[string]string) map[string]string {
	links := map[string]string{}
	for name, x11 := range aliases {
		if _, ok := have[name]; ok {
			continue
		}
		for _, a := range x11 {
			if file, ok := have[a]; ok {
				links[name] = file
				break
			}
		}
	}
	return links
}

var unsafeName = regexp.MustCompile(`[^A-Za-z0-9._-]+`)

// CompanionName is theme's companion's name, usable as a folder and,
// unquoted, in a compositor's config.
func CompanionName(theme string) string {
	return Prefix + "-" + unsafeName.ReplaceAllString(theme, "_")
}

// indexText is a companion's index.theme.
func indexText(theme string) string {
	return "[Icon Theme]\nName=" + CompanionName(theme) + "\nComment=" + theme +
		", with the standard cursor names it lacks (written by axiom)\nInherits=" + theme + "\n" + marker + "\n"
}

// inherits are the themes an index.theme names in its Inherits line.
func inherits(index string) []string {
	for _, line := range strings.Split(index, "\n") {
		key, value, _ := strings.Cut(line, "=")
		if strings.TrimSpace(key) != "Inherits" {
			continue
		}
		var themes []string
		for _, t := range strings.FieldsFunc(value, func(r rune) bool { return r == ',' || r == ';' }) {
			if t = strings.TrimSpace(t); t != "" {
				themes = append(themes, t)
			}
		}
		return themes
	}
	return nil
}

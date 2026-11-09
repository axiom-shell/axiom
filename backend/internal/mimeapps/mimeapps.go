// Package mimeapps is the user's default apps the way the freedesktop
// specs keep them: which desktop entry opens each file type and URL
// scheme (the MIME Applications Associations spec: the mimeapps.list
// files, desktop-specific ones first, and defaults.list), and which
// terminal starts (xdg-terminal-exec's xdg-terminals.list). It reads the
// desktop entries, answers a role's choices and default (Settings ›
// General › Default apps: the browser, file manager, terminal, …), writes
// a change into the user's own list, and turns what's to be opened (a
// role, a URL, a path) into the command that opens it (`axiom open`).
// Docs: docs/dev/features/default-apps.md.
package mimeapps

import (
	"cmp"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

// Role is a kind of app the settings offer as one choice: the MIME types
// it covers, its first the one whose default it shows.
type Role struct {
	ID    string   `json:"id"`
	Types []string `json:"types"` // none for the terminal
}

// Roles, in the order the settings list them (DefaultAppsManager.roleList
// names them)
var Roles = []Role{
	{ID: "browser", Types: []string{"x-scheme-handler/http", "x-scheme-handler/https", "text/html", "application/xhtml+xml"}},
	{ID: "mail", Types: []string{"x-scheme-handler/mailto"}},
	{ID: "fileManager", Types: []string{"inode/directory"}},
	{ID: "terminal"},
	{ID: "textEditor", Types: []string{"text/plain", "text/markdown", "application/x-shellscript"}},
	{ID: "images", Types: []string{"image/png", "image/jpeg", "image/gif", "image/webp", "image/bmp", "image/svg+xml", "image/tiff", "image/avif", "image/heic"}},
	{ID: "video", Types: []string{"video/mp4", "video/x-matroska", "video/webm", "video/quicktime", "video/x-msvideo", "video/mpeg", "video/ogg"}},
	{ID: "music", Types: []string{"audio/mpeg", "audio/flac", "audio/ogg", "audio/x-wav", "audio/mp4", "audio/aac", "audio/opus", "audio/x-vorbis+ogg"}},
	{ID: "pdf", Types: []string{"application/pdf"}},
	{ID: "archives", Types: []string{"application/zip", "application/x-tar", "application/x-compressed-tar", "application/gzip", "application/x-7z-compressed", "application/vnd.rar", "application/x-xz", "application/zstd"}},
}

// RoleOf is the role named id, ok false for none.
func RoleOf(id string) (Role, bool) {
	for _, r := range Roles {
		if r.ID == id {
			return r, true
		}
	}
	return Role{}, false
}

// Options are where the lists and entries are (the XDG base folders, as
// xdg.Resolve has them) and the desktops running ($XDG_CURRENT_DESKTOP,
// lowercased: their desktop-specific lists are read first).
type Options struct {
	ConfigHome string
	ConfigDirs []string
	DataHome   string
	DataDirs   []string
	Desktops   []string
}

// FromEnv is Options from the environment, the spec's defaults filling in.
func FromEnv(getenv func(string) string) Options {
	home := getenv("HOME")
	or := func(v, fallback string) string {
		if v == "" {
			return fallback
		}
		return v
	}
	split := func(v string) []string {
		var out []string
		for _, s := range strings.Split(v, ":") {
			if s != "" {
				out = append(out, s)
			}
		}
		return out
	}
	o := Options{
		ConfigHome: or(getenv("XDG_CONFIG_HOME"), filepath.Join(home, ".config")),
		ConfigDirs: split(or(getenv("XDG_CONFIG_DIRS"), "/etc/xdg")),
		DataHome:   or(getenv("XDG_DATA_HOME"), filepath.Join(home, ".local/share")),
		DataDirs:   split(or(getenv("XDG_DATA_DIRS"), "/usr/local/share:/usr/share")),
	}
	for _, d := range split(getenv("XDG_CURRENT_DESKTOP")) {
		o.Desktops = append(o.Desktops, strings.ToLower(d))
	}
	return o
}

// Apps is the desktop entries and lists as read once (Load); a change
// writes the user's list and is seen by the next Load.
type Apps struct {
	o       Options
	entries map[string]Entry
	lists   []appsList // mimeapps.list files, most important first
	legacy  []appsList // defaults.list files, read last
	// shared-mime-info's globs and type hierarchy, read when first asked
	// (mimeDB)
	globs *Globs
}

// Load reads the entries and lists.
func Load(o Options) *Apps {
	a := &Apps{o: o}
	var appDirs []string
	for _, d := range append([]string{o.DataHome}, o.DataDirs...) {
		appDirs = append(appDirs, filepath.Join(d, "applications"))
	}
	a.entries = scanEntries(appDirs)
	for _, path := range a.listPaths() {
		if l := readList(path); l != nil {
			a.lists = append(a.lists, l)
		}
	}
	for _, d := range appDirs {
		if l := readList(filepath.Join(d, "defaults.list")); l != nil {
			a.legacy = append(a.legacy, l)
		}
	}
	return a
}

// listPaths are the mimeapps.list files in the spec's order: per folder
// (config home, config dirs, data home's and data dirs' applications),
// each desktop's own list before the plain one.
func (a *Apps) listPaths() []string {
	var folders []string
	folders = append(folders, a.o.ConfigHome)
	folders = append(folders, a.o.ConfigDirs...)
	folders = append(folders, filepath.Join(a.o.DataHome, "applications"))
	for _, d := range a.o.DataDirs {
		folders = append(folders, filepath.Join(d, "applications"))
	}
	return a.named(folders, "mimeapps.list")
}

func (a *Apps) named(folders []string, name string) []string {
	var out []string
	for _, f := range folders {
		for _, desktop := range a.o.Desktops {
			out = append(out, filepath.Join(f, desktop+"-"+name))
		}
		out = append(out, filepath.Join(f, name))
	}
	return out
}

// Entry is the desktop entry id, ok false when it isn't installed.
func (a *Apps) Entry(id string) (Entry, bool) {
	e, ok := a.entries[id]
	return e, ok
}

// Default is the desktop entry that opens a type: its own (ownDefault,
// under any of its names), else the nearest parent type's
// (Globs.Lineage: a script with no app of its own opens in text/plain's).
func (a *Apps) Default(mime string) string {
	for _, names := range a.lineage(mime) {
		if id := a.ownDefault(names); id != "" {
			return id
		}
	}
	return ""
}

// lineage is the types an app for mime is looked up by, nearest first,
// each with its aliases (Globs.Lineage; just mime when it's not a known
// type).
func (a *Apps) lineage(mime string) [][]string {
	if mime == "" {
		return nil
	}
	return a.mimeDB().Lineage(mime)
}

// ownDefault is the desktop entry that opens one type, given by its
// names (the type and its aliases): the first installed one a Default
// Applications line for any of them lists (not removed by a more
// important list), else defaults.list's, else the first one associated
// with it.
func (a *Apps) ownDefault(names []string) string {
	removed := map[string]bool{}
	for _, l := range a.lists {
		for _, mime := range names {
			for _, id := range l[groupDefault][mime] {
				if _, ok := a.entries[id]; ok && !removed[id] {
					return id
				}
			}
		}
		for _, mime := range names {
			for _, id := range l[groupRemoved][mime] {
				removed[id] = true
			}
		}
	}
	for _, l := range a.legacy {
		for _, mime := range names {
			for _, id := range l[groupDefault][mime] {
				if _, ok := a.entries[id]; ok && !removed[id] {
					return id
				}
			}
		}
	}
	if handlers := a.handlers(names); len(handlers) > 0 {
		return handlers[0].ID
	}
	return ""
}

// Handlers are the installed entries that open a type: the Added
// Associations in list order, then those declaring it (by name), less
// the Removed Associations of the lists above each; under any of its
// names (the type and its aliases).
func (a *Apps) Handlers(mime string) []Entry {
	if l := a.lineage(mime); len(l) > 0 {
		return a.handlers(l[0])
	}
	return nil
}

// handlers is Handlers of one type given by its names.
func (a *Apps) handlers(names []string) []Entry {
	var out []Entry
	seen, removed := map[string]bool{}, map[string]bool{}
	add := func(id string) {
		if e, ok := a.entries[id]; ok && !seen[id] && !removed[id] {
			seen[id] = true
			out = append(out, e)
		}
	}
	for _, l := range a.lists {
		for _, mime := range names {
			for _, id := range l[groupAdded][mime] {
				add(id)
			}
		}
		for _, mime := range names {
			for _, id := range l[groupRemoved][mime] {
				removed[id] = true
			}
		}
	}
	var declared []Entry
	for _, e := range a.entries {
		if slices.ContainsFunc(names, e.handles) {
			declared = append(declared, e)
		}
	}
	sortEntries(declared)
	for _, e := range declared {
		add(e.ID)
	}
	return out
}

func sortEntries(entries []Entry) {
	slices.SortFunc(entries, func(x, y Entry) int {
		return cmp.Or(cmp.Compare(strings.ToLower(x.Name), strings.ToLower(y.Name)), cmp.Compare(x.ID, y.ID))
	})
}

// RoleState is a role as the settings show it: its default, whether some
// of its types open in another app (mixed), and the apps to pick from.
type RoleState struct {
	Role
	Default  string  `json:"default"` // desktop id, "" for none
	Mixed    bool    `json:"mixed"`
	Handlers []Entry `json:"handlers"`
}

// State is every role's.
func (a *Apps) State() []RoleState {
	var out []RoleState
	for _, r := range Roles {
		out = append(out, a.RoleState(r))
	}
	return out
}

// RoleState is one role's: the default its first type opens in, the apps
// handling any of its types (most of them first) and, for the terminal,
// the terminal emulators.
func (a *Apps) RoleState(r Role) RoleState {
	st := RoleState{Role: r}
	if r.ID == "terminal" {
		st.Default = a.Terminal()
		for _, e := range a.entries {
			if e.isTerminal() {
				st.Handlers = append(st.Handlers, e)
			}
		}
		sortEntries(st.Handlers)
		return st
	}
	st.Default = a.Default(r.Types[0])
	for _, mime := range r.Types[1:] {
		if d := a.Default(mime); d != "" && d != st.Default {
			st.Mixed = true
		}
	}
	count := map[string]int{}
	byID := map[string]Entry{}
	for _, mime := range r.Types {
		for _, e := range a.Handlers(mime) {
			count[e.ID]++
			byID[e.ID] = e
		}
	}
	for _, e := range byID {
		st.Handlers = append(st.Handlers, e)
	}
	slices.SortFunc(st.Handlers, func(x, y Entry) int {
		return cmp.Or(cmp.Compare(count[y.ID], count[x.ID]), cmp.Compare(strings.ToLower(x.Name), strings.ToLower(y.Name)))
	})
	return st
}

// Terminal is the terminal emulator to start: the first installed one an
// xdg-terminals.list names (config home, config dirs, then data dirs'
// xdg-terminal-exec folders; each desktop's own list first), else the
// first installed by name.
func (a *Apps) Terminal() string {
	var folders []string
	folders = append(folders, a.o.ConfigHome)
	folders = append(folders, a.o.ConfigDirs...)
	folders = append(folders, filepath.Join(a.o.DataHome, "xdg-terminal-exec"))
	for _, d := range a.o.DataDirs {
		folders = append(folders, filepath.Join(d, "xdg-terminal-exec"))
	}
	for _, path := range a.named(folders, "xdg-terminals.list") {
		for _, id := range readTerminals(path) {
			if e, ok := a.entries[id]; ok && e.isTerminal() {
				return id
			}
		}
	}
	var terminals []Entry
	for _, e := range a.entries {
		if e.isTerminal() {
			terminals = append(terminals, e)
		}
	}
	sortEntries(terminals)
	if len(terminals) > 0 {
		return terminals[0].ID
	}
	return ""
}

// SetDefault makes id the role's app: every type of the role the entry
// handles (its first type always) in the user's mimeapps.list, or first
// in their xdg-terminals.list for the terminal. It writes the most
// important list of the user's that exists (a desktop's own before the
// plain one), so the change isn't shadowed by it.
func (a *Apps) SetDefault(roleID, id string) error {
	r, ok := RoleOf(roleID)
	if !ok {
		return axerr.New(axerr.BadRequest, "no role %q", roleID)
	}
	e, ok := a.entries[id]
	if !ok {
		return axerr.New(axerr.NotFound, "%s isn't installed", id)
	}
	if r.ID == "terminal" {
		if !e.isTerminal() {
			return axerr.New(axerr.BadRequest, "%s isn't a terminal", id)
		}
		path := a.userList("xdg-terminals.list")
		data, _ := os.ReadFile(path)
		return writeText(path, setTerminal(string(data), id))
	}
	mimes := []string{r.Types[0]}
	for _, mime := range r.Types[1:] {
		if e.handles(mime) || slices.ContainsFunc(a.Handlers(mime), func(h Entry) bool { return h.ID == id }) {
			mimes = append(mimes, mime)
		}
	}
	return a.SetTypes(mimes, id)
}

// SetTypes makes id the default for each type given (Settings' one-type
// rows), in the user's mimeapps.list.
func (a *Apps) SetTypes(mimes []string, id string) error {
	if _, ok := a.entries[id]; !ok {
		return axerr.New(axerr.NotFound, "%s isn't installed", id)
	}
	for _, m := range mimes {
		if !validMime(m) {
			return axerr.New(axerr.BadRequest, "%q is no MIME type", m)
		}
	}
	// Under the type's own name, which a list checks before its aliases
	// (ownDefault): a line for it there would beat one for the alias
	names := make([]string, len(mimes))
	for i, m := range mimes {
		names[i] = a.mimeDB().Canonical(m)
	}
	path := a.userList("mimeapps.list")
	data, _ := os.ReadFile(path)
	return writeText(path, setDefaults(string(data), names, id))
}

// userList is the user's list called name in their config home: a
// desktop's own when it exists, else the plain one.
func (a *Apps) userList(name string) string {
	for _, desktop := range a.o.Desktops {
		if p := filepath.Join(a.o.ConfigHome, desktop+"-"+name); fileExists(p) {
			return p
		}
	}
	return filepath.Join(a.o.ConfigHome, name)
}

func fileExists(path string) bool {
	st, err := os.Stat(path)
	return err == nil && st.Mode().IsRegular()
}

// validMime: type/subtype, nothing a list line could be broken by
func validMime(m string) bool {
	t, sub, ok := strings.Cut(m, "/")
	return ok && t != "" && sub != "" && !strings.ContainsAny(m, "=;\n[] \t")
}

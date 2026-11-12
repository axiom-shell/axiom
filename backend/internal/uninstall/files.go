package uninstall

import (
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/compositor/manager"
	"github.com/axiom-shell/axiom/backend/internal/compositor/userconf"
	"github.com/axiom-shell/axiom/backend/internal/footprint"
	"github.com/axiom-shell/axiom/backend/internal/xdg"
)

// The compositors the uninstall gives the config back of.
var kinds = []string{kindHyprland, kindSway, kindNiri}

// offline is the writer of kind, reading the files only.
func (o Options) offline(kind string) *manager.Offline {
	w, _ := manager.NewOffline(o.Getenv, kind, o.Bin)
	return w
}

// lineFile is a file whose axiom lines are taken out.
type lineFile struct{ Kind, Path string }

// userOwned says a config is the user's to edit: not the system's.
func userOwned(path string) bool {
	return !strings.HasPrefix(path, "/etc/") && !strings.HasPrefix(path, "/usr/")
}

// lineFiles are the files install.sh and the Settings buttons put axiom's
// lines in: each compositor's main config (the one it runs, and the one
// install.sh edits), the portals' configs. Each once, by the file it is.
func (o Options) lineFiles() []lineFile {
	var out []lineFile
	seen := map[string]bool{}
	add := func(kind, path string) {
		if path == "" || !userOwned(path) || !isFile(path) {
			return
		}
		real, err := filepath.EvalSymlinks(path)
		if err != nil {
			real = path
		}
		if key := kind + " " + real; !seen[key] {
			seen[key] = true
			out = append(out, lineFile{kind, path})
		}
	}
	bases := xdg.ResolveBases(o.Getenv)
	add(kindHyprland, filepath.Join(bases.Config, "hypr", "hyprland.lua"))
	add(kindSway, userconf.SwayMain(o.Getenv))
	add(kindSway, filepath.Join(bases.Config, "sway", "config"))
	add(kindNiri, userconf.NiriMain(o.Getenv))
	add(kindNiri, filepath.Join(bases.Config, "niri", "config.kdl"))
	add(kindXDPH, filepath.Join(bases.Config, "hypr", "xdph.conf"))
	add(kindXDPW, filepath.Join(bases.Config, "xdg-desktop-portal-wlr", "config"))
	return out
}

// isPortalPath: a file that's part of the screen-share portal's setup.
func isPortalPath(path string) bool {
	return strings.Contains(path, "xdg-desktop-portal") || strings.Contains(path, "portal.desktop.axiom") ||
		filepath.Base(path) == "xdph.conf"
}

// execBinary is the program a desktop file's first Exec= starts ("" without
// one), the first word read as the desktop entry spec has it: in double
// quotes with backslash escapes, else up to a space.
func execBinary(data []byte) string {
	for _, line := range strings.Split(string(data), "\n") {
		v, ok := strings.CutPrefix(strings.TrimSpace(line), "Exec=")
		if !ok {
			continue
		}
		v = strings.TrimSpace(v)
		if !strings.HasPrefix(v, `"`) {
			word, _, _ := strings.Cut(v, " ")
			return word
		}
		var b strings.Builder
		for i := 1; i < len(v); i++ {
			switch c := v[i]; {
			case c == '\\' && i+1 < len(v):
				i++
				b.WriteByte(v[i])
			case c == '"':
				return b.String()
			default:
				b.WriteByte(c)
			}
		}
		return b.String()
	}
	return ""
}

// namesIn are the entries of dir (files or folders) whose name match says
// yes, as paths, sorted: a listing of one folder, never a glob (a folder's
// own name may hold glob characters).
func namesIn(dir string, match func(name string) bool) []string {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil
	}
	var out []string
	for _, e := range entries {
		if match(e.Name()) {
			out = append(out, filepath.Join(dir, e.Name()))
		}
	}
	return out
}

// ownsExec: the file's Exec= names a binary called axiom.
func ownsExec(path string) bool {
	data, err := os.ReadFile(path)
	return err == nil && filepath.Base(execBinary(data)) == "axiom"
}

// installedFile is a file install.sh puts in the data folder.
type installedFile struct {
	Path string
	// Dirs are the folders it sits in that go when it was their last
	Dirs []string
}

// installedFiles are install.sh's files that exist: the desktop entries
// whose Exec names axiom, the portal's .portal file and D-Bus service.
func (o Options) installedFiles() []installedFile {
	data := xdg.ResolveBases(o.Getenv).Data
	var out []installedFile
	entries := namesIn(filepath.Join(data, "applications"), func(n string) bool {
		return strings.HasPrefix(n, "axiom-") && strings.HasSuffix(n, ".desktop")
	})
	for _, e := range entries {
		if ownsExec(e) {
			out = append(out, installedFile{e, []string{filepath.Join(data, "applications")}})
		}
	}
	portal := filepath.Join(data, "xdg-desktop-portal", "portals", "axiom.portal")
	if isFile(portal) {
		out = append(out, installedFile{portal, []string{filepath.Dir(portal), filepath.Dir(filepath.Dir(portal))}})
	}
	service := filepath.Join(data, "dbus-1", "services", "org.freedesktop.impl.portal.desktop.axiom.service")
	if isFile(service) && ownsExec(service) {
		out = append(out, installedFile{service, []string{filepath.Dir(service), filepath.Dir(filepath.Dir(service))}})
	}
	return out
}

// datedSuffix is install.sh's backup name: <file>.bak-YYYYMMDD-HHMMSS
var datedSuffix = regexp.MustCompile(`\.bak-\d{8}-\d{6}$`)

// backups are the copies of the user's files from before axiom changed
// them, which are kept: beside a hooked-up file (.axiom-bak-*, also the
// ledger rows' own), install.sh's .bak-<date> of a compositor config, a
// takeover's .axiom-backup-* and user/.backups, a claim's leftover record.
// Only those that exist, sorted.
func (o Options) backups(rows []footprint.Row, files []lineFile) []string {
	seen := map[string]bool{}
	add := func(p string) {
		if p == "" {
			return
		}
		if _, err := os.Lstat(p); err == nil {
			seen[p] = true
		}
	}
	for _, r := range rows {
		if r.Hookup != nil {
			add(r.Hookup.Backup)
			for _, b := range r.Hookup.Backups {
				add(b)
			}
		}
	}
	// beside is the entries of path's folder named path + a suffix
	// pattern: kept names start with path's own name
	beside := func(path, infix string, dated bool) {
		base := filepath.Base(path) + infix
		for _, p := range namesIn(filepath.Dir(path), func(n string) bool {
			return strings.HasPrefix(n, base) && (!dated || datedSuffix.MatchString(n))
		}) {
			add(p)
		}
	}
	for _, f := range files {
		beside(f.Path, ".axiom-bak-", false)
		beside(f.Path, ".bak-", true)
		if real, err := filepath.EvalSymlinks(f.Path); err == nil && real != f.Path {
			beside(real, ".axiom-bak-", false)
			beside(real, ".bak-", true)
		}
	}
	for _, kind := range kinds {
		w := o.offline(kind)
		if w == nil {
			continue
		}
		dir := filepath.Clean(w.ConfigDir())
		for _, d := range []string{dir, filepath.Join(dir, "user")} {
			for _, p := range namesIn(d, func(n string) bool { return strings.Contains(n, ".axiom-backup-") }) {
				add(p)
			}
		}
		add(filepath.Join(dir, "user", ".backups"))
		add(filepath.Join(dir, ".axiom-claimed"))
		for _, p := range namesIn(dir, func(n string) bool { return strings.Contains(n, ".axiom-bak-") || datedSuffix.MatchString(n) }) {
			add(p)
		}
	}
	out := make([]string, 0, len(seen))
	for p := range seen {
		out = append(out, p)
	}
	slices.Sort(out)
	return out
}

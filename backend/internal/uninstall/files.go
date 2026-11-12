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

// execBinary is the program a desktop file's Exec= starts ("" without one).
func execBinary(data []byte) string {
	for _, line := range strings.Split(string(data), "\n") {
		if v, ok := strings.CutPrefix(strings.TrimSpace(line), "Exec="); ok {
			f := strings.Fields(v)
			if len(f) == 0 {
				return ""
			}
			return strings.Trim(f[0], `"'`)
		}
	}
	return ""
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
	entries, _ := filepath.Glob(filepath.Join(data, "applications", "axiom-*.desktop"))
	slices.Sort(entries)
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

var dated = regexp.MustCompile(`\.bak-\d{8}-\d{6}$`)

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
	glob := func(pattern string, keep func(string) bool) {
		m, _ := filepath.Glob(pattern)
		for _, p := range m {
			if keep == nil || keep(p) {
				add(p)
			}
		}
	}
	for _, f := range files {
		glob(f.Path+".axiom-bak-*", nil)
		glob(f.Path+".bak-*", dated.MatchString)
		if real, err := filepath.EvalSymlinks(f.Path); err == nil && real != f.Path {
			glob(real+".axiom-bak-*", nil)
			glob(real+".bak-*", dated.MatchString)
		}
	}
	for _, kind := range kinds {
		w := o.offline(kind)
		if w == nil {
			continue
		}
		dir := filepath.Clean(w.ConfigDir())
		glob(filepath.Join(dir, "*.axiom-backup-*"), nil)
		glob(filepath.Join(dir, "user", "*.axiom-backup-*"), nil)
		glob(filepath.Join(dir, "user", ".backups"), nil)
		glob(filepath.Join(dir, ".axiom-claimed"), nil)
		glob(filepath.Join(dir, "*.axiom-bak-*"), nil)
		glob(filepath.Join(dir, "*.bak-*"), dated.MatchString)
	}
	out := make([]string, 0, len(seen))
	for p := range seen {
		out = append(out, p)
	}
	slices.Sort(out)
	return out
}

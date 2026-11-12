package uninstall

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

// folder is one of axiom's own folders: what's done to it, and the answer
// that decides it ("": always).
type folder struct {
	Path, What, Asks string
	// Base is the XDG base it sits directly under
	Base string
}

// folders are axiom's folders under the XDG bases, in the order they go.
func (o Options) folders() []folder {
	dir := func(p string) string { return strings.TrimRight(p, "/") }
	out := []folder{
		{Path: dir(o.Dirs.Cache), What: "Delete the cache"},
	}
	if root := o.runtimeRoot(); root != "" {
		out = append(out, folder{Path: root, What: "Delete the runtime files", Base: filepath.Dir(root)})
	}
	out = append(out,
		folder{Path: dir(o.Dirs.Data), What: "Delete the downloaded wallpapers and calendars", Asks: FieldKeepUserContent},
		folder{Path: dir(o.Dirs.Config), What: "Delete the settings and saved setups", Asks: FieldKeepConfig},
		folder{Path: dir(o.Dirs.State), What: "Delete the state (logs, dev builds, approvals; all of it without your settings kept)"},
	)
	for i := range out {
		if out[i].Base == "" {
			out[i].Base = filepath.Dir(out[i].Path)
		}
	}
	return out
}

// removeAxiomDir is os.RemoveAll behind its guard: path must be a folder
// called axiom sitting directly under base, and never $HOME or the root.
func removeAxiomDir(home, base, path string) error {
	path, base = filepath.Clean(path), filepath.Clean(base)
	switch {
	case path == "" || path == "." || path == "/" || base == "/" || base == ".":
		return axerr.New(axerr.Refused, "refusing to remove %q", path)
	case home != "" && path == filepath.Clean(home):
		return axerr.New(axerr.Refused, "refusing to remove the home folder")
	case filepath.Base(path) != "axiom" || filepath.Dir(path) != base:
		return axerr.New(axerr.Refused, "refusing to remove %s: not a folder called axiom directly under %s", path, base)
	}
	return os.RemoveAll(path)
}

// removeIn removes the entries of dir whose names keep says no to.
func removeIn(dir string, keep func(name string) bool) error {
	entries, err := os.ReadDir(dir)
	if errors.Is(err, fs.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	var first error
	for _, e := range entries {
		if keep(e.Name()) {
			continue
		}
		if err := os.RemoveAll(filepath.Join(dir, e.Name())); err != nil && first == nil {
			first = err
		}
	}
	return first
}

// 9. the folders
func (r *run) folders() {
	home := r.Getenv("HOME")
	rm := func(f folder) {
		if err := removeAxiomDir(home, f.Base, f.Path); err != nil {
			r.left("folders", f.What, f.Path, err.Error())
			return
		}
		r.done("folders", f.What, f.Path, "")
	}
	for _, f := range r.Options.folders() {
		if !exists(f.Path) {
			continue
		}
		switch f.Asks {
		case FieldKeepUserContent:
			if r.a.KeepUserContent {
				r.left("folders", "Keep the downloaded wallpapers and calendars", f.Path, "kept, as you chose")
				continue
			}
		case FieldKeepConfig:
			if r.a.KeepConfig {
				r.left("folders", "Keep the settings and saved setups", f.Path, "kept, as you chose")
				continue
			}
		}
		if f.Path == strings.TrimRight(r.Dirs.State, "/") {
			r.state(f)
			continue
		}
		rm(f)
	}
}

// state: the state folder. With the settings kept, only what axiom made
// beside them goes (the approvals, the session record, logs and dev
// builds, and the ledger once it's empty); otherwise all of it, but the
// ledger while it still has rows (a later `axiom footprint undo` finishes
// them). The saved passwords file goes unless they're kept.
func (r *run) state(f folder) {
	rows := 0
	if r.Ledger != nil {
		rows = len(r.Ledger.Rows())
	}
	secrets := r.a.KeepSecrets
	ledgerNames := map[string]bool{"footprint.json": true, "footprint.lock": true, "footprint": true}
	var err error
	switch {
	case r.a.KeepConfig:
		names := []string{filepath.Join("ui", "takeover.json"), "session.json", "session.lock", "log", "dev"}
		if rows == 0 {
			names = append(names, "footprint.json", "footprint.lock", "footprint")
		}
		if !r.a.KeepSecrets {
			names = append(names, "secrets.json")
		}
		for _, n := range names {
			if e := os.RemoveAll(filepath.Join(f.Path, n)); e != nil && err == nil {
				err = e
			}
		}
		if rows > 0 {
			// Only the prior values of what's left are kept
			err = firstErr(err, removeIn(filepath.Join(f.Path, "footprint"), func(n string) bool { return n == "prior" }))
		}
	default:
		err = removeIn(f.Path, func(n string) bool {
			return rows > 0 && ledgerNames[n] || secrets && n == "secrets.json"
		})
		if err == nil && rows > 0 {
			err = removeIn(filepath.Join(f.Path, "footprint"), func(n string) bool { return n == "prior" })
		}
		if err == nil {
			os.Remove(f.Path) // when nothing is kept
		}
	}
	if err != nil {
		r.left("folders", f.What, f.Path, err.Error())
		return
	}
	r.done("folders", f.What, f.Path, "")
}

func firstErr(a, b error) error {
	if a != nil {
		return a
	}
	return b
}

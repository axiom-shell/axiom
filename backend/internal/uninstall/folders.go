package uninstall

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/xdg"
)

// folder is one of axiom's own folders: what's done to it, and the answer
// that decides it ("": always).
type folder struct {
	Path, Kind, What, Asks string
	// Base is the folder it sits directly under (an XDG base, or the
	// runtime folder)
	Base string
}

// dataWhat names what the data folder holds: the user's own things.
const dataWhat = "Delete your notes, to-dos, themes, downloaded wallpapers and calendars"

// runtimeDir is the session's runtime folder: $XDG_RUNTIME_DIR, else
// /run/user/<uid> when that exists, "" when none can be found.
func (o Options) runtimeDir() string {
	if rt := o.Getenv("XDG_RUNTIME_DIR"); filepath.IsAbs(rt) {
		return filepath.Clean(rt)
	}
	base := o.RunUserDir
	if base == "" {
		base = "/run/user"
	}
	if rt := filepath.Join(base, strconv.Itoa(os.Getuid())); isDir(rt) {
		return rt
	}
	return ""
}

func isDir(p string) bool {
	info, err := os.Stat(p)
	return err == nil && info.IsDir()
}

// cacheBase is $XDG_CACHE_HOME, else ~/.cache (xdg.Resolve's rule).
func cacheBase(getenv func(string) string) string {
	if c := getenv("XDG_CACHE_HOME"); filepath.IsAbs(c) {
		return filepath.Clean(c)
	}
	return filepath.Join(getenv("HOME"), ".cache")
}

// folders are axiom's folders under the XDG bases, in the order they go.
func (o Options) folders() []folder {
	dir := func(p string) string { return strings.TrimRight(p, "/") }
	bases := xdg.ResolveBases(o.Getenv)
	out := []folder{{Path: dir(o.Dirs.Cache), Kind: "cache", What: "Delete the cache", Base: cacheBase(o.Getenv)}}
	if rt := o.runtimeDir(); rt != "" {
		out = append(out, folder{Path: filepath.Join(rt, "axiom"), Kind: "runtime", What: "Delete the runtime files", Base: rt})
	}
	return append(out,
		folder{Path: dir(o.Dirs.Data), Kind: "data", What: dataWhat, Asks: FieldKeepUserContent, Base: bases.Data},
		folder{Path: dir(o.Dirs.Config), Kind: "config", What: "Delete the settings and saved setups", Asks: FieldKeepConfig, Base: bases.Config},
		folder{Path: dir(o.Dirs.State), Kind: "state", What: "Delete the state (logs, dev builds, approvals; all of it without your settings kept)", Base: bases.State},
	)
}

// guard says whether f may be removed: absolute paths, a folder called axiom
// directly under the base it's named under, that base being the one the
// environment names for it, and never $HOME, a relative path or the root.
func (o Options) guard(f folder) error {
	path, base := filepath.Clean(f.Path), filepath.Clean(f.Base)
	home := o.Getenv("HOME")
	bases := xdg.ResolveBases(o.Getenv)
	known := map[string]string{"cache": cacheBase(o.Getenv), "data": bases.Data, "config": bases.Config, "state": bases.State, "runtime": o.runtimeDir()}
	switch {
	case !filepath.IsAbs(path) || !filepath.IsAbs(base) || !filepath.IsAbs(home):
		return axerr.New(axerr.Refused, "refusing %q: not an absolute path (is $HOME set?)", f.Path)
	case path == "/" || base == "/" || base == filepath.Clean(home):
		return axerr.New(axerr.Refused, "refusing to remove %s: it sits directly under the home folder or the root", f.Path)
	case filepath.Base(path) != "axiom" || filepath.Dir(path) != base:
		return axerr.New(axerr.Refused, "refusing to remove %s: not a folder called axiom directly under %s", f.Path, base)
	case known[f.Kind] == "" || filepath.Clean(known[f.Kind]) != base:
		return axerr.New(axerr.Refused, "refusing to remove %s: %s isn't the %s base the environment names", f.Path, base, f.Kind)
	}
	return nil
}

// removeAxiomDir is os.RemoveAll behind the guard. The runtime folder is
// removed display by display, and only when it's a private folder of this
// user's (never a link, never a mode wider than 0700).
func (o Options) removeAxiomDir(f folder) error {
	if err := o.guard(f); err != nil {
		return err
	}
	if f.Kind != "runtime" {
		return os.RemoveAll(f.Path)
	}
	info, err := os.Lstat(f.Path)
	if err != nil {
		return err
	}
	st, ok := info.Sys().(*syscall.Stat_t)
	if info.Mode()&fs.ModeSymlink != 0 || !info.IsDir() || !ok || int(st.Uid) != os.Geteuid() || info.Mode().Perm() != 0o700 {
		return axerr.New(axerr.Refused, "refusing to remove %s: not a private folder of this user's", f.Path)
	}
	entries, err := os.ReadDir(f.Path)
	if err != nil {
		return err
	}
	var first error
	for _, e := range entries {
		if e.IsDir() && e.Type()&fs.ModeSymlink == 0 {
			if err := os.RemoveAll(filepath.Join(f.Path, e.Name())); err != nil && first == nil {
				first = err
			}
		}
	}
	if first != nil {
		return first
	}
	return os.Remove(f.Path)
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
	for _, f := range r.Options.folders() {
		info, err := os.Lstat(f.Path)
		if err != nil {
			continue
		}
		// A link is followed nowhere: it's left, and said
		if info.Mode()&fs.ModeSymlink != 0 {
			to, _ := os.Readlink(f.Path)
			r.left("folders", f.What, f.Path, "a link to "+to+": left as it is")
			continue
		}
		switch f.Asks {
		case FieldKeepUserContent:
			if r.a.KeepUserContent {
				r.left("folders", "Keep your notes, to-dos, themes, downloaded wallpapers and calendars", f.Path, "kept, as you chose")
				continue
			}
		case FieldKeepConfig:
			if r.a.KeepConfig {
				r.left("folders", "Keep the settings and saved setups", f.Path, "kept, as you chose")
				continue
			}
		}
		if f.Kind == "state" {
			r.state(f)
			continue
		}
		if err := r.removeAxiomDir(f); err != nil {
			r.left("folders", f.What, f.Path, err.Error())
			continue
		}
		r.done("folders", f.What, f.Path, "")
	}
}

// state: the state folder. With the settings kept, only what axiom made
// beside them goes (the approvals, the session record, logs and dev
// builds, and the ledger once it's empty); otherwise all of it, but the
// ledger while it still has rows or can't be read (a later `axiom footprint
// undo` finishes them). The saved passwords file goes unless they're kept.
// What stays is said: it's done only when nothing is left.
func (r *run) state(f folder) {
	if err := r.guard(f); err != nil {
		r.left("folders", f.What, f.Path, err.Error())
		return
	}
	// The ledger stays unless it's known to be empty
	keepLedger := r.rows != 0 || !r.ledgerKnown
	ledgerName := func(n string) bool {
		return n == "footprint.json" || n == "footprint.lock" || n == "footprint" || strings.HasPrefix(n, "footprint.json.bad-")
	}
	var err error
	if r.a.KeepConfig {
		names := []string{filepath.Join("ui", "takeover.json"), "session.json", "session.lock", "log", "dev", "dev.json"}
		if !keepLedger {
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
		if keepLedger && r.ledgerKnown {
			err = errors.Join(err, removeIn(filepath.Join(f.Path, "footprint"), func(n string) bool { return n == "prior" }))
		}
		os.Remove(f.Path) // only if nothing else is in it
	} else {
		err = removeIn(f.Path, func(n string) bool {
			return keepLedger && ledgerName(n) || n == "secrets.json" && r.a.KeepSecrets
		})
		if err == nil && keepLedger && r.ledgerKnown {
			err = removeIn(filepath.Join(f.Path, "footprint"), func(n string) bool { return n == "prior" })
		}
		if err == nil {
			os.Remove(f.Path) // when nothing is kept
		}
	}
	// What's still there that it keeps for a reason, said
	if r.a.KeepSecrets && exists(filepath.Join(f.Path, "secrets.json")) {
		r.left("secrets", "Keep the saved passwords file", filepath.Join(f.Path, "secrets.json"), "kept, as you chose")
	}
	entries, _ := os.ReadDir(f.Path)
	for _, e := range entries {
		if ledgerName(e.Name()) {
			why := "kept: it still has changes to undo (axiom footprint undo)"
			if !r.ledgerKnown {
				why = "kept: it couldn't be read, so what it recorded is unknown"
			}
			r.left("folders", "Keep the record of axiom's changes", filepath.Join(f.Path, e.Name()), why)
		}
	}
	switch {
	case err != nil:
		r.left("folders", f.What, f.Path, err.Error())
	case !exists(f.Path):
		r.done("folders", f.What, f.Path, "")
	case r.a.KeepConfig:
		r.done("folders", "Delete what axiom keeps in the state folder beside your settings", f.Path, "")
	default:
		r.left("folders", f.What, f.Path, "some of it stays (listed above)")
	}
}

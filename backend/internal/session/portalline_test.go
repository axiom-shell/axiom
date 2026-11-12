package session

import (
	"github.com/axiom-shell/axiom/backend/internal/fsx"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func portalSetup(t *testing.T) (PortalEnv, Store) {
	dir := t.TempDir()
	data := filepath.Join(dir, "data")
	os.MkdirAll(filepath.Join(data, "xdg-desktop-portal/portals"), 0o755)
	os.WriteFile(filepath.Join(data, "xdg-desktop-portal/portals/axiom.portal"), nil, 0o644)
	return PortalEnv{Config: filepath.Join(dir, "config"), DataDirs: []string{data}}, Store{Path: filepath.Join(dir, "state/session.json")}
}

func TestPortalLineAddRemoveIsExact(t *testing.T) {
	for name, seed := range map[string]*string{
		"no file":               nil,
		"no section":            ptr("[other]\na=b\n"),
		"no section, blank end": ptr("[other]\na=b\n\n"),
		"gnome line commented":  ptr("[preferred]\ndefault=gtk\norg.freedesktop.impl.portal.ScreenCast=gnome\n\n[other]\nx=y\n"),
		"crlf":                  ptr("[preferred]\r\ndefault=gtk\r\n"),
		"user edits elsewhere":  ptr("# mine\n[preferred]\ndefault=gtk\n\n[z]\nk=v\n"),
		"empty file":            ptr(""),
	} {
		t.Run(name, func(t *testing.T) {
			env, store := portalSetup(t)
			if seed != nil {
				os.MkdirAll(filepath.Dir(env.Path()), 0o755)
				os.WriteFile(env.Path(), []byte(*seed), 0o600)
			}
			state, changed, err := env.Sync(store, "d", true)
			if err != nil || state != LineOn || !changed {
				t.Fatalf("Sync = %q %v %v", state, changed, err)
			}
			got, _ := os.ReadFile(env.Path())
			if !contains(string(got), PortalText) {
				t.Fatalf("no line: %q", got)
			}
			if seed != nil && *seed != "" {
				if info, _ := os.Stat(env.Path()); info.Mode().Perm() != 0o600 {
					t.Fatalf("mode %v", info.Mode())
				}
			}
			// again: nothing
			if _, changed, _ := env.Sync(store, "d", true); changed {
				t.Fatal("changed twice")
			}
			state, changed, err = env.Sync(store, "d", false)
			if err != nil || state != LineOff || !changed {
				t.Fatalf("off = %q %v %v", state, changed, err)
			}
			back, err := os.ReadFile(env.Path())
			switch {
			case seed == nil || *seed == "":
				if err == nil && len(back) > 0 {
					t.Fatalf("left %q", back)
				}
			case string(back) != *seed:
				t.Fatalf("got %q, want %q", back, *seed)
			}
			if len(store.Read().Lines) != 0 {
				t.Fatal("record not cleared")
			}
		})
	}
}

func TestPortalLineAlreadyGoneAndAdopted(t *testing.T) {
	env, store := portalSetup(t)
	os.MkdirAll(filepath.Dir(env.Path()), 0o755)
	seed := "[preferred]\n# axiom: org.freedesktop.impl.portal.ScreenCast=gnome\n" + PortalText + "\n"
	os.WriteFile(env.Path(), []byte(seed), 0o644)
	state, changed, err := env.Sync(store, "d", true)
	if err != nil || state != LineOn || changed {
		t.Fatalf("adopt = %q %v %v", state, changed, err)
	}
	st := store.Read()
	if len(st.Lines) != 1 || !st.Lines[0].Adopted || len(st.Lines[0].Commented) != 1 {
		t.Fatalf("record %+v", st.Lines)
	}
	// the user took it out meanwhile
	os.WriteFile(env.Path(), []byte("[preferred]\n"), 0o644)
	if changed, err := env.Remove(st.Lines[0]); err != nil || changed {
		t.Fatalf("already gone: %v %v", changed, err)
	}
	os.Remove(env.Path())
	if changed, err := env.Remove(st.Lines[0]); err != nil || changed {
		t.Fatalf("no file: %v %v", changed, err)
	}
}

func TestPortalLineLeavesALinkAlone(t *testing.T) {
	env, store := portalSetup(t)
	target := filepath.Join(t.TempDir(), "dotfiles-portals.conf")
	os.WriteFile(target, []byte("[preferred]\n"), 0o644)
	os.MkdirAll(filepath.Dir(env.Path()), 0o755)
	os.Symlink(target, env.Path())
	state, changed, err := env.Sync(store, "d", true)
	if state != LineLink || changed || err != nil {
		t.Fatalf("= %q %v %v", state, changed, err)
	}
	if data, _ := os.ReadFile(target); string(data) != "[preferred]\n" {
		t.Fatalf("link target changed: %q", data)
	}
	if len(store.Read().Lines) != 0 {
		t.Fatal("recorded a line it didn't add")
	}
}

func TestPortalLineMissingPortal(t *testing.T) {
	env, store := portalSetup(t)
	env.DataDirs = []string{t.TempDir()}
	if state, _, _ := env.Sync(store, "d", true); state != LineMissing {
		t.Fatalf("state %q", state)
	}
}

func ptr(s string) *string { return &s }

func contains(s, sub string) bool { return len(s) >= len(sub) && strings.Contains(s, sub) }

// another display's line in the same file keeps the file as it is
func TestPortalLineLeftWhileAnotherDisplayHasIt(t *testing.T) {
	env, store := portalSetup(t)
	env.Alive = func(string) bool { return true }
	if _, _, err := env.Sync(store, "d1", true); err != nil {
		t.Fatal(err)
	}
	store.Update(func(st *State) error {
		st.Lines = append(st.Lines, PortalLine{Display: "d2", Path: env.Path(), Line: PortalText})
		return nil
	})
	if _, changed, err := env.Sync(store, "d1", false); err != nil || changed {
		t.Fatalf("off while d2 has it: %v %v", changed, err)
	}
	if data, _ := os.ReadFile(env.Path()); !contains(string(data), PortalText) {
		t.Fatal("the line was taken out from under the other display")
	}
	if st := store.Read(); len(st.Lines) != 1 || st.Lines[0].Display != "d2" {
		t.Fatalf("record %+v", st.Lines)
	}
	// teardown does the same
	if _, _, err := env.Sync(store, "d1", true); err != nil {
		t.Fatal(err)
	}
	o := TeardownOptions{State: store, Portal: env, Scope: Scope{WaylandDisplay: "d1"}}
	if o.undoLines("d1") {
		t.Fatal("teardown changed a file another display has a line in")
	}
	if data, _ := os.ReadFile(env.Path()); !contains(string(data), PortalText) {
		t.Fatal("teardown took the line out from under the other display")
	}
}

// the record goes only once the line is out
func TestPortalLineRecordStaysWhenTheUndoFails(t *testing.T) {
	env, store := portalSetup(t)
	os.MkdirAll(filepath.Dir(env.Path()), 0o755)
	os.WriteFile(env.Path(), []byte("[preferred]\ndefault=gtk\n"), 0o644)
	env.Sync(store, "d", true)
	env.Write = func(string, []byte, os.FileMode) error { return os.ErrPermission }
	state, _, err := env.Sync(store, "d", false)
	if err == nil || state != LineOff {
		t.Fatalf("= %q %v", state, err)
	}
	if len(store.Read().Lines) != 1 {
		t.Fatal("the record was dropped with the line still in")
	}
}

// a display whose daemon is gone doesn't hold a file: its entry blocks no
// undo, and pruning takes its line out when no live display has one
func TestPortalLineDeadDisplayBlocksNothing(t *testing.T) {
	env, store := portalSetup(t)
	alive := map[string]bool{"d1": true, "d2": true}
	env.Alive = func(d string) bool { return alive[d] }
	env.Sync(store, "d1", true)
	store.Update(func(st *State) error {
		st.Lines = append(st.Lines, PortalLine{Display: "d2", Path: env.Path(), Line: PortalText})
		return nil
	})
	alive["d2"] = false
	if _, changed, err := env.Sync(store, "d1", false); err != nil || !changed {
		t.Fatalf("off with only a dead display's entry: %v %v", changed, err)
	}
	// pruning: d2's entry alone, d2 dead: the line goes
	env.Sync(store, "d1", true)
	store.Update(func(st *State) error {
		st.Lines = []PortalLine{{Display: "d2", Path: env.Path(), Line: PortalText}}
		return nil
	})
	if !env.Prune(store, "d1", nil) {
		t.Fatal("the dead display's line wasn't taken out")
	}
	if data, _ := os.ReadFile(env.Path()); contains(string(data), PortalText) || len(store.Read().Lines) != 0 {
		t.Fatalf("file %q, record %+v", data, store.Read().Lines)
	}
	// a live display holding the same file keeps it
	env.Sync(store, "d1", true)
	store.Update(func(st *State) error {
		st.Lines = []PortalLine{{Display: "d2", Path: env.Path(), Line: PortalText}, {Display: "d1", Path: env.Path(), Line: PortalText}}
		return nil
	})
	if env.Prune(store, "d3", nil) {
		t.Fatal("a file a live display has a line in was changed")
	}
	if len(store.Read().Lines) != 1 || store.Read().Lines[0].Display != "d1" {
		t.Fatalf("record %+v", store.Read().Lines)
	}
}

func TestDisplayAliveFollowsTheInstanceLock(t *testing.T) {
	rt := t.TempDir()
	os.MkdirAll(filepath.Join(rt, "axiom", "w1"), 0o755)
	if DisplayAlive(rt, "w1") {
		t.Fatal("alive without a lock")
	}
	l, err := fsx.TryLock(filepath.Join(rt, "axiom", "w1", "daemon.lock"))
	if err != nil {
		t.Fatal(err)
	}
	if !DisplayAlive(rt, "w1") {
		t.Fatal("a held lock isn't alive")
	}
	l.Release()
	if DisplayAlive(rt, "w1") {
		t.Fatal("a released lock is alive")
	}
}

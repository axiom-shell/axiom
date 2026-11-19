package xdg

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func env(m map[string]string) func(string) string { return func(k string) string { return m[k] } }

func TestResolveFollowsDataDirs(t *testing.T) {
	t.Parallel()
	d := Resolve(env(map[string]string{"HOME": "/home/u/", "XDG_CONFIG_HOME": "/cfg//", "XDG_STATE_HOME": "relative"}))
	want := Dirs{
		Config: "/cfg/axiom/", State: "/home/u/.local/state/axiom/", UI: "/home/u/.local/state/axiom/ui/",
		Data: "/home/u/.local/share/axiom/", Notes: "/home/u/.local/share/axiom/notes/",
		GeneratedThemes: "/home/u/.local/state/axiom/themes/", CommunityThemes: "/home/u/.local/share/axiom/themes/",
		Cache: "/home/u/.cache/axiom/",
	}
	if d != want {
		t.Errorf("got %+v", d)
	}
}

func TestSearchDirs(t *testing.T) {
	t.Parallel()
	got := SearchDirs(env(map[string]string{"HOME": "/h", "XDG_DATA_DIRS": "/a/:rel: /b:/a"}))
	if want := []string{"/h/.local/share", "/a", "/b"}; !reflect.DeepEqual(got, want) {
		t.Errorf("got %v", got)
	}
	if got := SearchDirs(env(map[string]string{"HOME": "/h"})); !reflect.DeepEqual(got, []string{"/h/.local/share", "/usr/local/share", "/usr/share"}) {
		t.Errorf("default %v", got)
	}
}

func TestDisplayName(t *testing.T) {
	t.Parallel()
	for in, want := range map[string]string{"wayland-1": "wayland-1", "/run/user/1000/wayland-0": "wayland-0", "": "", "..": "", "a b": "", "x/../y": "y"} {
		if got := DisplayName(in); got != want {
			t.Errorf("DisplayName(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestRuntimeIsPrivate(t *testing.T) {
	t.Parallel()
	rt := t.TempDir()
	e := env(map[string]string{"XDG_RUNTIME_DIR": rt, "WAYLAND_DISPLAY": "wayland-9"})
	r, err := ForDisplay(e, true)
	if err != nil {
		t.Fatal(err)
	}
	for _, dir := range []string{filepath.Join(rt, "axiom"), r.Dir} {
		info, _ := os.Stat(dir)
		if info.Mode().Perm() != 0o700 {
			t.Errorf("%s mode %o", dir, info.Mode().Perm())
		}
	}
	if !strings.HasSuffix(r.Socket(), "axiom/wayland-9/axiom.sock") {
		t.Errorf("socket %s", r.Socket())
	}
	if r.Root != filepath.Join(rt, "axiom") {
		t.Errorf("root %s", r.Root)
	}
}

func TestBasesCache(t *testing.T) {
	t.Parallel()
	if got := ResolveBases(env(map[string]string{"HOME": "/home/u", "XDG_CACHE_HOME": "/c/"})).Cache; got != "/c" {
		t.Errorf("set: %s", got)
	}
	if got := ResolveBases(env(map[string]string{"HOME": "/home/u"})).Cache; got != "/home/u/.cache" {
		t.Errorf("default: %s", got)
	}
}

func TestRuntimeRefusesSymlinkAndNarrowsMode(t *testing.T) {
	t.Parallel()
	rt := t.TempDir()
	elsewhere := t.TempDir()
	if err := os.Symlink(elsewhere, filepath.Join(rt, "axiom")); err != nil {
		t.Fatal(err)
	}
	if _, err := RuntimeRoot(env(map[string]string{"XDG_RUNTIME_DIR": rt}), true); err == nil || !strings.Contains(err.Error(), "symlink") {
		t.Errorf("a symlinked axiom/ was accepted: %v", err)
	}

	rt2 := t.TempDir()
	os.Mkdir(filepath.Join(rt2, "axiom"), 0o755)
	if _, err := RuntimeRoot(env(map[string]string{"XDG_RUNTIME_DIR": rt2}), true); err != nil {
		t.Fatal(err)
	}
	if info, _ := os.Stat(filepath.Join(rt2, "axiom")); info.Mode().Perm() != 0o700 {
		t.Errorf("mode not narrowed: %o", info.Mode().Perm())
	}
}

func TestRuntimeNeedsXDGRuntimeDir(t *testing.T) {
	t.Parallel()
	if _, err := RuntimeRoot(env(map[string]string{}), true); err == nil {
		t.Error("ran without $XDG_RUNTIME_DIR")
	}
	if _, err := ForDisplay(env(map[string]string{"XDG_RUNTIME_DIR": t.TempDir()}), true); err == nil {
		t.Error("ran without a display")
	}
}

func TestSocketPathMustFit(t *testing.T) {
	t.Parallel()
	long := filepath.Join(t.TempDir(), strings.Repeat("d", 90))
	os.Mkdir(long, 0o700)
	if _, err := ForDisplay(env(map[string]string{"XDG_RUNTIME_DIR": long, "WAYLAND_DISPLAY": "wayland-1"}), true); err == nil || !strings.Contains(err.Error(), "shorter") {
		t.Errorf("a socket path past sun_path was accepted: %v", err)
	}
}

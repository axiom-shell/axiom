package procinfo

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"strconv"
	"strings"
	"sync/atomic"
	"testing"
)

// fakeProc is a /proc-like temp folder.
type fakeProc struct {
	t           *testing.T
	root        string
	foreignDirs map[string]bool
}

func newFake(t *testing.T) *fakeProc {
	return &fakeProc{t: t, root: t.TempDir(), foreignDirs: map[string]bool{}}
}

func (f *fakeProc) add(pid, ppid int, start uint64, comm string, argv []string, exe string, env ...string) {
	f.t.Helper()
	dir := filepath.Join(f.root, strconv.Itoa(pid))
	if err := os.MkdirAll(dir, 0o755); err != nil {
		f.t.Fatal(err)
	}
	stat := fmt.Sprintf("%d (%s) S %d 1 1 0 -1 4194304 1 0 0 0 0 0 0 0 20 0 1 0 %d 1 1", pid, comm, ppid, start)
	files := map[string]string{
		"stat":    stat,
		"cmdline": strings.Join(argv, "\x00") + "\x00",
		"environ": strings.Join(env, "\x00") + "\x00",
	}
	for n, c := range files {
		if err := os.WriteFile(filepath.Join(dir, n), []byte(c), 0o644); err != nil {
			f.t.Fatal(err)
		}
	}
	link := filepath.Join(dir, "exe")
	os.Remove(link)
	if exe != "" {
		if err := os.Symlink(exe, link); err != nil {
			f.t.Fatal(err)
		}
	}
}

func (f *fakeProc) remove(pid int) { os.RemoveAll(filepath.Join(f.root, strconv.Itoa(pid))) }

func (f *fakeProc) foreign(pid int) { f.foreignDirs[filepath.Join(f.root, strconv.Itoa(pid))] = true }

func (f *fakeProc) reader() *Reader {
	return New(Options{Proc: f.root, Mine: func(dir string) bool { return !f.foreignDirs[dir] }})
}

func TestParseStat(t *testing.T) {
	t.Parallel()
	good := "42 (a b) (c) S 7 1 1 0 -1 0 0 0 0 0 0 0 0 0 20 0 1 0 999 1 1"
	cases := []struct {
		name, in string
		ok       bool
		comm     string
		ppid     int
		start    uint64
	}{
		{"parens and spaces", good, true, "a b) (c", 7, 999},
		{"short", "42 (x) S 7 1", false, "", 0, 0},
		{"bad start", strings.Replace(good, "999", "zz", 1), false, "", 0, 0},
	}
	for _, c := range cases {
		comm, ppid, start, ok := parseStat([]byte(c.in))
		if ok != c.ok || comm != c.comm || ppid != c.ppid || start != c.start {
			t.Errorf("%s: got %q %d %d %v", c.name, comm, ppid, start, ok)
		}
	}
}

func TestName(t *testing.T) {
	t.Parallel()
	cases := []struct{ name, comm, argv0, exe, want string }{
		{"argv0", "gnome-calculato", "/usr/bin/gnome-calculator", "", "gnome-calculator"},
		{"exe", "gnome-calculato", "calc", "gnome-calculator", "gnome-calculator"},
		{"neither", "gnome-calculato", "calc", "other", "gnome-calculato"},
		{"script", "lutris", "/usr/bin/python3", "python3", "lutris"},
		{"setproctitle", "gnome-calculato", "/usr/bin/gnome-calculator --token=abc", "", "gnome-calculato"},
		{"short", "foo", "/usr/bin/foobar", "foobar", "foo"},
	}
	for _, c := range cases {
		if got := name(c.comm, c.argv0, c.exe); got != c.want {
			t.Errorf("%s: %q, want %q", c.name, got, c.want)
		}
	}
}

func TestLookup(t *testing.T) {
	t.Parallel()
	t.Run("ancestors", func(t *testing.T) {
		f := newFake(t)
		f.add(1, 0, 1, "systemd", []string{"systemd"}, "")
		f.add(10, 1, 5, "shell", []string{"shell"}, "")
		f.add(20, 10, 6, "launcher", []string{"launcher"}, "")
		f.add(30, 20, 7, "game", []string{"game"}, "")
		p, ok := f.reader().Lookup(30)
		if !ok || p.Name != "game" || !reflect.DeepEqual(p.Ancestors, []string{"launcher", "shell", "systemd"}) {
			t.Fatalf("%+v %v", p, ok)
		}
		if p.Signals == nil || p.Bridge {
			t.Fatalf("%+v", p)
		}
	})
	t.Run("stops at a foreign process", func(t *testing.T) {
		f := newFake(t)
		f.add(10, 0, 1, "root", []string{"root"}, "")
		f.add(20, 10, 2, "mid", []string{"mid"}, "")
		f.add(30, 20, 3, "game", []string{"game"}, "")
		f.foreign(20)
		p, _ := f.reader().Lookup(30)
		if len(p.Ancestors) != 0 || p.Ancestors == nil {
			t.Fatalf("%+v", p)
		}
	})
	t.Run("stops at a missing parent", func(t *testing.T) {
		f := newFake(t)
		f.add(30, 20, 3, "game", []string{"game"}, "")
		p, ok := f.reader().Lookup(30)
		if !ok || len(p.Ancestors) != 0 {
			t.Fatalf("%+v", p)
		}
	})
	t.Run("stops at a parent started later", func(t *testing.T) {
		f := newFake(t)
		f.add(20, 0, 9, "reused", []string{"reused"}, "")
		f.add(30, 20, 3, "game", []string{"game"}, "")
		p, _ := f.reader().Lookup(30)
		if len(p.Ancestors) != 0 {
			t.Fatalf("%+v", p)
		}
	})
	t.Run("stops at a cycle", func(t *testing.T) {
		f := newFake(t)
		f.add(10, 11, 5, "a", []string{"a"}, "")
		f.add(11, 10, 4, "b", []string{"b"}, "")
		p, ok := f.reader().Lookup(10)
		if !ok || !reflect.DeepEqual(p.Ancestors, []string{"b"}) {
			t.Fatalf("%+v", p)
		}
	})
	t.Run("stops at 64 steps", func(t *testing.T) {
		f := newFake(t)
		for i := 1; i <= 100; i++ {
			f.add(i, i-1, uint64(i), "p"+strconv.Itoa(i), []string{"p"}, "")
		}
		p, _ := f.reader().Lookup(100)
		if len(p.Ancestors) != 64 {
			t.Fatalf("%d", len(p.Ancestors))
		}
	})
	t.Run("not ours, gone, no pid", func(t *testing.T) {
		f := newFake(t)
		f.add(30, 1, 3, "game", []string{"game"}, "")
		f.foreign(30)
		r := f.reader()
		for _, pid := range []int{30, 0, -1, 99} {
			if _, ok := r.Lookup(pid); ok {
				t.Errorf("pid %d", pid)
			}
		}
	})
	t.Run("bridges", func(t *testing.T) {
		f := newFake(t)
		f.add(1, 0, 1, "systemd", []string{"systemd"}, "")
		f.add(40, 1, 2, "xwayland-satell", []string{"/usr/bin/xwayland-satellite"}, "", "SteamAppId=5")
		f.add(41, 1, 2, "Xwayland", []string{"Xwayland"}, "")
		for _, pid := range []int{40, 41} {
			p, ok := f.reader().Lookup(pid)
			if !ok || !p.Bridge || p.Name != "" || p.Ancestors == nil || len(p.Ancestors) != 0 || p.Signals == nil || len(p.Signals) != 0 {
				t.Errorf("%d: %+v", pid, p)
			}
		}
	})
}

func TestCacheByStart(t *testing.T) {
	t.Parallel()
	f := newFake(t)
	f.add(10, 0, 1, "parent", []string{"parent"}, "")
	f.add(20, 10, 2, "old", []string{"old"}, "")
	f.add(21, 10, 3, "other", []string{"other"}, "")
	r := f.reader()
	if p, _ := r.Lookup(20); p.Name != "old" {
		t.Fatal(p)
	}
	f.add(20, 10, 2, "old", []string{"changed"}, "")
	if p, _ := r.Lookup(20); p.Name != "old" {
		t.Fatalf("not cached: %+v", p)
	}
	f.add(20, 10, 2, "exec", []string{"exec"}, "")
	if p, _ := r.Lookup(20); p.Name != "exec" {
		t.Fatalf("exec (same pid and start, new comm) kept: %+v", p)
	}
	f.add(20, 10, 4, "new", []string{"new"}, "")
	if p, _ := r.Lookup(20); p.Name != "new" {
		t.Fatalf("reused pid kept: %+v", p)
	}
	// the parent's node is read once for both windows
	f.add(10, 0, 1, "parent", []string{"changed"}, "")
	if p, _ := r.Lookup(21); !reflect.DeepEqual(p.Ancestors, []string{"parent"}) {
		t.Fatalf("parent node re-read: %+v", p)
	}
	f.remove(20)
	if _, ok := r.Lookup(20); ok {
		t.Fatal("removed")
	}
}

func TestMineCalls(t *testing.T) {
	t.Parallel()
	f := newFake(t)
	f.add(10, 0, 1, "p", []string{"p"}, "")
	f.add(20, 10, 2, "w", []string{"w"}, "")
	var n atomic.Int32
	r := New(Options{Proc: f.root, Mine: func(string) bool { n.Add(1); return true }})
	r.Lookup(20)
	got := n.Load()
	r.Lookup(20)
	if n.Load() != got {
		t.Fatal("a cached lookup checked ownership again")
	}
}

func TestPrune(t *testing.T) {
	t.Parallel()
	f := newFake(t)
	r := f.reader()
	for i := 1000; i < 1600; i++ {
		f.add(i, 0, uint64(i), "w", []string{"w"}, "")
		r.Lookup(i)
	}
	for i := 1000; i < 1590; i++ {
		f.remove(i)
	}
	f.add(2000, 0, 5, "w", []string{"w"}, "")
	r.Lookup(2000)
	if len(r.procs) > 512 || len(r.nodes) > 512 {
		t.Fatalf("%d %d", len(r.procs), len(r.nodes))
	}
	if _, ok := r.procs[1599]; !ok {
		t.Fatal("a live process was dropped")
	}
}

func TestNothingLeaks(t *testing.T) {
	t.Parallel()
	f := newFake(t)
	f.add(10, 0, 1, "reaper", []string{"reaper", "SteamLaunch", "AppId=SECRETAPP", "--", "game"}, "")
	f.add(20, 10, 2, "game", []string{"game", "--password", "SECRETARG"}, "", "SteamAppId=SECRETENV", "TOKEN=SECRETTOKEN")
	r := f.reader()
	p, ok := r.Lookup(20)
	if !ok || !reflect.DeepEqual(p.Signals, []Signal{SignalSteam}) {
		t.Fatalf("%+v", p)
	}
	b, _ := json.Marshal(p)
	for _, s := range []string{string(b), fmt.Sprintf("%+v", r.procs), fmt.Sprintf("%+v", r.nodes)} {
		if strings.Contains(s, "SECRET") {
			t.Fatalf("leak: %s", s)
		}
	}
}

func TestRealProc(t *testing.T) {
	t.Parallel()
	if _, err := os.Stat("/proc/self/stat"); err != nil {
		t.Skip("no /proc")
	}
	r := New(Options{})
	if p, ok := r.Lookup(os.Getpid()); !ok || p.Name == "" {
		t.Fatalf("%+v %v", p, ok)
	}
	if _, ok := r.Lookup(0); ok {
		t.Fatal("pid 0")
	}
}

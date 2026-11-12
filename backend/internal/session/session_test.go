package session

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"testing"
)

// fakeProc writes a /proc-like folder holding processes
type fakeProc struct {
	t    *testing.T
	root string
}

func newProc(t *testing.T) *fakeProc { return &fakeProc{t: t, root: t.TempDir()} }

func (p *fakeProc) add(pid int, argv []string, env ...string) {
	p.t.Helper()
	dir := filepath.Join(p.root, strconv.Itoa(pid))
	if err := os.MkdirAll(dir, 0o755); err != nil {
		p.t.Fatal(err)
	}
	os.WriteFile(filepath.Join(dir, "cmdline"), []byte(strings.Join(argv, "\x00")+"\x00"), 0o644)
	os.WriteFile(filepath.Join(dir, "environ"), []byte(strings.Join(env, "\x00")+"\x00"), 0o644)
	os.WriteFile(filepath.Join(dir, "stat"), []byte(strconv.Itoa(pid)+" (a b) S 1 1 1 0 -1 0 0 0 0 0 0 0 0 0 20 0 1 0 "+strconv.Itoa(pid*10)+" 0 0\n"), 0o644)
	os.Symlink("/work", filepath.Join(dir, "cwd"))
}

func (p *fakeProc) scope() Scope {
	return Scope{WaylandDisplay: "wayland-1", RuntimeDir: "/run/u", Bus: "unix:path=/run/u/bus", ProcRoot: p.root}
}

var inScope = []string{"WAYLAND_DISPLAY=wayland-1", "XDG_RUNTIME_DIR=/run/u", "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/u/bus"}

type fakeBus struct {
	owners map[string]uint32 // name -> pid
}

func (b fakeBus) NameOwner(_ context.Context, name string) (string, error) {
	if _, ok := b.owners[name]; ok {
		return ":1.1", nil
	}
	return "", errors.New("no owner")
}

func (b fakeBus) ConnectionPID(_ context.Context, name string) (uint32, error) {
	if pid, ok := b.owners[name]; ok {
		return pid, nil
	}
	return 0, errors.New("no owner")
}

// calls records what the seams were asked, in order
type calls struct {
	mu   sync.Mutex
	list []string
	// out answers systemctl by its first args
	out map[string]string
}

func (c *calls) add(s string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.list = append(c.list, s)
}

func (c *calls) seams() Seams {
	return Seams{
		Systemctl: func(_ context.Context, args ...string) (string, error) {
			c.add("systemctl " + strings.Join(args, " "))
			return c.out[strings.Join(args, " ")], nil
		},
		Spawn: func(_ context.Context, argv, env []string, cwd string) error {
			c.add("spawn " + strings.Join(argv, " ") + " in " + cwd)
			return nil
		},
		Signal: func(pid int, sig syscall.Signal) error {
			c.add("signal " + strconv.Itoa(pid) + " " + strconv.Itoa(int(sig)))
			return nil
		},
	}
}

func (c *calls) got() string { c.mu.Lock(); defer c.mu.Unlock(); return strings.Join(c.list, "\n") }

func TestRuntimeRecordUnknownVersionIsLeftAlone(t *testing.T) {
	path := filepath.Join(t.TempDir(), "session.json")
	os.WriteFile(path, []byte(`{"version":99,"daemonPid":5}`), 0o600)
	var logged []string
	if r := ReadRuntime(path, func(f string, a ...any) { logged = append(logged, f) }); r != nil {
		t.Fatalf("read a record of another version: %+v", r)
	}
	if len(logged) != 1 {
		t.Fatalf("logged %v, want one line", logged)
	}
	st := Store{Path: filepath.Join(t.TempDir(), "session.json")}
	os.WriteFile(st.Path, []byte(`{"version":2}`), 0o600)
	if st.Read() != nil {
		t.Fatal("read a state of another version")
	}
	if err := st.Update(func(*State) error { return nil }); err == nil {
		t.Fatal("updated a state of another version")
	}
	if data, _ := os.ReadFile(st.Path); string(data) != `{"version":2}` {
		t.Fatalf("the record was rewritten: %s", data)
	}
}

func TestStateRecordWriteAheadSurvivesACrashBeforeConfirm(t *testing.T) {
	dir := t.TempDir()
	store := Store{Path: filepath.Join(dir, "state", "session.json")}
	cfg := filepath.Join(dir, "config")
	data := filepath.Join(dir, "data")
	os.MkdirAll(filepath.Join(data, "xdg-desktop-portal/portals"), 0o755)
	os.WriteFile(filepath.Join(data, "xdg-desktop-portal/portals/axiom.portal"), nil, 0o644)
	failed := errors.New("crash")
	env := PortalEnv{Config: cfg, DataDirs: []string{data}, Write: func(string, []byte, os.FileMode) error { return failed }}
	// The record holds the entry before the file is written: a crash
	// there (here the write failing, and the cleanup after it also
	// missing) leaves it
	env.Write = func(path string, b []byte, m os.FileMode) error {
		st := store.Read()
		if len(st.Lines) != 1 || st.Lines[0].Line != PortalText {
			t.Errorf("the record at the write: %+v", st)
		}
		return failed
	}
	if state, _, err := env.Sync(store, "wayland-1", true); err == nil || state != LineFailed {
		t.Fatalf("Sync = %q, %v", state, err)
	}
	// Planned and written, then the process died: the next start's undo
	// finds the planned entry and the file
	env.Write = nil
	if _, _, err := env.Sync(store, "wayland-1", true); err != nil {
		t.Fatal(err)
	}
	st := store.Read()
	if len(st.Lines) != 1 {
		t.Fatalf("lines: %+v", st.Lines)
	}
	changed, err := env.Remove(st.Lines[0])
	if err != nil || !changed {
		t.Fatalf("Remove = %v, %v", changed, err)
	}
	if _, err := os.Stat(env.Path()); err == nil {
		t.Fatal("the file axiom made is still there")
	}
}

func TestScopeMatchesOnlyThisSession(t *testing.T) {
	p := newProc(t)
	p.add(10, []string{"/usr/bin/soteria"}, inScope...)
	p.add(11, []string{"/usr/bin/soteria"}, "WAYLAND_DISPLAY=wayland-2", "XDG_RUNTIME_DIR=/run/u")
	p.add(12, []string{"/usr/bin/soteria"}, "XDG_RUNTIME_DIR=/run/u")
	p.add(13, []string{"/usr/bin/soteria"}, "WAYLAND_DISPLAY=wayland-1", "XDG_RUNTIME_DIR=/run/u", "DBUS_SESSION_BUS_ADDRESS=unix:path=/tmp/other")
	s := p.scope()
	found := s.Find(regexp.MustCompile(`soteria`))
	if len(found) != 1 || found[0].PID != 10 {
		t.Fatalf("found %+v, want only pid 10", found)
	}
	if found[0].Start != 100 || found[0].Cwd != "/work" || found[0].Argv[0] != "/usr/bin/soteria" {
		t.Fatalf("found %+v", found[0])
	}
	if s.Owns(11) || s.Owns(12) || s.Owns(13) || !s.Owns(10) {
		t.Fatal("Owns disagrees with Find")
	}
}

// the QML pattern (PolkitAgents.processPattern)
var agentPattern = regexp.MustCompile(`^([^ ]*/)?(hyprpolkitagent|soteria|lxpolkit)( |$)`)

func TestPatternMatchesLikePgrepF(t *testing.T) {
	for line, want := range map[string]bool{
		"/usr/lib/hyprpolkitagent":              true,
		"soteria":                               true,
		"soteria --flag":                        true,
		"lxpolkit":                              true,
		"vim /home/me/soteria":                  false,
		"vim soteria":                           false,
		"/usr/bin/python /opt/soteria-notes.py": false,
		"soteria-helper":                        false,
	} {
		p := newProc(t)
		p.add(20, strings.Fields(line), inScope...)
		got := len(p.scope().Find(agentPattern)) == 1
		if got != want {
			t.Errorf("%q: matched = %v, want %v", line, got, want)
		}
	}
}

func baseOpts(t *testing.T, c *calls, p *fakeProc) TeardownOptions {
	dir := t.TempDir()
	return TeardownOptions{
		Runtime:     &Runtime{DaemonPID: 1, Stopped: []Process{{Kind: "polkit", Argv: []string{"/usr/lib/hyprpolkitagent"}, Env: []string{"A=b"}, Cwd: "/home"}}},
		RuntimePath: filepath.Join(dir, "session.json"),
		State:       Store{Path: filepath.Join(dir, "state", "session.json")},
		Scope:       p.scope(), CompositorAlive: true, SameInstance: true, Compositor: true,
		Seams:  c.seams(),
		Portal: PortalEnv{Config: filepath.Join(dir, "config")},
	}
}

func TestTeardownOrder(t *testing.T) {
	p := newProc(t)
	p.add(30, []string{"wlsunset", "-t", "4000"}, append([]string{Marker("wayland-1")}, inScope...)...)
	c := &calls{}
	o := baseOpts(t, c, p)
	o.Bus = fakeBus{owners: map[string]uint32{systemd: 1, portalBus: 77}}
	o.State.Update(func(st *State) error {
		st.Units = []Unit{{Name: "hyprpolkitagent.service", Display: "wayland-1"}, {Name: "other.service", Display: "wayland-2"}}
		return nil
	})
	o.Runtime.Compositor.Kind = "none"
	if err := Teardown(context.Background(), o); err != nil {
		t.Fatal(err)
	}
	want := "signal 30 15\nspawn /usr/lib/hyprpolkitagent in /home\nsystemctl start hyprpolkitagent.service"
	if got := c.got(); got != want {
		t.Fatalf("calls:\n%s\nwant:\n%s", got, want)
	}
	st := o.State.Read()
	if len(st.Units) != 1 || st.Units[0].Display != "wayland-2" {
		t.Fatalf("units left: %+v", st.Units)
	}
	if rec := ReadRuntime(o.RuntimePath, nil); rec == nil || !rec.Clean || len(rec.Stopped) != 0 {
		t.Fatalf("record: %+v", rec)
	}
}

func TestTeardownWithoutCompositorOnlyEditsFiles(t *testing.T) {
	p := newProc(t)
	p.add(30, []string{"wlsunset"}, append([]string{Marker("wayland-1")}, inScope...)...)
	c := &calls{}
	o := baseOpts(t, c, p)
	o.CompositorAlive = false
	o.Bus = fakeBus{owners: map[string]uint32{systemd: 1}}
	o.State.Update(func(st *State) error {
		st.Units = []Unit{{Name: "x.service", Display: "wayland-1"}}
		st.Lines = []PortalLine{{Display: "wayland-1", Path: filepath.Join(o.Portal.Config, PortalFile), Line: PortalText, CreatedFile: true, CreatedSection: true}}
		return nil
	})
	os.MkdirAll(filepath.Join(o.Portal.Config, "xdg-desktop-portal"), 0o755)
	os.WriteFile(filepath.Join(o.Portal.Config, PortalFile), []byte("[preferred]\n"+PortalText+"\n"), 0o644)
	restarted := false
	o.RestartPortal = func(context.Context) error { restarted = true; return nil }
	if err := Teardown(context.Background(), o); err != nil {
		t.Fatal(err)
	}
	if got := c.got(); got != "signal 30 15" {
		t.Fatalf("calls: %q: only wlsunset's end is a process effect", got)
	}
	if restarted {
		t.Fatal("restarted the portal without a compositor")
	}
	if _, err := os.Stat(filepath.Join(o.Portal.Config, PortalFile)); err == nil {
		t.Fatal("the line's file wasn't undone")
	}
	if len(o.State.Read().Units) != 1 {
		t.Fatal("units must stay for the next start's heal")
	}
}

func TestTeardownRespawnsOnlyOnTheSameInstance(t *testing.T) {
	p := newProc(t)
	c := &calls{}
	o := baseOpts(t, c, p)
	o.SameInstance = false
	if err := Teardown(context.Background(), o); err != nil {
		t.Fatal(err)
	}
	if got := c.got(); got != "" {
		t.Fatalf("respawned for another instance: %q", got)
	}
}

func TestRespawnSkipsAnAgentAlreadyRunning(t *testing.T) {
	p := newProc(t)
	p.add(40, []string{"/usr/bin/hyprpolkitagent"}, inScope...)
	c := &calls{}
	o := baseOpts(t, c, p)
	if err := Teardown(context.Background(), o); err != nil {
		t.Fatal(err)
	}
	if got := c.got(); got != "" {
		t.Fatalf("started a second agent: %q", got)
	}
}

func TestUnitsSkippedWithoutTheUserManagersBus(t *testing.T) {
	p := newProc(t)
	c := &calls{}
	o := baseOpts(t, c, p)
	o.Bus = fakeBus{owners: map[string]uint32{}}
	o.State.Update(func(st *State) error {
		st.Units = []Unit{{Name: "x.service", Display: "wayland-1"}}
		return nil
	})
	var logged []string
	o.Log = func(f string, a ...any) { logged = append(logged, f) }
	Teardown(context.Background(), o)
	if strings.Contains(c.got(), "systemctl") {
		t.Fatalf("systemctl ran: %q", c.got())
	}
	if len(o.State.Read().Units) != 1 {
		t.Fatal("the unit was dropped")
	}
	if !strings.Contains(strings.Join(logged, "\n"), "left units alone") {
		t.Fatalf("not logged: %v", logged)
	}
}

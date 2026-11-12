package daemon

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
	"github.com/axiom-shell/axiom/backend/internal/screenshare"
	sessx "github.com/axiom-shell/axiom/backend/internal/session"
)

// fakeBus is the session bus: its owners by name, with their pids
type fakeBus map[string]uint32

func (b fakeBus) NameOwner(_ context.Context, name string) (string, error) {
	if _, ok := b[name]; ok {
		return ":1.1", nil
	}
	return "", errors.New("no owner")
}

func (b fakeBus) ConnectionPID(_ context.Context, name string) (uint32, error) {
	if pid, ok := b[name]; ok {
		return pid, nil
	}
	return 0, errors.New("no owner")
}

// effects records what a daemon asked of the session, in order
type effects struct {
	mu   sync.Mutex
	list []string
	proc string
}

func (e *effects) add(s string) { e.mu.Lock(); e.list = append(e.list, s); e.mu.Unlock() }
func (e *effects) got() string  { e.mu.Lock(); defer e.mu.Unlock(); return strings.Join(e.list, "\n") }

func (e *effects) seams(before func(call string)) sessx.Seams {
	note := func(s string) {
		if before != nil {
			before(s)
		}
		e.add(s)
	}
	return sessx.Seams{
		Systemctl: func(_ context.Context, args ...string) (string, error) {
			note("systemctl " + strings.Join(args, " "))
			return "", nil
		},
		Spawn: func(_ context.Context, argv, env []string, cwd string) error {
			marker := ""
			for _, v := range env {
				if strings.HasPrefix(v, "AXIOM_SPAWNED=") {
					marker = " [" + v + "]"
				}
			}
			note("spawn " + strings.Join(argv, " ") + marker)
			return nil
		},
		SpawnTo: func(_ context.Context, argv, _ []string, _, output string) error {
			note("spawn " + strings.Join(argv, " ") + " >" + output)
			return nil
		},
		Signal: func(pid int, sig syscall.Signal) error {
			note("signal " + strconv.Itoa(pid))
			// the process ends
			os.RemoveAll(filepath.Join(e.proc, strconv.Itoa(pid)))
			return nil
		},
	}
}

func addProc(t *testing.T, root string, pid int, argv []string, env ...string) {
	t.Helper()
	dir := filepath.Join(root, strconv.Itoa(pid))
	os.MkdirAll(dir, 0o755)
	os.WriteFile(filepath.Join(dir, "cmdline"), []byte(strings.Join(argv, "\x00")+"\x00"), 0o644)
	os.WriteFile(filepath.Join(dir, "environ"), []byte(strings.Join(env, "\x00")+"\x00"), 0o644)
	os.WriteFile(filepath.Join(dir, "stat"), []byte(strconv.Itoa(pid)+" (x) S 1 1 1 0 -1 0 0 0 0 0 0 0 0 0 20 0 1 0 "+strconv.Itoa(pid*10)+" 0 0\n"), 0o644)
}

// sessionDaemon is a daemon's session parts on scratch folders, nothing
// real behind them: a /proc fixture, seams, a bus.
type sessionDaemon struct {
	d     *Daemon
	td    *testDaemon
	fx    *effects
	proc  string
	bus   fakeBus
	scope []string // the environment an in-scope process has
}

func newSessionDaemon(t *testing.T, guard bool) *sessionDaemon {
	t.Helper()
	td := newTestDaemon(t)
	sd := &sessionDaemon{td: td, fx: &effects{proc: t.TempDir()}, bus: fakeBus{}}
	sd.proc = sd.fx.proc
	sd.scope = []string{"WAYLAND_DISPLAY=wayland-test", "XDG_RUNTIME_DIR=" + td.env["XDG_RUNTIME_DIR"]}
	d := &Daemon{runtime: td.runtime, dirs: td.dirs}
	d.opts = Options{Getenv: td.getenv, Log: slog.New(slog.NewTextHandler(io.Discard, nil)), Guard: guard}
	d.opts.session = &sessionTest{Seams: sd.fx.seams(nil), ProcRoot: sd.proc, Bus: sd.bus}
	d.sess = &sessionRec{path: td.runtime.File(sessx.RuntimeFile), log: d.sessionLog}
	d.sess.rec = sessx.Runtime{Instance: ":", DaemonPID: os.Getpid()}
	sd.d = d
	return sd
}

func (sd *sessionDaemon) record() *sessx.Runtime {
	return sessx.ReadRuntime(sd.td.runtime.File(sessx.RuntimeFile), nil)
}

func (sd *sessionDaemon) state() *sessx.State { return sd.d.sessionStore().Read() }

var agents = regexp.MustCompile(`^([^ ]*/)?(hyprpolkitagent|soteria)( |$)`)

func TestCompositorGoneSkipsCompositorTeardown(t *testing.T) {
	for _, gone := range []bool{false, true} {
		sd := newSessionDaemon(t, false)
		sd.bus[systemdName] = 1
		sd.d.compositorGone.Store(gone)
		compositorTold := false
		sd.d.opts.session.CompositorTeardown = func(context.Context) { compositorTold = true }
		sd.d.sess.rec.Stopped = []sessx.Process{{Kind: "polkit", Argv: []string{"/usr/bin/soteria"}}}
		sd.d.sessionStore().Update(func(st *sessx.State) error {
			st.Units = []sessx.Unit{{Name: "a.service", Display: "wayland-test"}}
			return nil
		})
		sd.d.sessionTeardown()
		if compositorTold == gone {
			t.Fatalf("gone=%v: the manager's teardown ran = %v", gone, compositorTold)
		}
		got := sd.fx.got()
		if gone && got != "" {
			t.Fatalf("a gone compositor: %q (only files and wlsunset are undone)", got)
		}
		if !gone && got != "spawn /usr/bin/soteria\nsystemctl start a.service" {
			t.Fatalf("calls: %q", got)
		}
		if rec := sd.record(); rec == nil || !rec.Clean {
			t.Fatalf("record %+v", rec)
		}
	}
}

const systemdName = "org.freedesktop.systemd1"

func TestGuardNotSpawnedWithoutTheOption(t *testing.T) {
	sd := newSessionDaemon(t, false)
	started := 0
	sd.d.opts.session.StartGuard = func() error { started++; return nil }
	sd.d.startSession(nil)
	if started != 0 {
		t.Fatal("the guard started without Options.Guard")
	}
	if _, err := os.Stat(sd.td.runtime.File(sessx.GuardLock)); err == nil {
		t.Fatal("touched guard.lock")
	}
	if rec := sd.record(); rec == nil || rec.DaemonPID != os.Getpid() || rec.Clean {
		t.Fatalf("record %+v", rec)
	}
}

func TestCarriedImageKeepsItsGuard(t *testing.T) {
	sd := newSessionDaemon(t, true)
	started := 0
	sd.d.opts.session.StartGuard = func() error { started++; return nil }
	rec := sessx.Runtime{Instance: ":", DaemonPID: os.Getpid(), GuardPID: 4242, Stopped: []sessx.Process{{Kind: "polkit", Argv: []string{"x"}}}}
	rec.Write(sd.td.runtime.File(sessx.RuntimeFile))
	lock, err := fsx.TryLock(sd.td.runtime.File(sessx.GuardLock))
	if err != nil {
		t.Fatal(err)
	}
	sd.d.startSession(&handoff{})
	if started != 0 {
		t.Fatal("started a second guard beside a live one")
	}
	if got := sd.record(); got.GuardPID != 4242 || len(got.Stopped) != 1 {
		t.Fatalf("the carried record was changed: %+v", got)
	}
	// the guard died: a new one
	lock.Release()
	sd.d.startSession(&handoff{})
	if started != 1 {
		t.Fatalf("guards started: %d", started)
	}
}

func TestFreshImageWaitsForAnotherGuardThenHeals(t *testing.T) {
	sd := newSessionDaemon(t, true)
	sd.bus[systemdName] = 1
	started := 0
	sd.d.opts.session.StartGuard = func() error {
		started++
		sd.fx.add("guard")
		return nil
	}
	old := sessx.Runtime{Instance: ":", DaemonPID: 99999, Stopped: []sessx.Process{{Kind: "polkit", Argv: []string{"/usr/bin/hyprpolkitagent"}}}}
	old.Write(sd.td.runtime.File(sessx.RuntimeFile))
	sd.d.sessionStore().Update(func(st *sessx.State) error {
		st.Units = []sessx.Unit{{Name: "hyprpolkitagent.service", Display: "wayland-test"}}
		return nil
	})
	lock, err := fsx.TryLock(sd.td.runtime.File(sessx.GuardLock))
	if err != nil {
		t.Fatal(err)
	}
	go func() {
		time.Sleep(300 * time.Millisecond)
		sd.fx.add("guard done")
		lock.Release()
	}()
	begin := time.Now()
	sd.d.startSession(nil)
	if time.Since(begin) < 250*time.Millisecond {
		t.Fatal("didn't wait for the old guard")
	}
	want := "guard done\nspawn /usr/bin/hyprpolkitagent\nsystemctl start hyprpolkitagent.service\nguard"
	if got := sd.fx.got(); got != want {
		t.Fatalf("order:\n%s\nwant:\n%s", got, want)
	}
	if rec := sd.record(); rec.Clean || len(rec.Stopped) != 0 || rec.DaemonPID != os.Getpid() {
		t.Fatalf("new record %+v", rec)
	}
	if len(sd.state().Units) != 0 {
		t.Fatal("the unit is still recorded")
	}
}

func TestPolkitStopRecordsBeforeStopping(t *testing.T) {
	sd := newSessionDaemon(t, false)
	sd.bus[systemdName] = 1
	addProc(t, sd.proc, 500, []string{"/usr/lib/hyprpolkitagent"}, append(sd.scope, "A=b")...)
	check := func(call string) {
		switch {
		case strings.HasPrefix(call, "systemctl stop"):
			if st := sd.state(); len(st.Units) != 1 || st.Units[0].Name != "hyprpolkitagent.service" || st.Units[0].Display != "wayland-test" {
				t.Errorf("the unit wasn't recorded before it was stopped: %+v", st)
			}
		case call == "signal 500":
			if rec := sd.record(); rec == nil || len(rec.Stopped) != 1 || rec.Stopped[0].PID != 500 || rec.Stopped[0].Kind != "polkit" ||
				rec.Stopped[0].Argv[0] != "/usr/lib/hyprpolkitagent" || rec.Stopped[0].Cwd != "" && false {
				t.Errorf("the process wasn't recorded before the signal: %+v", rec)
			}
		}
	}
	sd.d.opts.session.Seams = sd.fx.seams(check)
	res := sd.d.stopOthers(context.Background(), agents, []string{"hyprpolkitagent.service"})
	if len(res.Units) != 1 || len(res.Names) != 1 || res.Names[0] != "hyprpolkitagent" {
		t.Fatalf("result %+v", res)
	}
	want := "systemctl -q is-active hyprpolkitagent.service\nsystemctl stop hyprpolkitagent.service\nsignal 500"
	if got := sd.fx.got(); got != want {
		t.Fatalf("calls:\n%s", got)
	}
	if rec := sd.record(); len(rec.Stopped[0].Env) == 0 {
		t.Fatalf("env not recorded: %+v", rec.Stopped)
	}
}

func TestPolkitOutOfScopeLeftAlone(t *testing.T) {
	sd := newSessionDaemon(t, false)
	addProc(t, sd.proc, 600, []string{"/usr/bin/soteria"}, "WAYLAND_DISPLAY=wayland-other", "XDG_RUNTIME_DIR="+sd.td.env["XDG_RUNTIME_DIR"])
	addProc(t, sd.proc, 601, []string{"/usr/bin/soteria"}, sd.scope...)
	// no systemd on this bus: units are left alone, whatever the shell says
	res := sd.d.stopOthers(context.Background(), agents, []string{"x.service"})
	if got := sd.fx.got(); got != "signal 601" {
		t.Fatalf("calls: %q", got)
	}
	if len(res.Units) != 0 || len(sd.state().Units) != 0 {
		t.Fatalf("units: %+v", res)
	}
	if _, err := os.Stat(filepath.Join(sd.proc, "600")); err != nil {
		t.Fatal("the other session's agent was touched")
	}
}

func TestPolkitHandBack(t *testing.T) {
	sd := newSessionDaemon(t, false)
	sd.bus[systemdName] = 1
	sd.d.sess.rec.Stopped = []sessx.Process{
		{Kind: "polkit", Argv: []string{"/usr/bin/soteria"}},
		{Kind: "wlsunset", Argv: []string{"wlsunset"}},
	}
	sd.d.sessionStore().Update(func(st *sessx.State) error {
		st.Units = []sessx.Unit{{Name: "p.service", Display: "wayland-test"}}
		return nil
	})
	sd.d.handBack(context.Background())
	want := "systemctl start p.service\nspawn /usr/bin/soteria"
	got := sd.fx.got()
	if !strings.Contains(got, "systemctl start p.service") || !strings.Contains(got, "spawn /usr/bin/soteria") || strings.Contains(got, "wlsunset") {
		t.Fatalf("calls %q, want %q (polkit only)", got, want)
	}
	if rec := sd.record(); len(rec.Stopped) != 1 || rec.Stopped[0].Kind != "wlsunset" {
		t.Fatalf("record %+v", rec.Stopped)
	}
	if len(sd.state().Units) != 0 {
		t.Fatal("unit still recorded")
	}
}

func TestWlsunsetTheirsRecordedOursMarked(t *testing.T) {
	sd := newSessionDaemon(t, false)
	addProc(t, sd.proc, 700, []string{"wlsunset", "-t", "3000"}, sd.scope...)
	addProc(t, sd.proc, 701, []string{"wlsunset", "-t", "4000"}, append(sd.scope, sessx.Marker("wayland-test"))...)
	argv := []string{"wlsunset", "-t", "5000"}
	if err := sd.d.wlsunset(context.Background(), true, argv); err != nil {
		t.Fatal(err)
	}
	want := "signal 700\nsignal 701\nspawn wlsunset -t 5000 [AXIOM_SPAWNED=nightlight:wayland-test]"
	if got := sd.fx.got(); got != want {
		t.Fatalf("calls:\n%s", got)
	}
	if rec := sd.record(); len(rec.Stopped) != 1 || rec.Stopped[0].Kind != "wlsunset" || rec.Stopped[0].Argv[2] != "3000" {
		t.Fatalf("record %+v", rec.Stopped)
	}
	// Off: only ours; theirs stays recorded
	addProc(t, sd.proc, 702, []string{"wlsunset"}, append(sd.scope, sessx.Marker("wayland-test"))...)
	sd.d.wlsunset(context.Background(), false, nil)
	if got := sd.fx.got(); !strings.HasSuffix(got, "signal 702") {
		t.Fatalf("calls:\n%s", got)
	}
	if rec := sd.record(); len(rec.Stopped) != 1 {
		t.Fatalf("record %+v", rec.Stopped)
	}
}

func TestPortalLineFollowsScreenSharingEnabled(t *testing.T) {
	sd := newSessionDaemon(t, false)
	d := sd.d
	sd.td.env["NIRI_SOCKET"] = "/nonexistent/niri.sock"
	data := sd.td.env["XDG_DATA_HOME"]
	os.MkdirAll(filepath.Join(data, "xdg-desktop-portal/portals"), 0o755)
	os.WriteFile(filepath.Join(data, "xdg-desktop-portal/portals/axiom.portal"), nil, 0o644)
	sd.bus["org.freedesktop.portal.Desktop"] = 321
	addProc(t, sd.proc, 321, []string{"xdg-desktop-portal"}, "XDG_RUNTIME_DIR="+sd.td.env["XDG_RUNTIME_DIR"])
	d.newScreenShare()
	path := sessx.PortalEnvFrom(sd.td.getenv).Path()
	has := func() bool {
		b, _ := os.ReadFile(path)
		return strings.Contains(string(b), sessx.PortalText)
	}
	d.screenShare.Configure(screenshare.Settings{Enabled: true})
	d.syncPortalLine(context.Background(), false)
	if !has() {
		t.Fatal("the line isn't there with ScreenSharing on")
	}
	if got := sd.fx.got(); got != "signal 321" {
		t.Fatalf("the portal wasn't restarted once: %q", got)
	}
	d.syncPortalLine(context.Background(), false)
	if sd.fx.got() != "signal 321" {
		t.Fatal("restarted again for nothing")
	}
	// the portal came back (the signal ended the fixture's)
	addProc(t, sd.proc, 321, []string{"xdg-desktop-portal"}, "XDG_RUNTIME_DIR="+sd.td.env["XDG_RUNTIME_DIR"])
	d.screenShare.Configure(screenshare.Settings{Enabled: false})
	d.syncPortalLine(context.Background(), false)
	if has() {
		t.Fatal("the line is still there with ScreenSharing off")
	}
	if strings.Count(sd.fx.got(), "signal 321") != 2 {
		t.Fatalf("calls %q", sd.fx.got())
	}
	if d.portalLine.state != sessx.LineOff {
		t.Fatalf("state %q", d.portalLine.state)
	}
}

func TestRestartPortalRPCIsShellOnly(t *testing.T) {
	td := newTestDaemon(t)
	fx := &effects{proc: t.TempDir()}
	addProc(t, fx.proc, 77, []string{"xdg-desktop-portal"}, "XDG_RUNTIME_DIR="+td.env["XDG_RUNTIME_DIR"])
	td.session = &sessionTest{Seams: fx.seams(nil), ProcRoot: fx.proc, Bus: fakeBus{"org.freedesktop.portal.Desktop": 77}}
	td.start(t, func(int) bool { return true })
	shell, err := td.connect(t, "shell", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	if err := shell.Call(context.Background(), "screenshare.restartPortal", map[string]any{"backends": []any{}}, nil); err != nil {
		t.Fatal(err)
	}
	if got := fx.got(); got != "signal 77" {
		t.Fatalf("calls %q", got)
	}
	other, err := td.connect(t, "cli", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	err = other.Call(context.Background(), "screenshare.restartPortal", map[string]any{"backends": []any{}}, nil)
	if axerr.KindOf(err) != axerr.Refused {
		t.Fatalf("a non-shell restarted the portal: %v", err)
	}
}

// units are left alone for a runtime folder that isn't the user manager's
// (a scratch daemon on the live bus), even with systemd on the bus
func TestUnitsLeftAloneForAScratchRuntimeFolder(t *testing.T) {
	sd := newSessionDaemon(t, false)
	sd.bus[systemdName] = 1
	sd.td.env["DBUS_SESSION_BUS_ADDRESS"] = "unix:path=/tmp/live/bus"
	addProc(t, sd.proc, 800, []string{"/usr/bin/hyprpolkitagent"}, sd.scope...)
	res := sd.d.stopOthers(context.Background(), agents, []string{"hyprpolkitagent.service"})
	if len(res.Units) != 0 || strings.Contains(sd.fx.got(), "systemctl") {
		t.Fatalf("calls %q, result %+v", sd.fx.got(), res)
	}
}

// an entry that couldn't be written is not kept: the next save would persist
// a ghost, which teardown would start as a duplicate
func TestRecordIsRolledBackWhenItCannotBeSaved(t *testing.T) {
	sd := newSessionDaemon(t, false)
	rec := &sessionRec{path: filepath.Join(t.TempDir(), "missing", "dir", "session.json"), log: sd.d.sessionLog}
	rec.rec.DaemonPID = 7
	err := rec.with(func(rt *sessx.Runtime) {
		rt.Stopped = append(rt.Stopped, sessx.Process{Kind: "polkit", Argv: []string{"x"}})
	})
	if err == nil {
		t.Fatal("saved into a folder that isn't there")
	}
	if len(rec.rec.Stopped) != 0 || rec.rec.DaemonPID != 7 {
		t.Fatalf("not rolled back: %+v", rec.rec)
	}
	// and once it can be saved, no ghost comes with the next change
	os.MkdirAll(filepath.Dir(rec.path), 0o755)
	rec.with(func(rt *sessx.Runtime) { rt.Clean = true })
	if got := sessx.ReadRuntime(rec.path, nil); got == nil || len(got.Stopped) != 0 {
		t.Fatalf("saved %+v", got)
	}
}

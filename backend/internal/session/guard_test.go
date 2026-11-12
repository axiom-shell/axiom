package session

import (
	"context"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"golang.org/x/sys/unix"

	"github.com/axiom-shell/axiom/backend/internal/fsx"
)

// a stand-in daemon, its pidfd, and a Wayland socket that stays up until
// the test closes it
type guardRig struct {
	t      *testing.T
	dir    string
	child  *exec.Cmd
	pidfd  int
	socket string
	conns  chan net.Conn
	ln     net.Listener
	calls  *calls
	proc   *fakeProc
}

func newGuardRig(t *testing.T, clean bool) *guardRig {
	dir := t.TempDir()
	r := &guardRig{t: t, dir: dir, calls: &calls{}, proc: newProc(t)}
	r.child = exec.Command("sleep", "60")
	if err := r.child.Start(); err != nil {
		t.Skip("no sleep:", err)
	}
	t.Cleanup(func() { r.child.Process.Kill(); r.child.Wait() })
	fd, err := unix.PidfdOpen(r.child.Process.Pid, 0)
	if err != nil {
		t.Skip("no pidfd:", err)
	}
	r.pidfd = fd
	t.Cleanup(func() { unix.Close(fd) })
	r.socket = filepath.Join(dir, "wl")
	r.ln, err = net.Listen("unix", r.socket)
	if err != nil {
		t.Fatal(err)
	}
	r.conns = make(chan net.Conn, 4)
	go func() {
		for {
			c, err := r.ln.Accept()
			if err != nil {
				return
			}
			r.conns <- c
		}
	}()
	t.Cleanup(func() { r.ln.Close() })
	rec := &Runtime{DaemonPID: r.child.Process.Pid, Clean: clean,
		Stopped: []Process{{Kind: "polkit", Argv: []string{"/usr/bin/soteria"}, Cwd: "/h"}}}
	rec.Compositor.Kind = "none"
	if err := rec.Write(filepath.Join(dir, RuntimeFile)); err != nil {
		t.Fatal(err)
	}
	return r
}

func (r *guardRig) opts() GuardOptions {
	to := TeardownOptions{Scope: r.proc.scope(), Seams: r.calls.seams(),
		State: Store{Path: filepath.Join(r.dir, "state/session.json")}, Portal: PortalEnv{Config: filepath.Join(r.dir, "cfg")}}
	return GuardOptions{Dir: r.dir, Pidfd: r.pidfd, WaylandSocket: r.socket, Base: to}
}

func (r *guardRig) run(o GuardOptions) <-chan error {
	done := make(chan error, 1)
	go func() { done <- RunGuard(context.Background(), o) }()
	return done
}

func (r *guardRig) record() *Runtime { return ReadRuntime(filepath.Join(r.dir, RuntimeFile), nil) }

func wait(t *testing.T, done <-chan error) {
	t.Helper()
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("the guard didn't exit")
	}
}

func (r *guardRig) kill() { r.child.Process.Kill(); r.child.Wait() }

func TestGuardExitsOnACleanRecord(t *testing.T) {
	r := newGuardRig(t, true)
	done := r.run(r.opts())
	r.kill()
	wait(t, done)
	if got := r.calls.got(); got != "" {
		t.Fatalf("a clean record was acted on: %q", got)
	}
}

func TestGuardTearsDownWhenTheDaemonDies(t *testing.T) {
	r := newGuardRig(t, false)
	o := r.opts()
	o.Alive = func() bool { return true }
	done := r.run(o)
	// the guard writes its pid before waiting
	for i := 0; i < 200 && (r.record() == nil || r.record().GuardPID == 0); i++ {
		time.Sleep(10 * time.Millisecond)
	}
	if rec := r.record(); rec.GuardPID != os.Getpid() {
		t.Fatalf("guard pid %d", rec.GuardPID)
	}
	r.kill()
	wait(t, done)
	if got := r.calls.got(); got != "spawn /usr/bin/soteria in /h" {
		t.Fatalf("calls: %q", got)
	}
	if rec := r.record(); !rec.Clean || len(rec.Stopped) != 0 {
		t.Fatalf("record: %+v", rec)
	}
}

func TestGuardFileOnlyWhenTheCompositorIsGone(t *testing.T) {
	r := newGuardRig(t, false)
	o := r.opts()
	o.Alive = func() bool { t.Error("asked whether the compositor is alive"); return true }
	r.proc.add(50, []string{"wlsunset"}, append([]string{Marker("wayland-1")}, inScope...)...)
	done := r.run(o)
	select {
	case c := <-r.conns:
		c.Close()
		r.ln.Close()
	case <-time.After(5 * time.Second):
		t.Fatal("the guard never watched the socket")
	}
	wait(t, done)
	got := r.calls.got()
	if got != "signal 50 15" {
		t.Fatalf("calls: %q: only wlsunset goes, nothing is started", got)
	}
	if rec := r.record(); !rec.Clean || len(rec.Stopped) != 0 {
		t.Fatalf("record: %+v", rec)
	}
}

func TestGuardLockHeldMeansExit(t *testing.T) {
	r := newGuardRig(t, false)
	lock, err := fsx.TryLock(filepath.Join(r.dir, GuardLock))
	if err != nil {
		t.Fatal(err)
	}
	defer lock.Release()
	done := r.run(r.opts())
	wait(t, done)
	if rec := r.record(); rec.GuardPID != 0 || rec.Clean {
		t.Fatalf("a second guard touched the record: %+v", rec)
	}
	if strings.Contains(r.calls.got(), "spawn") {
		t.Fatal("acted")
	}
}

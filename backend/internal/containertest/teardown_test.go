//go:build container

package containertest

import (
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"syscall"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

var (
	swayReload = regexp.MustCompile(`Handling command 'reload'`)
	swayBind   = regexp.MustCompile(`Handling command 'bindsym `)
	swayUnbind = regexp.MustCompile(`Handling command 'unbindsym `)
)

// swaySession is a sway with axiom running on it, its binds sent.
func swaySession(t *testing.T, config string) (*Session, *Proc) {
	t.Helper()
	s := NewSession(t)
	s.StartSway(config)
	p := s.StartAxiom("sway")
	if !swayHandled(s, 0) {
		t.Fatalf("sway never handled axiom's binds; sway log tail:\n%s\naxiom log tail:\n%s", s.Tail("sway.log", 20), s.Tail(daemonLog, 30))
	}
	return s, p
}

func stopAxiom(t *testing.T, p *Proc) {
	t.Helper()
	p.Signal(syscall.SIGTERM)
	if !p.Wait() {
		t.Fatal("axiom didn't stop")
	}
}

// stepsRecorded waits until the record holds what takes the layer out
func stepsRecorded(t *testing.T, s *Session) {
	t.Helper()
	if !testkit.Eventually(func() bool { r := s.Record(); return r != nil && len(r.Compositor.Steps) > 0 }) {
		t.Fatalf("no steps in the record: %+v", s.Record())
	}
}

func recordClean(s *Session) func() bool {
	return func() bool { r := s.Record(); return r != nil && r.Clean }
}

func TestContainerSwayQuitReloads(t *testing.T) {
	s, p := swaySession(t, swayMinimal)
	offset := len(s.LogSince("sway.log", 0))
	stopAxiom(t, p)
	if !s.WaitLog("sway.log", swayReload, offset) {
		t.Fatalf("sway was never told to reload; log tail:\n%s", s.Tail("sway.log", 20))
	}
	if !testkit.Eventually(recordClean(s)) {
		t.Fatalf("the record isn't clean: %+v", s.Record())
	}
	if !strings.Contains(s.LogSince(daemonLog, 0), "session teardown done") {
		t.Fatalf("no teardown line; log tail:\n%s", s.Tail(daemonLog, 20))
	}
}

// The user's config starts axiom at every reload: a reload on quit would
// start another, so only the binds come out.
func TestContainerSwayExecAlwaysAxiomGetsPartialTeardown(t *testing.T) {
	s, p := swaySession(t, swayMinimal+"exec_always true axiom run\n")
	offset := len(s.LogSince("sway.log", 0))
	stopAxiom(t, p)
	if !s.WaitLog("sway.log", swayUnbind, offset) {
		t.Fatalf("the binds weren't taken out; log tail:\n%s", s.Tail("sway.log", 20))
	}
	// the teardown is over once the record is clean: nothing came after
	if !testkit.Eventually(recordClean(s)) {
		t.Fatal("the record isn't clean")
	}
	if swayReload.MatchString(s.LogSince("sway.log", offset)) {
		t.Fatal("sway was told to reload")
	}
}

func TestContainerGuardTearsDownAfterKill9(t *testing.T) {
	s, p := swaySession(t, swayMinimal)
	guard := s.Guard()
	stepsRecorded(t, s)
	offset := len(s.LogSince("sway.log", 0))
	p.Signal(syscall.SIGKILL)
	p.Wait()
	if !s.WaitLog("sway.log", swayReload, offset) {
		t.Fatalf("the guard never reloaded sway; guard log:\n%s", s.GuardLog())
	}
	if !testkit.Eventually(recordClean(s)) {
		t.Fatalf("the record isn't clean: %+v", s.Record())
	}
	if !WaitGone(guard) {
		t.Fatal("the guard is still running")
	}
}

func TestContainerGuardExitsWithTheCompositor(t *testing.T) {
	s, p := swaySession(t, swayMinimal)
	guard := s.Guard()
	// The daemon is frozen, so only the guard sees the compositor go
	p.Signal(syscall.SIGSTOP)
	t.Cleanup(func() { p.Signal(syscall.SIGKILL) })
	s.sway.Signal(syscall.SIGKILL)
	s.sway.Wait()
	if !WaitGone(guard) {
		t.Fatalf("the guard outlived its compositor; guard log:\n%s", s.GuardLog())
	}
	if log := s.GuardLog(); !strings.Contains(log, "the compositor is gone") || !strings.Contains(log, "compositor reachable: false") {
		t.Fatalf("guard log:\n%s", log)
	}
	if r := s.Record(); r == nil || !r.Clean {
		t.Fatalf("record: %+v", r)
	}
}

func TestContainerReexecKeepsOneGuard(t *testing.T) {
	s, _ := swaySession(t, swayMinimal)
	guard := s.Guard()
	guards := func() int {
		return len(Procs(func(p ProcInfo) bool {
			return len(p.Argv) >= 2 && filepath.Base(p.Argv[0]) == "axiom" && p.Argv[1] == "guard" && p.HasEnv("WAYLAND_DISPLAY="+s.vars["WAYLAND_DISPLAY"])
		}))
	}
	if guards() != 1 {
		t.Fatalf("guards before: %d", guards())
	}
	offset := len(s.LogSince(daemonLog, 0))
	s.Axiom("daemon", "reexec")
	if !s.WaitLog(daemonLog, regexp.MustCompile(`axiom is running.*reexec=true`), offset) {
		t.Fatalf("the daemon didn't come back; log tail:\n%s", s.Tail(daemonLog, 30))
	}
	time.Sleep(testkit.Bound(time.Second))
	if got := s.Guard(); got != guard {
		t.Fatalf("guard pid %d, was %d", got, guard)
	}
	if guards() != 1 {
		t.Fatalf("guards after: %d", guards())
	}
}

func TestContainerFreshStartWaitsForTheOldGuard(t *testing.T) {
	s, p := swaySession(t, swayMinimal)
	s.Guard()
	stepsRecorded(t, s)
	offset := len(s.LogSince("sway.log", 0))
	p.Signal(syscall.SIGKILL)
	p.Wait()
	s.StartAxiom("sway")
	if !s.WaitLog("sway.log", swayBind, offset) {
		t.Fatal("the second daemon's binds never reached sway")
	}
	log := s.LogSince("sway.log", offset)
	reload, bind := swayReload.FindStringIndex(log), swayBind.FindStringIndex(log)
	if reload == nil || reload[0] > bind[0] {
		t.Fatalf("the old guard's reload must come before the new binds (reload at %v, bind at %v)", reload, bind)
	}
	if !strings.Contains(s.GuardLog(), "guard: done") {
		t.Fatalf("guard log:\n%s", s.GuardLog())
	}
}

const polkitPattern = `^([^ ]*/)?(hyprpolkitagent)( |$)`

func agentsOf(path string) []ProcInfo {
	return Procs(func(p ProcInfo) bool { return p.Argv[0] == path })
}

func TestContainerPolkitStopAndRespawn(t *testing.T) {
	s, p := swaySession(t, swayMinimal)
	agent := s.FakeSleeper("hyprpolkitagent")
	s.FakeProgram("systemctl", `echo "$@" >> "$HOME/systemctl.log"`)
	mine := s.StartProgram(nil, agent, "4000")
	theirs := s.StartProgram(s.SecondDisplayEnv(), agent, "5000")
	if !testkit.Eventually(func() bool { return len(agentsOf(agent)) == 2 }) {
		t.Fatal("the fake agents didn't start")
	}
	systemctlLog := func() string { data, _ := os.ReadFile(filepath.Join(s.Home, "systemctl.log")); return string(data) }
	stop := func() {
		t.Helper()
		if _, err := s.ShellCall("polkit.stopOthers", map[string]any{"pattern": polkitPattern, "units": []string{"hyprpolkitagent.service"}}); err != nil {
			t.Fatal(err)
		}
	}
	// no systemd on this bus: its units stay alone
	stop()
	if !WaitGone(mine.cmd.Process.Pid) {
		t.Fatal("the agent of this session wasn't stopped")
	}
	if !Alive(theirs.cmd.Process.Pid) {
		t.Fatal("the agent of another session was stopped")
	}
	if got := systemctlLog(); got != "" {
		t.Fatalf("systemctl ran without the user manager's bus: %q", got)
	}
	rec := s.Record()
	if rec == nil || len(rec.Stopped) != 1 || !slices.Equal(rec.Stopped[0].Argv, []string{agent, "4000"}) {
		t.Fatalf("the record: %+v", rec)
	}
	// with systemd on the bus: its unit is stopped, and started on quit
	s.OwnBusName("org.freedesktop.systemd1")
	again := s.StartProgram(nil, agent, "4000")
	if !testkit.Eventually(func() bool { return Alive(again.cmd.Process.Pid) }) {
		t.Fatal("no second agent")
	}
	stop()
	want := "--user -q is-active hyprpolkitagent.service\n--user stop hyprpolkitagent.service\n"
	if got := systemctlLog(); got != want {
		t.Fatalf("systemctl log:\n%s\nwant:\n%s", got, want)
	}
	known := map[int]bool{mine.cmd.Process.Pid: true, theirs.cmd.Process.Pid: true, again.cmd.Process.Pid: true}
	stopAxiom(t, p)
	if !testkit.Eventually(func() bool {
		for _, a := range agentsOf(agent) {
			if !known[a.PID] && slices.Equal(a.Argv, []string{agent, "4000"}) {
				return true
			}
		}
		return false
	}) {
		t.Fatalf("the agent wasn't started again; daemon log:\n%s", s.Tail(daemonLog, 20))
	}
	if got := systemctlLog(); !strings.HasSuffix(got, "--user start hyprpolkitagent.service\n") {
		t.Fatalf("the unit wasn't started again: %q", got)
	}
}

func TestContainerWlsunsetTheirsBackOursGone(t *testing.T) {
	s, p := swaySession(t, swayMinimal)
	prog := s.FakeSleeper("wlsunset")
	theirs := s.StartProgram(nil, prog, "-t", "3000")
	if !testkit.Eventually(func() bool { return len(agentsOf(prog)) == 1 }) {
		t.Fatal("their wlsunset didn't start")
	}
	marker := "AXIOM_SPAWNED=nightlight:" + s.vars["WAYLAND_DISPLAY"]
	ours := func() []ProcInfo {
		return Procs(func(p ProcInfo) bool { return filepath.Base(p.Argv[0]) == "wlsunset" && p.HasEnv(marker) })
	}
	if _, err := s.ShellCall("nightlight.wlsunset", map[string]any{"on": true, "argv": []string{"wlsunset", "-t", "4000"}}); err != nil {
		t.Fatal(err)
	}
	if !WaitGone(theirs.cmd.Process.Pid) {
		t.Fatal("their wlsunset wasn't stopped")
	}
	if !testkit.Eventually(func() bool { return len(ours()) == 1 }) {
		t.Fatalf("axiom's wlsunset isn't running; daemon log:\n%s", s.Tail(daemonLog, 20))
	}
	running := func() bool {
		raw, err := s.ShellCall("nightlight.wlsunsetState", map[string]any{})
		return err == nil && strings.Contains(string(raw), "true")
	}
	if !running() {
		t.Fatal("wlsunsetState says it isn't running")
	}
	stopAxiom(t, p)
	if !testkit.Eventually(func() bool {
		// theirs again: a wlsunset without the marker
		return len(ours()) == 0 && len(Procs(func(p ProcInfo) bool {
			return filepath.Base(p.Argv[0]) == "wlsunset" && !p.HasEnv(marker) && slices.Equal(p.Argv[1:], []string{"-t", "3000"})
		})) == 1
	}) {
		t.Fatalf("axiom's wlsunset should be gone and theirs back; daemon log:\n%s", s.Tail(daemonLog, 20))
	}
}

func TestContainerPortalRestartIsScopedToTheBus(t *testing.T) {
	s, _ := swaySession(t, swayMinimal)
	s.FakeProgram("systemctl", `echo "$@" >> "$HOME/systemctl.log"`)
	const name = "org.freedesktop.portal.Desktop"
	mine := s.StartFakePortal("", name)
	other := s.StartFakePortal(s.StartSecondBus(), name)
	if _, err := s.ShellCall("screenshare.restartPortal", map[string]any{"backends": []any{}}); err != nil {
		t.Fatal(err)
	}
	if !testkit.Eventually(mine.Termed) {
		t.Fatal("the portal of this session's bus wasn't told to stop")
	}
	// given the time the other one would have needed
	time.Sleep(testkit.Bound(500 * time.Millisecond))
	if other.Termed() || !Alive(other.cmd.Process.Pid) {
		t.Fatal("the portal of another bus was signalled")
	}
	if _, err := os.Stat(filepath.Join(s.Home, "systemctl.log")); err == nil {
		t.Fatal("systemctl ran without systemd on the bus")
	}
}

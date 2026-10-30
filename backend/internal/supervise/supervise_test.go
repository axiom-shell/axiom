package supervise

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

func fast(opts Options) Options {
	opts.Backoff = []time.Duration{5 * time.Millisecond, 20 * time.Millisecond}
	opts.Window = time.Second
	opts.StopGrace = 300 * time.Millisecond
	return opts
}

func run(t *testing.T, s *Supervisor) (context.CancelFunc, chan struct{}) {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() { s.Run(ctx); close(done) }()
	t.Cleanup(func() { cancel(); <-done })
	return cancel, done
}

func eventually(t *testing.T, cond func() bool) {
	t.Helper()
	if !testkit.Eventually(cond) {
		t.Fatal("timed out")
	}
}

func TestCrashesRestartThenGiveUp(t *testing.T) {
	t.Parallel()
	s := New(fast(Options{Command: []string{"sh", "-c", "exit 3"}, GiveUp: 4}))
	run(t, s)
	eventually(t, func() bool { return s.Status().GaveUp })
	if st := s.Status(); st.Restarts < 4 || st.Running {
		t.Errorf("status %+v", st)
	}
	// Asking starts it again
	if err := s.Restart(context.Background(), nil); err != nil {
		t.Fatal(err)
	}
	if s.Status().GaveUp {
		t.Error("still given up after a restart")
	}
}

func TestCleanExitWaitsForRestart(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	count := filepath.Join(dir, "count")
	s := New(fast(Options{Command: []string{"sh", "-c", "echo x >> " + count}}))
	run(t, s)
	eventually(t, func() bool { data, _ := os.ReadFile(count); return len(data) > 0 })
	time.Sleep(100 * time.Millisecond)
	if data, _ := os.ReadFile(count); strings.Count(string(data), "x") != 1 {
		t.Errorf("a clean exit was restarted: %q", data)
	}
	s.Restart(context.Background(), nil)
	eventually(t, func() bool { data, _ := os.ReadFile(count); return strings.Count(string(data), "x") == 2 })
}

func TestEnvironmentIsTheDaemonsWithItsAxiomValues(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	out := filepath.Join(dir, "env")
	s := New(fast(Options{
		Command: []string{"sh", "-c", "env > " + out + "; sleep 10"},
		Environ: []string{"HOME=/h", "PATH=" + os.Getenv("PATH"), "AXIOM_REEXEC=evil", "AXIOM_SOCKET=/wrong", "EDITOR=vi"},
		Env:     map[string]string{"AXIOM_SOCKET": "/right"},
	}))
	run(t, s)
	s.Restart(context.Background(), map[string]string{"AXIOM_LOCK_ON_START": "1"})
	eventually(t, func() bool {
		data, _ := os.ReadFile(out)
		return strings.Contains(string(data), "AXIOM_LOCK_ON_START=1")
	})
	data, _ := os.ReadFile(out)
	env := string(data)
	for _, want := range []string{"HOME=/h", "EDITOR=vi", "AXIOM_SOCKET=/right"} {
		if !strings.Contains(env, want) {
			t.Errorf("missing %s", want)
		}
	}
	for _, bad := range []string{"AXIOM_REEXEC", "/wrong"} {
		if strings.Contains(env, bad) {
			t.Errorf("leaked %s", bad)
		}
	}
}

func TestStopEscalatesToKill(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	pidFile := filepath.Join(dir, "child.pid")
	s := New(fast(Options{Command: []string{"sh", "-c", "trap '' TERM; while :; do sleep 0.05; done"}, PIDFile: pidFile}))
	cancel, done := run(t, s)
	eventually(t, func() bool { return s.Status().Running })
	pid := s.Status().PID
	cancel()
	select {
	case <-done:
	case <-time.After(testkit.Bound(3 * time.Second)):
		t.Fatal("didn't stop")
	}
	if syscall.Kill(pid, 0) == nil {
		t.Error("the child survived")
	}
	if _, err := os.Stat(pidFile); err == nil {
		t.Error("pid file left behind")
	}
}

func TestOrphanOfAnEarlierDaemonIsStopped(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	pidFile := filepath.Join(dir, "child.pid")
	command := []string{"sleep", "30"}
	orphan := exec.Command(command[0], command[1:]...)
	if err := orphan.Start(); err != nil {
		t.Fatal(err)
	}
	exited := make(chan struct{})
	go func() { orphan.Wait(); close(exited) }()
	os.WriteFile(pidFile, []byte(strconv.Itoa(orphan.Process.Pid)), 0o600)
	// A pid file naming an unrelated process must leave it alone
	other := exec.Command("sleep", "31")
	other.Start()
	defer other.Process.Kill()

	s := New(fast(Options{Command: command, PIDFile: pidFile}))
	// Start returns before the kernel shows the new cmdline (empty, or still
	// ours, under load): an orphan of an earlier daemon has long shown it
	eventually(t, func() bool { return s.isOurChild(orphan.Process.Pid) })
	run(t, s)
	// Left alone, it would sleep 30 s
	select {
	case <-exited:
	case <-time.After(testkit.Bound(15 * time.Second)):
		t.Fatal("the orphan wasn't stopped")
	}
	if syscall.Kill(other.Process.Pid, 0) != nil {
		t.Error("an unrelated process was stopped")
	}
}

func TestMissingBinaryCountsAsCrash(t *testing.T) {
	t.Parallel()
	s := New(fast(Options{Command: []string{filepath.Join(t.TempDir(), "no-such-qs")}, GiveUp: 3}))
	run(t, s)
	eventually(t, func() bool { return s.Status().GaveUp })
}

// After a re-exec the pid file names the adopted shell: it is supervised,
// never stopped as an orphan.
func TestAdoptedShellIsNotStoppedAsAnOrphan(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	pidFile := filepath.Join(dir, "child.pid")
	command := []string{"sleep", "30"}
	child := exec.Command(command[0], command[1:]...)
	child.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := child.Start(); err != nil {
		t.Fatal(err)
	}
	pid := child.Process.Pid
	os.WriteFile(pidFile, []byte(strconv.Itoa(pid)), 0o600)

	s := New(fast(Options{Command: command, PIDFile: pidFile, AdoptPID: pid}))
	cancel, done := run(t, s)
	eventually(t, func() bool { return s.Status().PID == pid })
	// Longer than an orphan's stop takes
	time.Sleep(2 * fast(Options{}).StopGrace)
	if syscall.Kill(pid, 0) != nil || s.Status().PID != pid {
		t.Fatalf("the adopted shell was stopped (status %+v)", s.Status())
	}
	cancel()
	<-done
	if syscall.Kill(pid, 0) == nil {
		t.Error("the adopted shell outlived the supervisor")
	}
}

// A stop the supervisor asked for is OnStop's, never OnExit's: the
// daemon relaunches a locked shell only when it ended on its own.
func TestRequestedStopIsNotAnExit(t *testing.T) {
	t.Parallel()
	exits, stops := make(chan int, 4), make(chan int, 4)
	s := New(fast(Options{
		Command: []string{"sleep", "30"},
		OnExit:  func(pid int, _ bool) { exits <- pid },
		OnStop:  func(pid int) { stops <- pid },
	}))
	cancel, done := run(t, s)
	eventually(t, func() bool { return s.Status().Running })
	first := s.Status().PID
	if err := s.Restart(context.Background(), nil); err != nil {
		t.Fatal(err)
	}
	select {
	case pid := <-stops:
		if pid != first {
			t.Errorf("OnStop got %d, want %d", pid, first)
		}
	case <-time.After(time.Second):
		t.Fatal("no OnStop for the restart")
	}
	cancel()
	<-done
	select {
	case pid := <-exits:
		t.Errorf("OnExit for %d, a stop that was asked for", pid)
	default:
	}
}

// The test binary stands in for the axiom image /proc/self/exe names.
func TestMain(m *testing.M) {
	if len(os.Args) > 1 && os.Args[1] == NoTHPArg {
		err := ExecNoTHP(os.Args[2:], os.Stderr)
		os.Stderr.WriteString(err.Error() + "\n")
		os.Exit(127)
	}
	os.Exit(m.Run())
}

// With NoTHP the shell, and what it runs, has transparent huge pages off,
// under the pid the supervisor started; the supervisor keeps them.
func TestNoTHPIsTheShellsAlone(t *testing.T) {
	t.Parallel()
	thp := func(status string) string {
		for line := range strings.Lines(status) {
			if v, ok := strings.CutPrefix(line, "THP_enabled:"); ok {
				return strings.TrimSpace(v)
			}
		}
		return ""
	}
	own, err := os.ReadFile("/proc/self/status")
	if err != nil || thp(string(own)) != "1" {
		t.Skip("no transparent huge pages here")
	}
	for _, c := range []struct {
		noTHP bool
		want  string
	}{{false, "1"}, {true, "0"}} {
		t.Run(strconv.FormatBool(c.noTHP), func(t *testing.T) {
			t.Parallel()
			out := filepath.Join(t.TempDir(), "out")
			// $$ is the shell's pid; grep, its child, reads its own status
			script := `echo $$ > "$0"; grep THP_enabled /proc/self/status >> "$0"`
			started := make(chan int, 1)
			s := New(fast(Options{Command: []string{"sh", "-c", script, out}, NoTHP: c.noTHP, OnStart: func(pid int) { started <- pid }}))
			run(t, s)
			pid := <-started
			var data []byte
			eventually(t, func() bool {
				data, _ = os.ReadFile(out)
				return strings.Count(string(data), "\n") == 2
			})
			first, rest, _ := strings.Cut(string(data), "\n")
			if first != strconv.Itoa(pid) {
				t.Errorf("the shell ran as %s, started as %d", first, pid)
			}
			if got := thp(rest); got != c.want {
				t.Errorf("THP_enabled %q, want %q", got, c.want)
			}
			if own, _ := os.ReadFile("/proc/self/status"); thp(string(own)) != "1" {
				t.Error("the supervisor's huge pages were turned off")
			}
		})
	}
}

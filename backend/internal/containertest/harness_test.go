//go:build container

package containertest

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/buildinfo"
	"github.com/axiom-shell/axiom/backend/internal/daemon"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

// Require skips a test unless it runs in the container, and refuses to run
// when AXIOM_CONTAINER says so on a machine that isn't one: these tests
// start compositors and must never touch a dev machine's.
func Require(t *testing.T) {
	t.Helper()
	if os.Getenv("AXIOM_CONTAINER") != "1" {
		t.Skip("container tests run only in scripts/dev/container-test.sh")
	}
	if _, err := os.Stat("/.dockerenv"); err != nil {
		t.Fatal("AXIOM_CONTAINER is set but this isn't a container (no /.dockerenv): refusing to run")
	}
}

// TestMain lets this test binary be the daemon's shell (its --qs): the
// daemon drops AXIOM_* variables from the shell's environment, so its own
// are CTR_*. The daemon starts it as `qs -p <entry> …`, and it says hello
// and waits.
func TestMain(m *testing.M) {
	if os.Getenv("CTR_FAKESHELL") == "1" {
		os.Exit(fakeShell())
	}
	os.Exit(m.Run())
}

// fakeShell is the shell as far as the daemon can tell: it says hello as
// the shell, hands over the compositor inputs and waits for SIGTERM.
func fakeShell() int {
	// The daemon keeps the shell's output to itself: into a file, panics too
	if path := os.Getenv("CTR_LOG"); path != "" {
		if f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644); err == nil {
			syscall.Dup3(int(f.Fd()), 2, 0)
		}
	}
	fail := func(format string, args ...any) int {
		fmt.Fprintf(os.Stderr, "fakeshell: "+format+"\n", args...)
		return 1
	}
	sock := os.Getenv("AXIOM_SOCKET")
	if sock == "" {
		sock = filepath.Join(os.Getenv("XDG_RUNTIME_DIR"), "axiom", os.Getenv("WAYLAND_DISPLAY"), "axiom.sock")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	c, err := rpc.Dial(ctx, sock, nil, nil)
	if err != nil {
		return fail("%v", err)
	}
	defer c.Close()
	hash := ""
	if data, err := os.ReadFile(os.Getenv("AXIOM_SCHEMA")); err == nil {
		hash = buildinfo.SchemaHash(data)
	}
	// Up before the daemon has noted the shell's pid, which a real shell
	// (qs takes its time) never is: say hello again until it's taken
	var hello daemon.HelloResult
	for try := 0; ; try++ {
		err = c.Call(ctx, "daemon.hello", daemon.HelloParams{Protocol: buildinfo.Protocol(), Client: "shell", SchemaHash: hash, PID: os.Getpid()}, &hello)
		if err == nil {
			break
		}
		if try >= 50 {
			return fail("hello (pid %d): %v", os.Getpid(), err)
		}
		time.Sleep(100 * time.Millisecond)
	}
	facts, err := os.ReadFile(filepath.Join(os.Getenv("CTR_SRC"), "backend/internal/compositor/manager/testdata/facts.json"))
	if err != nil {
		return fail("%v", err)
	}
	var params map[string]any
	if err := json.Unmarshal(facts, &params); err != nil {
		return fail("facts: %v", err)
	}
	params["kind"] = os.Getenv("CTR_KIND")
	if err := c.Call(ctx, "compositor.inputs", params, nil); err != nil {
		return fail("compositor.inputs: %v", err)
	}
	// The marker says it
	os.WriteFile(filepath.Join(os.Getenv("XDG_RUNTIME_DIR"), "fakeshell-hello"), nil, 0o644)
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGTERM, syscall.SIGINT)
	<-stop
	return 0
}

// Proc is a process a session started.
type Proc struct {
	cmd  *exec.Cmd
	done chan struct{}
	err  error
}

func start(cmd *exec.Cmd) (*Proc, error) {
	if err := cmd.Start(); err != nil {
		return nil, err
	}
	p := &Proc{cmd: cmd, done: make(chan struct{})}
	go func() {
		p.err = cmd.Wait()
		close(p.done)
	}()
	return p, nil
}

// Signal sends sig to the process.
func (p *Proc) Signal(sig os.Signal) { p.cmd.Process.Signal(sig) }

// Wait waits for it to exit, false if it doesn't within the bound.
func (p *Proc) Wait() bool {
	select {
	case <-p.done:
		return true
	case <-time.After(testkit.Bound(15 * time.Second)):
		return false
	}
}

func (p *Proc) stop() {
	select {
	case <-p.done:
		return
	default:
	}
	p.Signal(syscall.SIGTERM)
	if !p.Wait() {
		p.Signal(syscall.SIGKILL)
		<-p.done
	}
}

// Session is one scratch desktop: its own directories, its own session bus
// and, as started, a sway, a nested niri and an axiom, each stopped when the
// test ends. Its environment is built from scratch: nothing of the host's
// compositor reaches it.
type Session struct {
	t       *testing.T
	Home    string
	Config  string
	State   string
	Data    string
	Cache   string
	Runtime string
	// Out is where this test's logs go: $AXIOM_CTR_OUT/<test>/
	Out  string
	vars map[string]string
	mu   sync.Mutex
}

// NewSession makes the directories and starts the session bus.
func NewSession(t *testing.T) *Session {
	t.Helper()
	Require(t)
	s := &Session{t: t}
	base := t.TempDir()
	s.Home = filepath.Join(base, "home")
	s.Config, s.State = filepath.Join(s.Home, ".config"), filepath.Join(s.Home, ".local/state")
	s.Data, s.Cache = filepath.Join(s.Home, ".local/share"), filepath.Join(s.Home, ".cache")
	for _, d := range []string{s.Home, s.Config, s.State, s.Data, s.Cache} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	rt, err := os.MkdirTemp("/tmp", "xr")
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(rt, 0o700); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(rt) })
	s.Runtime = rt
	outRoot := os.Getenv("AXIOM_CTR_OUT")
	if outRoot == "" {
		outRoot = filepath.Join(base, "out")
	}
	s.Out = filepath.Join(outRoot, t.Name())
	if err := os.MkdirAll(s.Out, 0o755); err != nil {
		t.Fatal(err)
	}
	s.vars = map[string]string{
		"PATH": os.Getenv("PATH"), "HOME": s.Home, "LANG": "C.UTF-8",
		"XDG_CONFIG_HOME": s.Config, "XDG_STATE_HOME": s.State, "XDG_DATA_HOME": s.Data,
		"XDG_CACHE_HOME": s.Cache, "XDG_RUNTIME_DIR": s.Runtime,
		"DBUS_SESSION_BUS_ADDRESS": "unix:path=" + filepath.Join(s.Runtime, "bus"),
	}
	s.startDBus()
	return s
}

// env is the session's environment, plus extra (KEY=value).
func (s *Session) env(extra ...string) []string {
	s.mu.Lock()
	defer s.mu.Unlock()
	var out []string
	for k, v := range s.vars {
		out = append(out, k+"="+v)
	}
	return append(out, extra...)
}

func (s *Session) set(k, v string) {
	s.mu.Lock()
	s.vars[k] = v
	s.mu.Unlock()
}

// logFile opens a log in the test's output folder.
func (s *Session) logFile(name string) *os.File {
	f, err := os.OpenFile(filepath.Join(s.Out, name), os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		s.t.Fatal(err)
	}
	s.t.Cleanup(func() { f.Close() })
	return f
}

// run starts a long-running process of the session, its output in log, and
// stops it when the test ends.
func (s *Session) run(log string, cmd *exec.Cmd) *Proc {
	s.t.Helper()
	f := s.logFile(log)
	cmd.Stdout, cmd.Stderr = f, f
	p, err := start(cmd)
	if err != nil {
		s.t.Fatalf("starting %s: %v", cmd.Path, err)
	}
	s.t.Cleanup(p.stop)
	return p
}

func (s *Session) startDBus() {
	s.t.Helper()
	cmd := exec.Command("dbus-daemon", "--session", "--nofork", "--address="+s.vars["DBUS_SESSION_BUS_ADDRESS"])
	cmd.Env = s.env()
	s.run("dbus.log", cmd)
	if !testkit.Eventually(func() bool { _, err := os.Stat(filepath.Join(s.Runtime, "bus")); return err == nil }) {
		s.t.Fatal("the session bus didn't come up")
	}
}

// glob is the first match of pattern in the runtime dir, "" for none
func (s *Session) glob(pattern string) string {
	m, _ := filepath.Glob(filepath.Join(s.Runtime, pattern))
	for _, p := range m {
		if !strings.HasSuffix(p, ".lock") {
			return p
		}
	}
	return ""
}

// WriteFile writes text to rel under the session's home (".config/sway/config").
func (s *Session) WriteFile(rel, text string) string {
	s.t.Helper()
	path := filepath.Join(s.Home, rel)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		s.t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(text), 0o644); err != nil {
		s.t.Fatal(err)
	}
	return path
}

// StartSway writes config as sway's and starts a headless sway (debug log
// on), once its sockets are there.
func (s *Session) StartSway(config string) {
	s.t.Helper()
	s.WriteFile(".config/sway/config", config)
	cmd := exec.Command("sway", "-d")
	cmd.Env = s.env("WLR_BACKENDS=headless", "WLR_RENDERER=pixman", "WLR_LIBINPUT_NO_DEVICES=1")
	p := s.run("sway.log", cmd)
	if !testkit.Eventually(func() bool { return s.glob("sway-ipc.*.sock") != "" && s.glob("wayland-*") != "" }) {
		s.t.Fatalf("sway didn't come up (alive: %v); log tail:\n%s", !isDone(p), s.Tail("sway.log", 20))
	}
	s.set("SWAYSOCK", s.glob("sway-ipc.*.sock"))
	s.set("WAYLAND_DISPLAY", filepath.Base(s.glob("wayland-*")))
}

func isDone(p *Proc) bool {
	select {
	case <-p.done:
		return true
	default:
		return false
	}
}

// Swaymsg runs swaymsg against the session's sway.
func (s *Session) Swaymsg(args ...string) string {
	s.t.Helper()
	cmd := exec.Command("swaymsg", append([]string{"-s", s.vars["SWAYSOCK"]}, args...)...)
	cmd.Env = s.env()
	out, err := cmd.CombinedOutput()
	if err != nil {
		s.t.Fatalf("swaymsg %v: %v\n%s", args, err, out)
	}
	return string(out)
}

// StartNiriNested writes config as niri's own (its default path) and starts
// niri inside the session's sway. It skips the test when niri doesn't come
// up here.
func (s *Session) StartNiriNested(config string) {
	s.t.Helper()
	s.WriteFile(".config/niri/config.kdl", config)
	cmd := exec.Command("niri")
	cmd.Env = s.env("LIBGL_ALWAYS_SOFTWARE=1")
	p := s.run("niri.log", cmd)
	if !testkit.Eventually(func() bool { return s.glob("niri.*.sock") != "" }) {
		s.t.Skipf("niri doesn't start nested here (alive: %v); log tail:\n%s", !isDone(p), s.Tail("niri.log", 20))
	}
	s.set("NIRI_SOCKET", s.glob("niri.*.sock"))
}

// NiriMsg runs niri msg against the session's niri, never another.
func (s *Session) NiriMsg(args ...string) string {
	s.t.Helper()
	sock := s.vars["NIRI_SOCKET"]
	if sock == "" {
		s.t.Fatal("no niri of the session's is running")
	}
	cmd := exec.Command("niri", append([]string{"msg"}, args...)...)
	cmd.Env = s.env()
	out, err := cmd.CombinedOutput()
	if err != nil {
		s.t.Fatalf("niri msg %v: %v\n%s", args, err, out)
	}
	return string(out)
}

// NiriMsgTry is NiriMsg, with the error returned.
func (s *Session) NiriMsgTry(args ...string) (string, error) {
	cmd := exec.Command("niri", append([]string{"msg"}, args...)...)
	cmd.Env = s.env()
	out, err := cmd.CombinedOutput()
	return string(out), err
}

// StartAxiom starts the daemon on the session's compositor with this test
// binary as its shell, once the shell has said hello.
func (s *Session) StartAxiom(kind string) *Proc {
	s.t.Helper()
	bin, src := os.Getenv("AXIOM_BIN"), os.Getenv("AXIOM_SRC")
	if bin == "" || src == "" {
		s.t.Fatal("AXIOM_BIN and AXIOM_SRC name the built axiom and its tree")
	}
	self, err := os.Executable()
	if err != nil {
		s.t.Fatal(err)
	}
	s.set("AXIOM_SRC", src)
	marker := filepath.Join(s.Runtime, "fakeshell-hello")
	os.Remove(marker)
	cmd := exec.Command(bin, "run", "--tree", src, "--qs", self)
	cmd.Env = s.env("CTR_FAKESHELL=1", "CTR_KIND="+kind, "AXIOM_BLUETOOTH_AGENT=off", "CTR_SRC="+src, "CTR_LOG="+filepath.Join(s.Out, "fakeshell.log"))
	p := s.run("axiom.out", cmd)
	s.keepDaemonLog()
	sock := filepath.Join(s.Runtime, "axiom", s.vars["WAYLAND_DISPLAY"], "axiom.sock")
	if !testkit.Eventually(func() bool { _, err := os.Stat(sock); return err == nil }) {
		s.t.Fatalf("axiom's socket didn't appear; log tail:\n%s%s", s.Tail("axiom.out", 30), s.Tail(daemonLog, 30))
	}
	if !testkit.Eventually(func() bool { _, err := os.Stat(marker); return err == nil }) {
		s.t.Fatalf("the fake shell never said hello; log tail:\n%s%s", s.Tail("axiom.out", 30), s.Tail(daemonLog, 30))
	}
	return p
}

// Axiom runs the axiom CLI against the session's daemon.
func (s *Session) Axiom(args ...string) string {
	s.t.Helper()
	sock := filepath.Join(s.Runtime, "axiom", s.vars["WAYLAND_DISPLAY"], "axiom.sock")
	cmd := exec.Command(os.Getenv("AXIOM_BIN"), append([]string{"--socket", sock}, args...)...)
	cmd.Env = s.env()
	out, err := cmd.CombinedOutput()
	if err != nil {
		s.t.Fatalf("axiom %v: %v\n%s", args, err, out)
	}
	return string(out)
}

// daemonLog names the daemon's own log (in the session's state dir) for
// LogSince, Tail and WaitLog; it's copied to the test's output at its end
const daemonLog = "daemon.log"

func (s *Session) logPath(name string) string {
	if name == daemonLog {
		return filepath.Join(s.State, "axiom", "log", "daemon.log")
	}
	return filepath.Join(s.Out, name)
}

func (s *Session) keepDaemonLog() {
	s.t.Cleanup(func() {
		if data, err := os.ReadFile(s.logPath(daemonLog)); err == nil {
			os.WriteFile(filepath.Join(s.Out, daemonLog), data, 0o644)
		}
	})
}

// LogSince is the log's text from byte offset on.
func (s *Session) LogSince(name string, offset int) string {
	data, _ := os.ReadFile(s.logPath(name))
	if offset > len(data) {
		return ""
	}
	return string(data[offset:])
}

// Tail is the log's last n lines.
func (s *Session) Tail(name string, n int) string {
	lines := strings.Split(s.LogSince(name, 0), "\n")
	if len(lines) > n {
		lines = lines[len(lines)-n:]
	}
	return strings.Join(lines, "\n")
}

// WaitLog waits until the log, from offset on, matches re.
func (s *Session) WaitLog(name string, re *regexp.Regexp, offset int) bool {
	return testkit.Eventually(func() bool { return re.MatchString(s.LogSince(name, offset)) })
}

var sigterm = syscall.SIGTERM

func formatFloat(f float64) string { return fmt.Sprintf("%.2f", f) }

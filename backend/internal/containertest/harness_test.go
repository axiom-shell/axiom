//go:build container

package containertest

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/buildinfo"
	"github.com/axiom-shell/axiom/backend/internal/daemon"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/session"
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
	if os.Getenv("CTR_FAKEPORTAL") == "1" {
		os.Exit(fakePortal())
	}
	os.Exit(m.Run())
}

// relaySock is the fake shell's socket for ShellCall: one JSON line in
// ({"method", "params"}), one out ({"result"} or {"error"}), so a test can
// make the shell-only calls the real shell makes
const relaySock = "ctr-shell.sock"

// fakeShell is the shell as far as the daemon can tell: it says hello as
// the shell, hands over the compositor inputs, relays a test's calls, and
// waits for SIGTERM. It also ends when the daemon's connection is gone for
// good (a SIGKILLed daemon leaves it behind otherwise); a re-exec's gap it
// waits out.
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
	hash := ""
	if data, err := os.ReadFile(os.Getenv("AXIOM_SCHEMA")); err == nil {
		hash = buildinfo.SchemaHash(data)
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
	var (
		connMu sync.Mutex
		conn   *rpc.Conn
	)
	connect := func(first bool) error {
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		c, err := rpc.Dial(ctx, sock, nil, nil)
		if err != nil {
			return err
		}
		// Up before the daemon has noted the shell's pid, which a real
		// shell (qs takes its time) never is: say hello again until it's
		// taken
		var hello daemon.HelloResult
		for try := 0; ; try++ {
			err = c.Call(ctx, "daemon.hello", daemon.HelloParams{Protocol: buildinfo.Protocol(), Client: "shell", SchemaHash: hash, PID: os.Getpid()}, &hello)
			if err == nil {
				break
			}
			if try >= 50 {
				return fmt.Errorf("hello (pid %d): %v", os.Getpid(), err)
			}
			time.Sleep(100 * time.Millisecond)
		}
		if err := c.Call(ctx, "compositor.inputs", params, nil); err != nil {
			return fmt.Errorf("compositor.inputs: %v", err)
		}
		connMu.Lock()
		conn = c
		connMu.Unlock()
		if first {
			// The marker says it
			os.WriteFile(filepath.Join(os.Getenv("XDG_RUNTIME_DIR"), "fakeshell-hello"), nil, 0o644)
		}
		return nil
	}
	if err := connect(true); err != nil {
		return fail("%v", err)
	}
	// The relay
	relayPath := filepath.Join(os.Getenv("XDG_RUNTIME_DIR"), relaySock)
	os.Remove(relayPath)
	if ln, err := net.Listen("unix", relayPath); err == nil {
		go func() {
			for {
				nc, err := ln.Accept()
				if err != nil {
					return
				}
				go relay(nc, func() *rpc.Conn { connMu.Lock(); defer connMu.Unlock(); return conn })
			}
		}()
	}
	// The daemon's end of the connection gone for good ends it
	go func() {
		for {
			connMu.Lock()
			c := conn
			connMu.Unlock()
			<-c.Done()
			var err error
			for range 30 {
				if err = connect(false); err == nil {
					break
				}
				time.Sleep(100 * time.Millisecond)
			}
			if err != nil {
				fmt.Fprintf(os.Stderr, "fakeshell: the daemon is gone: %v\n", err)
				os.Exit(0)
			}
		}
	}()
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGTERM, syscall.SIGINT)
	<-stop
	return 0
}

// relay answers one call a test sent through the relay socket.
func relay(nc net.Conn, conn func() *rpc.Conn) {
	defer nc.Close()
	line, err := bufio.NewReader(nc).ReadBytes('\n')
	if err != nil {
		return
	}
	var req struct {
		Method string          `json:"method"`
		Params json.RawMessage `json:"params"`
	}
	reply := map[string]any{}
	if err := json.Unmarshal(line, &req); err != nil {
		reply["error"] = err.Error()
	} else {
		var result json.RawMessage
		ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
		defer cancel()
		if err := conn().Call(ctx, req.Method, req.Params, &result); err != nil {
			reply["error"] = err.Error()
		} else {
			reply["result"] = result
		}
	}
	data, _ := json.Marshal(reply)
	nc.Write(append(data, '\n'))
}

// fakePortal owns a name on a bus (CTR_BUS, CTR_NAME), writes CTR_MARK+".up"
// once it does, and CTR_MARK+".term" when it gets SIGTERM, then exits: a
// portal for the restart to signal (the test process can't be one).
func fakePortal() int {
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	conn, err := dbus.Dial(ctx, os.Getenv("CTR_BUS"), dbus.Options{})
	if err != nil {
		fmt.Fprintln(os.Stderr, "fakeportal:", err)
		return 1
	}
	defer conn.Close()
	if _, err := conn.RequestName(ctx, os.Getenv("CTR_NAME"), 0); err != nil {
		fmt.Fprintln(os.Stderr, "fakeportal:", err)
		return 1
	}
	mark := os.Getenv("CTR_MARK")
	os.WriteFile(mark+".up", nil, 0o644)
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGTERM, syscall.SIGINT)
	select {
	case <-stop:
		os.WriteFile(mark+".term", nil, 0o644)
	case <-time.After(5 * time.Minute):
	}
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
	sway *Proc
}

// NewSession makes the directories and starts the session bus.
func NewSession(t *testing.T) *Session { return NewSessionWith(t) }

// NewSessionWith is NewSession with more environment (KEY=value) in the
// session's, the bus's too: what the programs it activates get.
func NewSessionWith(t *testing.T, extra ...string) *Session {
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
		"PATH": filepath.Join(s.Home, "bin") + ":" + os.Getenv("PATH"), "HOME": s.Home, "LANG": "C.UTF-8",
		"XDG_CONFIG_HOME": s.Config, "XDG_STATE_HOME": s.State, "XDG_DATA_HOME": s.Data,
		"XDG_CACHE_HOME": s.Cache, "XDG_RUNTIME_DIR": s.Runtime,
		// This scratch folder stands for the user manager's: the daemon
		// runs the systemctl stub only for it (session.Scope.UnitsAllowed)
		"AXIOM_USER_RUNTIME_DIR":   s.Runtime,
		"DBUS_SESSION_BUS_ADDRESS": "unix:path=" + filepath.Join(s.Runtime, "bus"),
	}
	for _, kv := range extra {
		k, v, _ := strings.Cut(kv, "=")
		s.vars[k] = v
	}
	// Registered first, so it runs after every process has stopped
	t.Cleanup(func() {
		if data, err := os.ReadFile(s.logPath(daemonLog)); err == nil {
			os.WriteFile(filepath.Join(s.Out, daemonLog), data, 0o644)
		}
	})
	s.startDBus()
	return s
}

// env is the session's environment, plus extra (KEY=value).
func (s *Session) env(extra ...string) []string {
	var out []string
	for k, v := range s.vars {
		out = append(out, k+"="+v)
	}
	return append(out, extra...)
}

func (s *Session) set(k, v string) {
	s.vars[k] = v
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
	s.sway = p
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
	// niri's own Wayland display: what its clients (axiom) connect to
	prior := s.vars["WAYLAND_DISPLAY"]
	var display string
	testkit.Eventually(func() bool {
		m, _ := filepath.Glob(filepath.Join(s.Runtime, "wayland-*"))
		for _, path := range m {
			if base := filepath.Base(path); !strings.HasSuffix(base, ".lock") && base != prior {
				display = base
			}
		}
		return display != ""
	})
	if display == "" {
		s.t.Skipf("niri has no Wayland display of its own here; log tail:\n%s", s.Tail("niri.log", 20))
	}
	s.set("WAYLAND_DISPLAY", display)
}

// StartHyprlandNested writes config as Hyprland's own (hyprland.lua) and
// starts Hyprland inside the session's sway. It skips the test when it
// doesn't come up here. It sets HYPRLAND_INSTANCE_SIGNATURE.
func (s *Session) StartHyprlandNested(config string) {
	s.t.Helper()
	s.WriteFile(".config/hypr/hyprland.lua", config)
	cmd := exec.Command("Hyprland")
	cmd.Env = s.env("LIBGL_ALWAYS_SOFTWARE=1", "AQ_BACKENDS=wayland")
	p := s.run("hyprland.log", cmd)
	if !testkit.Eventually(func() bool { return s.glob("hypr/*/.socket.sock") != "" || isDone(p) }) || isDone(p) {
		// Its own log, after the config stopped stdout's
		own := ""
		if m, _ := filepath.Glob(filepath.Join(s.Runtime, "hypr", "*", "hyprland.log")); len(m) > 0 {
			data, _ := os.ReadFile(m[0])
			lines := strings.Split(string(data), "\n")
			own = strings.Join(lines[max(0, len(lines)-15):], "\n")
		}
		s.t.Skipf("Hyprland doesn't start nested here (alive: %v); log tail:\n%s\nits own log:\n%s", !isDone(p), s.Tail("hyprland.log", 8), own)
	}
	s.set("HYPRLAND_INSTANCE_SIGNATURE", filepath.Base(filepath.Dir(s.glob("hypr/*/.socket.sock"))))
}

// Hyprctl runs hyprctl against the session's Hyprland, never another.
func (s *Session) Hyprctl(args ...string) string {
	s.t.Helper()
	if s.vars["HYPRLAND_INSTANCE_SIGNATURE"] == "" {
		s.t.Fatal("no Hyprland of the session's is running")
	}
	cmd := exec.Command("hyprctl", args...)
	cmd.Env = s.env()
	out, err := cmd.CombinedOutput()
	if err != nil {
		s.t.Fatalf("hyprctl %v: %v\n%s", args, err, out)
	}
	return string(out)
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
func (s *Session) StartAxiom(kind string) *Proc { return s.StartAxiomWith(kind, nil, nil) }

// StartAxiomWith is StartAxiom with more environment (KEY=value) and more
// arguments to `axiom run`.
func (s *Session) StartAxiomWith(kind string, env, args []string) *Proc {
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
	cmd := exec.Command(bin, append([]string{"run", "--tree", src, "--qs", self}, args...)...)
	cmd.Env = s.env(append([]string{"CTR_FAKESHELL=1", "CTR_KIND=" + kind, "AXIOM_BLUETOOTH_AGENT=off", "CTR_SRC=" + src, "CTR_LOG=" + filepath.Join(s.Out, "fakeshell.log")}, env...)...)
	p := s.run("axiom.out", cmd)
	sock := s.axiomSock()
	if !testkit.Eventually(func() bool { _, err := os.Stat(sock); return err == nil }) {
		s.t.Fatalf("axiom's socket didn't appear; log tail:\n%s%s", s.Tail("axiom.out", 30), s.Tail(daemonLog, 30))
	}
	if !testkit.Eventually(func() bool { _, err := os.Stat(marker); return err == nil }) {
		s.t.Fatalf("the fake shell never said hello; log tail:\n%s%s", s.Tail("axiom.out", 30), s.Tail(daemonLog, 30))
	}
	return p
}

func (s *Session) axiomSock() string {
	return filepath.Join(s.Runtime, "axiom", s.vars["WAYLAND_DISPLAY"], "axiom.sock")
}

// Axiom runs the axiom CLI against the session's daemon.
func (s *Session) Axiom(args ...string) string {
	s.t.Helper()
	out, err := s.AxiomTry(args...)
	if err != nil {
		s.t.Fatalf("axiom %v: %v\n%s", args, err, out)
	}
	return out
}

// AxiomTry is Axiom, with the error returned.
func (s *Session) AxiomTry(args ...string) (string, error) {
	cmd := exec.Command(os.Getenv("AXIOM_BIN"), append([]string{"--socket", s.axiomSock()}, args...)...)
	cmd.Env = s.env()
	out, err := cmd.CombinedOutput()
	return string(out), err
}

// SwaymsgTry is Swaymsg, with the error returned.
func (s *Session) SwaymsgTry(args ...string) (string, error) {
	cmd := exec.Command("swaymsg", append([]string{"-s", s.vars["SWAYSOCK"]}, args...)...)
	cmd.Env = s.env()
	out, err := cmd.CombinedOutput()
	return string(out), err
}

// ShellCall makes a call as the shell would, through the fake shell (the
// shell-only methods: polkit.stopOthers, screenshare.restartPortal, …).
func (s *Session) ShellCall(method string, params any) (json.RawMessage, error) {
	s.t.Helper()
	nc, err := net.DialTimeout("unix", filepath.Join(s.Runtime, relaySock), 5*time.Second)
	if err != nil {
		s.t.Fatalf("the fake shell's relay: %v", err)
	}
	defer nc.Close()
	nc.SetDeadline(time.Now().Add(30 * time.Second))
	req, _ := json.Marshal(map[string]any{"method": method, "params": params})
	if _, err := nc.Write(append(req, '\n')); err != nil {
		s.t.Fatal(err)
	}
	line, err := bufio.NewReader(nc).ReadBytes('\n')
	if err != nil {
		s.t.Fatalf("%s: no answer: %v", method, err)
	}
	var reply struct {
		Result json.RawMessage `json:"result"`
		Error  string          `json:"error"`
	}
	if err := json.Unmarshal(line, &reply); err != nil {
		s.t.Fatal(err)
	}
	if reply.Error != "" {
		return nil, errors.New(reply.Error)
	}
	return reply.Result, nil
}

// FakeProgram writes a program named name into ~/bin (on the session's
// PATH), a bash script. A program meant to be found by its command line
// starts with `exec -a "$0" …`, so its argv[0] is its own path.
func (s *Session) FakeProgram(name, script string) string {
	s.t.Helper()
	path := s.WriteFile("bin/"+name, "#!/bin/bash\n"+script+"\n")
	if err := os.Chmod(path, 0o755); err != nil {
		s.t.Fatal(err)
	}
	// What it started (the daemon starts programs of its own, too) goes
	// with the test
	s.t.Cleanup(func() {
		for _, p := range Procs(func(p ProcInfo) bool { return p.Argv[0] == path }) {
			syscall.Kill(p.PID, syscall.SIGKILL)
		}
	})
	return path
}

// Sleeper is the script of a program that only runs, under its own name
// (argv[0] is its path); its numeric arguments become the durations it
// sleeps, so they show in its argv and nothing else does (`-t 3000` is 3000).
const Sleeper = `n=(); for a in "$@"; do [[ $a =~ ^[0-9]+$ ]] && n+=("$a"); done; exec -a "$0" sleep "${n[@]:-600}"`

// SecondDisplayEnv is an environment that is out of the session's scope: a
// Wayland display of another session, the rest the session's.
func (s *Session) SecondDisplayEnv() []string {
	return s.env("WAYLAND_DISPLAY=wayland-other")
}

// StartProgram starts a program of the session in env (nil: the session's),
// stopped when the test ends.
func (s *Session) StartProgram(env []string, name string, args ...string) *Proc {
	s.t.Helper()
	if env == nil {
		env = s.env()
	}
	cmd := exec.Command(name, args...)
	cmd.Env = env
	return s.run("programs.log", cmd)
}

// StartSecondBus starts another session bus (a scratch session of its own)
// and returns its address.
func (s *Session) StartSecondBus() string {
	s.t.Helper()
	path := filepath.Join(s.Runtime, "bus2")
	cmd := exec.Command("dbus-daemon", "--session", "--nofork", "--address=unix:path="+path)
	cmd.Env = s.env()
	s.run("dbus2.log", cmd)
	if !testkit.Eventually(func() bool { _, err := os.Stat(path); return err == nil }) {
		s.t.Fatal("the second bus didn't come up")
	}
	return "unix:path=" + path
}

// OwnBusName holds name on the session bus from the test process: a fake
// org.freedesktop.systemd1. It lets go when the test ends.
func (s *Session) OwnBusName(name string) {
	s.t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	conn, err := dbus.Dial(ctx, s.vars["DBUS_SESSION_BUS_ADDRESS"], dbus.Options{})
	if err != nil {
		s.t.Fatal(err)
	}
	s.t.Cleanup(func() { conn.Close() })
	if _, err := conn.RequestName(ctx, name, 0); err != nil {
		s.t.Fatal(err)
	}
}

// FakePortal is a process owning name on the bus at address (the session's:
// ""), which says when it got SIGTERM.
type FakePortal struct {
	*Proc
	mark string
}

// StartFakePortal starts one.
func (s *Session) StartFakePortal(address, name string) *FakePortal {
	s.t.Helper()
	if address == "" {
		address = s.vars["DBUS_SESSION_BUS_ADDRESS"]
	}
	self, err := os.Executable()
	if err != nil {
		s.t.Fatal(err)
	}
	mark := filepath.Join(s.Runtime, "portal-"+strconv.Itoa(len(name))+"-"+filepath.Base(address))
	cmd := exec.Command(self)
	cmd.Env = s.env("CTR_FAKEPORTAL=1", "CTR_BUS="+address, "CTR_NAME="+name, "CTR_MARK="+mark)
	p := s.run("fakeportal.log", cmd)
	if !testkit.Eventually(func() bool { _, err := os.Stat(mark + ".up"); return err == nil }) {
		s.t.Fatalf("the fake portal never got %s", name)
	}
	return &FakePortal{Proc: p, mark: mark}
}

// Termed: it got SIGTERM.
func (f *FakePortal) Termed() bool { _, err := os.Stat(f.mark + ".term"); return err == nil }

// Record is the daemon's runtime session record, nil before there is one.
func (s *Session) Record() *session.Runtime {
	return session.ReadRuntime(filepath.Join(s.Runtime, "axiom", s.vars["WAYLAND_DISPLAY"], session.RuntimeFile), nil)
}

// Guard is the guard's pid from the record, once it wrote it.
func (s *Session) Guard() int {
	s.t.Helper()
	pid := 0
	if !testkit.Eventually(func() bool {
		if r := s.Record(); r != nil {
			pid = r.GuardPID
		}
		return pid > 0
	}) {
		s.t.Fatalf("no guard in the record; guard log:\n%s", s.guardLog())
	}
	return pid
}

func (s *Session) guardLog() string {
	data, _ := os.ReadFile(filepath.Join(s.State, "axiom", "log", "guard.log"))
	return string(data)
}

// GuardLog is the guard's log.
func (s *Session) GuardLog() string { return s.guardLog() }

// ProcInfo is a running process.
type ProcInfo struct {
	PID  int
	Argv []string
	Env  []string
}

// Procs are the processes running (the container's /proc) for which match
// is true.
func Procs(match func(ProcInfo) bool) []ProcInfo {
	var out []ProcInfo
	entries, _ := os.ReadDir("/proc")
	for _, e := range entries {
		pid, err := strconv.Atoi(e.Name())
		if err != nil {
			continue
		}
		cmdline, err := os.ReadFile(filepath.Join("/proc", e.Name(), "cmdline"))
		if err != nil || len(cmdline) == 0 {
			continue
		}
		environ, _ := os.ReadFile(filepath.Join("/proc", e.Name(), "environ"))
		p := ProcInfo{PID: pid, Argv: strings.Split(strings.TrimSuffix(string(cmdline), "\x00"), "\x00"), Env: strings.Split(strings.TrimSuffix(string(environ), "\x00"), "\x00")}
		if match(p) {
			out = append(out, p)
		}
	}
	return out
}

// Alive: the process runs (a zombie doesn't count).
func Alive(pid int) bool {
	data, err := os.ReadFile(filepath.Join("/proc", strconv.Itoa(pid), "stat"))
	if err != nil {
		return false
	}
	i := strings.LastIndexByte(string(data), ')')
	return i >= 0 && i+2 < len(data) && data[i+2] != 'Z'
}

// WaitGone waits for the process to end.
func WaitGone(pid int) bool { return testkit.Eventually(func() bool { return !Alive(pid) }) }

// HasEnv: the process's environment holds entry.
func (p ProcInfo) HasEnv(entry string) bool {
	for _, e := range p.Env {
		if e == entry {
			return true
		}
	}
	return false
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

// PingPortal calls xdg-desktop-portal on the session bus (which starts it
// when it isn't running) and returns the pid owning its name.
func (s *Session) PingPortal() (int, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	conn, err := dbus.Dial(ctx, s.vars["DBUS_SESSION_BUS_ADDRESS"], dbus.Options{})
	if err != nil {
		return 0, err
	}
	defer conn.Close()
	if _, err := conn.Call(ctx, "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop", "org.freedesktop.DBus.Peer", "Ping", ""); err != nil {
		return 0, err
	}
	pid, err := conn.ConnectionPID(ctx, "org.freedesktop.portal.Desktop")
	return int(pid), err
}

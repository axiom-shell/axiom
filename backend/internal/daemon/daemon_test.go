package daemon

import (
	"context"
	"encoding/json"
	"net"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/buildinfo"
	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/ipcroute"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
	"github.com/axiom-shell/axiom/backend/internal/topics"
	"github.com/axiom-shell/axiom/backend/internal/xdg"
)

// testDaemon is a daemon on scratch folders, running no shell.
type testDaemon struct {
	env     map[string]string
	socket  string
	dirs    xdg.Dirs
	runtime xdg.Runtime
	// registered sees the running daemon's registry
	registered func(*rpc.Registry)
}

func (td *testDaemon) getenv(k string) string { return td.env[k] }

// startDaemon runs a daemon until the test ends. isShell, when set,
// replaces the check that a peer is the shell.
func startDaemon(t *testing.T, isShell func(int) bool, sources ...topics.Source) *testDaemon {
	t.Helper()
	td := newTestDaemon(t)
	td.start(t, isShell, sources...)
	return td
}

// newTestDaemon is a daemon's scratch folders, not yet running.
func newTestDaemon(t *testing.T) *testDaemon {
	t.Helper()
	// Short: the socket path must fit a sockaddr_un
	runtimeDir, err := os.MkdirTemp("", "ax")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(runtimeDir) })
	home := t.TempDir()
	td := &testDaemon{env: map[string]string{
		"HOME":            home,
		"XDG_RUNTIME_DIR": runtimeDir,
		"WAYLAND_DISPLAY": "wayland-test",
		"XDG_CONFIG_HOME": filepath.Join(home, "config"),
		"XDG_STATE_HOME":  filepath.Join(home, "state"),
		"XDG_DATA_HOME":   filepath.Join(home, "data"),
		"XDG_CACHE_HOME":  filepath.Join(home, "cache"),
	}}
	td.dirs = xdg.Resolve(td.getenv)
	rt, err := xdg.ForDisplay(td.getenv, true)
	if err != nil {
		t.Fatal(err)
	}
	td.runtime = rt
	td.socket = rt.Socket()
	return td
}

// start runs the daemon until the test ends, once its socket is there.
func (td *testDaemon) start(t *testing.T, isShell func(int) bool, sources ...topics.Source) {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() {
		done <- Run(ctx, td.options(isShell, sources...))
	}()
	t.Cleanup(func() {
		cancel()
		select {
		case err := <-done:
			if err != nil {
				t.Errorf("run: %v", err)
			}
		case <-time.After(10 * time.Second):
			t.Error("the daemon didn't stop")
		}
	})
	// Ready once a connection gets through: the socket's file is there
	// from the bind, a moment before the listen, and a connect between
	// the two is refused
	deadline := time.Now().Add(10 * time.Second)
	for {
		if nc, err := net.Dial("unix", td.socket); err == nil {
			nc.Close()
			return
		}
		select {
		case err := <-done:
			t.Fatalf("the daemon stopped: %v", err)
		default:
		}
		if time.Now().After(deadline) {
			t.Fatal("no socket")
		}
		time.Sleep(10 * time.Millisecond)
	}
}

func (td *testDaemon) options(isShell func(int) bool, sources ...topics.Source) Options {
	return Options{Tree: testkit.RepoRoot(), NoShell: true, Getenv: td.getenv, isShell: isShell, topics: sources, registered: td.registered}
}

// connect dials the daemon and says hello as client; the connection's
// pushes go to pushes (nil: dropped).
func (td *testDaemon) connect(t *testing.T, client string, subscribe any, pushes chan<- string) (*rpc.Conn, error) {
	t.Helper()
	reg := rpc.NewRegistry()
	if pushes != nil {
		for _, method := range []string{"config.changed", "config.state", "schema.changed", "saved.state", "daemon.state", "dev.state", "probe.state"} {
			rpc.Handle(reg, method, func(context.Context, *rpc.Conn, json.RawMessage) (struct{}, error) {
				pushes <- method
				return struct{}{}, nil
			})
		}
	}
	c, err := rpc.Dial(context.Background(), td.socket, reg, nil)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { c.Close() })
	params := map[string]any{"protocol": buildinfo.Protocol(), "client": client, "pid": os.Getpid()}
	if subscribe != nil {
		params["subscribe"] = subscribe
	}
	var hello HelloResult
	return c, c.Call(context.Background(), "daemon.hello", params, &hello)
}

func TestOnlyTheShellMaySayItIsTheShell(t *testing.T) {
	t.Parallel()
	td := startDaemon(t, nil) // no shell runs: no peer is it
	if _, err := td.connect(t, "shell", nil, nil); axerr.KindOf(err) != axerr.Refused {
		t.Errorf("a stranger as the shell: %v", err)
	}
	c, err := td.connect(t, "cli", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	if err := c.Call(ctx, "lock.state", map[string]any{"locked": true, "surfaces": 1, "outputs": 1}, nil); axerr.KindOf(err) != axerr.Refused {
		t.Errorf("lock.state from the CLI: %v", err)
	}
	if err := c.Call(ctx, "ipc.register", map[string]any{"targets": []any{}}, nil); axerr.KindOf(err) != axerr.Refused {
		t.Errorf("ipc.register from the CLI: %v", err)
	}
}

func TestShellPeerIsAccepted(t *testing.T) {
	t.Parallel()
	td := startDaemon(t, func(pid int) bool { return pid == os.Getpid() })
	if _, err := td.connect(t, "shell", true, nil); err != nil {
		t.Errorf("the shell's hello: %v", err)
	}
}

func TestLockScreenOnlyTakesLock(t *testing.T) {
	t.Parallel()
	td := startDaemon(t, nil)
	c, err := td.connect(t, "cli", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	for _, fn := range []string{"unlock", "toggle", "Unlock", ""} {
		err := c.Call(context.Background(), "ipc.call", ipcroute.CallParams{Target: "lockscreen", Function: fn}, nil)
		if axerr.KindOf(err) != axerr.Refused {
			t.Errorf("lockscreen %q: %v", fn, err)
		}
	}
}

// A hello from another version hears the protocol mismatch even when it
// carries a key this binary doesn't know (params are otherwise strict).
func TestHelloFromAnotherVersion(t *testing.T) {
	t.Parallel()
	td := startDaemon(t, nil)
	c, err := rpc.Dial(context.Background(), td.socket, nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	ctx := context.Background()
	newer := map[string]any{"protocol": buildinfo.Protocol() + 1, "client": "cli", "pid": os.Getpid(), "later": true}
	if err := c.Call(ctx, "daemon.hello", newer, nil); axerr.KindOf(err) != axerr.Incompatible {
		t.Errorf("a newer client's hello: %v", err)
	}
	newer["protocol"] = buildinfo.Protocol()
	if err := c.Call(ctx, "daemon.hello", newer, nil); err != nil {
		t.Errorf("a hello with an extra key: %v", err)
	}
}

func TestNothingBeforeHello(t *testing.T) {
	t.Parallel()
	td := startDaemon(t, nil)
	c, err := rpc.Dial(context.Background(), td.socket, nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	if err := c.Call(context.Background(), "config.get", nil, nil); axerr.KindOf(err) != axerr.BadRequest {
		t.Errorf("config.get before hello: %v", err)
	}
}

func TestPushesFollowTopics(t *testing.T) {
	t.Parallel()
	td := startDaemon(t, nil)
	all := make(chan string, 16)
	savedOnly := make(chan string, 16)
	writer, err := td.connect(t, "cli", true, all)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := td.connect(t, "cli", []string{"saved"}, savedOnly); err != nil {
		t.Fatal(err)
	}
	if _, err := td.connect(t, "cli", []string{"nope"}, nil); axerr.KindOf(err) != axerr.BadRequest {
		t.Errorf("an unknown topic: %v", err)
	}
	ops := []config.Op{config.SetValue(config.Keys("Battery", "lowThreshold"), 15.0)}
	if err := writer.Call(context.Background(), "config.set", map[string]any{"ops": ops}, nil); err != nil {
		t.Fatal(err)
	}
	select {
	case m := <-all:
		if m != "config.changed" {
			t.Errorf("first push %s", m)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("no push to a subscriber of everything")
	}
	select {
	case m := <-savedOnly:
		if strings.HasPrefix(m, "config.") {
			t.Errorf("a config push to a saved-only subscriber: %s", m)
		}
	case <-time.After(200 * time.Millisecond):
	}
}

// A polled topic runs only while a connection subscribes, pushes only to
// it, and stops when it closes. A hello subscribing to everything doesn't
// subscribe to it.
func TestPolledTopicFollowsItsSubscribers(t *testing.T) {
	t.Parallel()
	var fetches atomic.Int64
	td := startDaemon(t, nil, topics.Source{Name: "probe", Floor: 10 * time.Millisecond, Default: time.Hour,
		Fetch: func(ctx context.Context, requests []json.RawMessage) (any, error) {
			return fetches.Add(1), nil
		}})
	all := make(chan string, 64)
	if _, err := td.connect(t, "cli", true, all); err != nil {
		t.Fatal(err)
	}
	pushes := make(chan string, 64)
	sub, err := td.connect(t, "cli", false, pushes)
	if err != nil {
		t.Fatal(err)
	}
	time.Sleep(50 * time.Millisecond)
	if n := fetches.Load(); n != 0 {
		t.Fatalf("%d fetches with nobody subscribed", n)
	}
	if err := sub.Call(context.Background(), "probe.subscribe", map[string]any{"interval": 10}, nil); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 2; i++ {
		select {
		case m := <-pushes:
			if m != "probe.state" {
				t.Errorf("push %s", m)
			}
		case <-time.After(5 * time.Second):
			t.Fatal("no state")
		}
	}
	select {
	case m := <-all:
		t.Errorf("%s pushed to a connection that didn't subscribe", m)
	default:
	}
	sub.Close()
	deadline := time.Now().Add(5 * time.Second)
	for {
		before := fetches.Load()
		time.Sleep(100 * time.Millisecond)
		if fetches.Load() == before {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("still fetching after its subscriber closed")
		}
	}
}

func TestDevModeIsSwitchedAndRemembered(t *testing.T) {
	t.Parallel()
	td := startDaemon(t, nil)
	pushes := make(chan string, 16)
	c, err := td.connect(t, "cli", []string{"daemon"}, pushes)
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	if err := c.Call(ctx, "dev.rebuild", nil, nil); axerr.KindOf(err) != axerr.Unavailable {
		t.Errorf("a rebuild with dev mode off: %v", err)
	}
	var st DevState
	if err := c.Call(ctx, "dev.set", map[string]bool{"enabled": true}, &st); err != nil || !st.Enabled {
		t.Fatalf("dev.set: %v %+v", err, st)
	}
	if !loadDevChoice(td.dirs) {
		t.Error("the choice wasn't saved")
	}
	seen := map[string]bool{}
	for len(seen) < 2 {
		select {
		case m := <-pushes:
			seen[m] = true
		case <-time.After(5 * time.Second):
			t.Fatalf("pushes %v", seen)
		}
	}
	if !seen["dev.state"] || !seen["daemon.state"] {
		t.Errorf("pushes %v", seen)
	}
	if err := c.Call(ctx, "dev.set", map[string]bool{"enabled": false}, &st); err != nil || st.Enabled {
		t.Fatalf("dev.set off: %v %+v", err, st)
	}
	if loadDevChoice(td.dirs) {
		t.Error("the choice wasn't saved off")
	}
}

func TestWritableFollowsDevMode(t *testing.T) {
	t.Parallel()
	d := &Daemon{}
	d.dev = &devMode{d: d, changed: make(chan struct{}, 1)}
	d.treeMatches = false
	if err := d.writable(); axerr.KindOf(err) != axerr.Incompatible {
		t.Errorf("another schema, dev off: %v", err)
	}
	if env := d.shellEnvNow(); env["AXIOM_INCOMPATIBLE"] == "" {
		t.Error("the shell isn't told it's read-only")
	}
	d.dev.enabled = true
	if err := d.writable(); err != nil {
		t.Errorf("another schema, dev on: %v", err)
	}
	d.dev.enabled = false
	d.treeMatches = true
	if err := d.writable(); err != nil || d.shellEnvNow() != nil {
		t.Errorf("this binary's schema: %v", err)
	}
}

func TestEmbeddedSchemaMatch(t *testing.T) {
	t.Parallel()
	hash := buildinfo.SchemaHash([]byte(`{"type":"object"}`))
	if !embeddedMatches(hash, hash) {
		t.Error("the embedded schema doesn't match itself")
	}
	if embeddedMatches(hash, buildinfo.SchemaHash([]byte(`{}`))) {
		t.Error("another schema matches")
	}
	if embeddedMatches("", hash) {
		t.Error("a missing embedded schema counts as this binary's")
	}
}

func TestHandoffIsChecked(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		name, raw string
		ok        bool
	}{
		{"none", "", true},
		{"not json", "{", false},
		{"stdio descriptors", `{"lock":0,"configLock":4,"listener":5}`, false},
		{"no listener", `{"lock":3,"configLock":4}`, false},
		{"whole", `{"lock":3,"configLock":4,"listener":5,"shell":42,"locked":true,"dev":true,"installed":"/usr/bin/axiom"}`, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			h, err := inherited(func(string) string { return tc.raw })
			if (err == nil) != tc.ok {
				t.Fatalf("err %v", err)
			}
			if tc.name == "whole" && (!h.Dev || h.Installed != "/usr/bin/axiom" || h.Shell != 42 || !h.Locked) {
				t.Errorf("handoff %+v", h)
			}
		})
	}
}

// Every polled topic names its request and state types (what rpc.md shows)
func TestSourcesDeclareTypes(t *testing.T) {
	t.Parallel()
	d := &Daemon{opts: Options{Getenv: func(string) string { return "" }}}
	for _, src := range d.sources() {
		if src.Request == nil || src.State == nil {
			t.Errorf("topic %s declares no request or state type", src.Name)
		}
	}
}

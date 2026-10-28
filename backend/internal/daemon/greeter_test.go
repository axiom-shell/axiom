package daemon

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/buildinfo"
	"github.com/axiom-shell/axiom/backend/internal/command"
	"github.com/axiom-shell/axiom/backend/internal/files"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/topics"
)

// shortDir is a temp folder short enough for a socket's path.
func shortDir(t *testing.T) string {
	t.Helper()
	dir, err := os.MkdirTemp("", "ax")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(dir) })
	return dir
}

// The greeter's axiom answers its quickshell's hello alone, then only its
// commands and lookups: nothing of the session's daemon (config, lock,
// compositor) is there to reach.
func TestGreeterRegistryAnswersOnlyTheGreeter(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name    string
		shell   bool
		client  string
		schema  string
		method  string
		want    axerr.Kind // "" for an answer
		wantOut string
	}{
		{name: "its quickshell runs a command", shell: true, client: "shell", method: "exec.run", wantOut: "hi\n"},
		{name: "the hello names another schema", shell: true, client: "shell", schema: "other", want: axerr.Incompatible},
		{name: "another process", client: "shell", want: axerr.Refused},
		{name: "a CLI client", shell: true, client: "cli", want: axerr.Refused},
		{name: "the session daemon's methods aren't there", shell: true, client: "shell", method: "config.set", want: axerr.Unavailable},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			path := filepath.Join(shortDir(t), "s.sock")
			ln, err := rpc.Listen(path)
			if err != nil {
				t.Fatal(err)
			}
			o := GreeterOptions{SchemaHash: "abc", Getenv: func(string) string { return "" }}
			reg := greeterRegistry(o, os.Environ(), func(int) bool { return c.shell }, command.NewWatches(command.WatchOptions{Method: pushExecOutputs.Method}), topics.New(topics.Options{}), files.New(files.Options{}), nil, func(any) {})
			ctx, cancel := context.WithCancel(context.Background())
			t.Cleanup(cancel)
			go (&rpc.Server{Registry: reg}).Serve(ctx, ln)
			conn, err := rpc.Dial(ctx, path, rpc.NewRegistry(), nil)
			if err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { conn.Close() })

			if err := conn.Call(ctx, "exec.run", map[string]any{"argv": []string{"true"}}, nil); axerr.KindOf(err) != axerr.BadRequest {
				t.Errorf("a call before the hello: %v, want bad_request", err)
			}
			schema := c.schema
			if schema == "" {
				schema = "abc"
			}
			var hello HelloResult
			err = conn.Call(ctx, "daemon.hello", HelloParams{Protocol: buildinfo.Protocol(), Client: c.client, SchemaHash: schema}, &hello)
			if c.method == "" {
				if axerr.KindOf(err) != c.want {
					t.Fatalf("hello: %v, want %s", err, c.want)
				}
				return
			}
			if err != nil || !hello.Compatible || hello.SchemaHash != "abc" {
				t.Fatalf("hello: %+v, %v", hello, err)
			}
			var res command.Result
			err = conn.Call(ctx, c.method, map[string]any{"argv": []string{"echo", "hi"}}, &res)
			if c.want != "" {
				if axerr.KindOf(err) != c.want {
					t.Errorf("%s: %v, want %s", c.method, err, c.want)
				}
				return
			}
			if err != nil || res.Stdout != c.wantOut {
				t.Errorf("%s: %+v, %v", c.method, res, err)
			}
		})
	}
}

// The greeter's Weather module subscribes to the weather topic, its state
// (GreetdManager's) is written through file.write, and on Hyprland its
// HyprlandManager sends hypr.request (monitors, layouts, the cursor), and
// on niri its NiriManager sends niri.request and watches niri.watch.
func TestGreeterServesWeather(t *testing.T) {
	t.Parallel()
	reg := greeterRegistry(GreeterOptions{Getenv: func(string) string { return "" }}, nil, func(int) bool { return true }, command.NewWatches(command.WatchOptions{Method: pushExecOutputs.Method}), topics.New(topics.Options{}), files.New(files.Options{}), nil, func(any) {})
	for _, m := range []string{"weather.subscribe", "weather.unsubscribe", "weather.refresh", "file.write", "hypr.request", "niri.request", "niri.watch"} {
		if _, _, ok := reg.Types(m); !ok {
			t.Errorf("no %s", m)
		}
	}
}

// The greeter's quickshell watches commands too (a Button's label, a
// CommandOutput module), their outputs pushed to it.
func TestGreeterWatchesCommands(t *testing.T) {
	t.Parallel()
	path := filepath.Join(shortDir(t), "s.sock")
	ln, err := rpc.Listen(path)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	watches := command.NewWatches(command.WatchOptions{Method: pushExecOutputs.Method, Context: ctx})
	o := GreeterOptions{SchemaHash: "abc", Getenv: func(string) string { return "" }}
	go (&rpc.Server{Registry: greeterRegistry(o, os.Environ(), func(int) bool { return true }, watches, topics.New(topics.Options{Context: ctx}), files.New(files.Options{}), nil, func(any) {})}).Serve(ctx, ln)
	outputs := make(chan command.Outputs, 4)
	client := rpc.NewRegistry()
	rpc.Handle(client, pushExecOutputs.Method, func(_ context.Context, _ *rpc.Conn, p command.Outputs) (struct{}, error) {
		outputs <- p
		return struct{}{}, nil
	})
	conn, err := rpc.Dial(ctx, path, client, nil)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { conn.Close() })
	if err := conn.Call(ctx, "daemon.hello", HelloParams{Protocol: buildinfo.Protocol(), Client: "shell", SchemaHash: "abc"}, nil); err != nil {
		t.Fatal(err)
	}
	if err := conn.Call(ctx, "exec.watch", command.WatchRequest{Command: "echo hi", Mode: command.ModeOnce}, nil); err != nil {
		t.Fatal(err)
	}
	select {
	case p := <-outputs:
		if p.Outputs["echo hi"].Text != "hi" {
			t.Errorf("pushed %+v", p)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("no output pushed")
	}
}

// It lives as long as its quickshell: a failure is an error (the session
// script then tries the fallback config), and an ended ctx stops it.
func TestRunGreeterFollowsItsQuickshell(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name    string
		command []string
		cancel  bool
		wantErr bool
	}{
		{name: "it exits", command: []string{"true"}},
		{name: "it fails", command: []string{"false"}, wantErr: true},
		{name: "it's stopped", command: []string{"sleep", "30"}, cancel: true},
		{name: "it can't start", command: []string{"/nonexistent/qs"}, wantErr: true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()
			if c.cancel {
				time.AfterFunc(100*time.Millisecond, cancel)
			}
			dir := shortDir(t)
			start := time.Now()
			err := RunGreeter(ctx, GreeterOptions{Command: c.command, Dir: dir, Getenv: os.Getenv})
			if (err != nil) != c.wantErr {
				t.Errorf("RunGreeter = %v, want an error: %v", err, c.wantErr)
			}
			if time.Since(start) > 10*time.Second {
				t.Errorf("took %v", time.Since(start))
			}
			if _, err := os.Stat(filepath.Join(dir, greeterSocket)); err == nil {
				t.Error("its socket is left behind")
			}
		})
	}
}

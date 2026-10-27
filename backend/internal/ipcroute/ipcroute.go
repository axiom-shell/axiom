// Package ipcroute is how `axiom ipc <target> <fn> [args]` and the named
// commands (`axiom launcher toggle`) reach the shell. The shell registers
// its IPC targets with the daemon over its connection (ipc.register), and
// a call goes back over that connection (ipc.call): no process per key
// press, and nothing reaches the shell any other way.
package ipcroute

import (
	"context"
	"fmt"
	"sort"
	"strconv"
	"sync"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
)

// Function is one function of a target: its name and how many arguments
// it takes (JavaScript has no parameter types to read; the shell's typed
// parameters convert the text they're given).
type Function struct {
	Name string `json:"name"`
	Args int    `json:"args"`
}

// Target is one IpcTarget of the shell.
type Target struct {
	Name      string     `json:"name"`
	Functions []Function `json:"functions"`
}

// Options configure a Router.
type Options struct {
	Timeout time.Duration
}

// Router routes calls to the shell.
type Router struct {
	opts Options

	mu      sync.Mutex
	shell   *rpc.Conn
	targets map[string]Target
}

// New returns a router.
func New(opts Options) *Router {
	if opts.Timeout == 0 {
		opts.Timeout = 5 * time.Second
	}
	return &Router{opts: opts, targets: map[string]Target{}}
}

// Register records the targets the shell registered on conn, replacing
// what it registered before (a QML reload registers anew). It does
// nothing, and says so, when conn has closed.
func (r *Router) Register(conn *rpc.Conn, targets []Target) bool {
	byName := make(map[string]Target, len(targets))
	for _, t := range targets {
		byName[t.Name] = t
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	select {
	case <-conn.Done():
		return false
	default:
	}
	r.shell, r.targets = conn, byName
	return true
}

// Forget drops a shell connection's targets when it closes.
func (r *Router) Forget(conn *rpc.Conn) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.shell == conn {
		r.shell = nil
		r.targets = map[string]Target{}
	}
}

// Targets is what the shell has registered.
func (r *Router) Targets() []Target {
	r.mu.Lock()
	defer r.mu.Unlock()
	out := make([]Target, 0, len(r.targets))
	for _, t := range r.targets {
		out = append(out, t)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out
}

// CallParams name a function and its arguments, as text (the command
// line's).
type CallParams struct {
	Target   string   `json:"target"`
	Function string   `json:"function"`
	Args     []string `json:"args"`
}

// Call calls a function of the shell and returns its result as text.
func (r *Router) Call(ctx context.Context, p CallParams) (string, error) {
	if p.Target == "" || p.Function == "" {
		return "", axerr.New(axerr.BadRequest, "name a target and a function")
	}
	r.mu.Lock()
	conn := r.shell
	target, registered := r.targets[p.Target]
	r.mu.Unlock()

	if conn == nil {
		return "", axerr.New(axerr.Unavailable, "the shell isn't connected")
	}
	if !registered {
		return "", axerr.New(axerr.NotFound, "the shell has no IPC target %s", p.Target)
	}
	fn, ok := find(target, p.Function)
	if !ok {
		return "", axerr.New(axerr.NotFound, "%s has no function %s", p.Target, p.Function)
	}
	if len(p.Args) != fn.Args {
		return "", axerr.New(axerr.BadRequest, "%s takes %d arguments, got %d", fn.Name, fn.Args, len(p.Args))
	}
	ctx, cancel := context.WithTimeout(ctx, r.opts.Timeout)
	defer cancel()
	args := p.Args
	if args == nil {
		args = []string{}
	}
	var result any
	if err := conn.Call(ctx, "ipc.call", map[string]any{"target": p.Target, "function": p.Function, "args": args}, &result); err != nil {
		return "", err
	}
	return format(result), nil
}

func find(t Target, name string) (Function, bool) {
	for _, f := range t.Functions {
		if f.Name == name {
			return f, true
		}
	}
	return Function{}, false
}

func format(v any) string {
	switch t := v.(type) {
	case nil:
		return ""
	case string:
		return t
	case bool:
		return strconv.FormatBool(t)
	case float64:
		return strconv.FormatFloat(t, 'f', -1, 64)
	}
	return fmt.Sprint(v)
}

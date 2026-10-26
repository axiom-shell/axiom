// Package ipcroute is how `axiom ipc <target> <fn> [args]` and the named
// commands (`axiom launcher toggle`) reach the shell. The shell registers
// its IPC targets with the daemon over its connection (ipc.register), and
// a call goes back over that connection (ipc.call): no process per key
// press. A target the shell hasn't registered is called by running
// `qs ipc --pid <the shell> call …`, exactly as before the daemon existed.
package ipcroute

import (
	"bytes"
	"context"
	"fmt"
	"os/exec"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
)

// Arg is one argument of a function, typed as the IpcHandler declares it.
type Arg struct {
	Name string `json:"name"`
	Type string `json:"type"` // string, int, bool, real
}

// Function is one function of a target.
type Function struct {
	Name    string `json:"name"`
	Args    []Arg  `json:"args"`
	Returns string `json:"returns"`
}

// Target is one IpcTarget of the shell.
type Target struct {
	Name      string     `json:"name"`
	Functions []Function `json:"functions"`
	Enabled   bool       `json:"enabled"`
}

// Options configure a Router.
type Options struct {
	// QS is the quickshell binary; ShellPID the running shell's pid (0:
	// none), for the exec fallback
	QS       string
	ShellPID func() int
	Timeout  time.Duration
}

// Router routes calls to the shell.
type Router struct {
	opts Options

	mu      sync.Mutex
	shell   *rpc.Conn
	targets map[string]Target
	// The latest registration begun (Begin): an older one finishing late
	// is dropped
	generation int
}

// New returns a router.
func New(opts Options) *Router {
	if opts.Timeout == 0 {
		opts.Timeout = 5 * time.Second
	}
	if opts.QS == "" {
		opts.QS = "qs"
	}
	return &Router{opts: opts, targets: map[string]Target{}}
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
// line's), typed by the target's declaration on the fast path.
type CallParams struct {
	Target   string   `json:"target"`
	Function string   `json:"function"`
	Args     []string `json:"args"`
}

// Call calls a function of the shell and returns its result (as text,
// the way `qs ipc call` prints it).
func (r *Router) Call(ctx context.Context, p CallParams) (string, error) {
	if p.Target == "" || p.Function == "" {
		return "", axerr.New(axerr.BadRequest, "name a target and a function")
	}
	r.mu.Lock()
	conn, target, registered := r.shell, r.targets[p.Target], false
	if conn != nil {
		_, registered = r.targets[p.Target]
	}
	r.mu.Unlock()

	if registered {
		fn, ok := find(target, p.Function)
		if !ok {
			return "", axerr.New(axerr.NotFound, "%s has no function %s", p.Target, p.Function)
		}
		if !target.Enabled {
			return "", axerr.New(axerr.Unavailable, "%s isn't answering on this screen", p.Target)
		}
		args, err := coerce(fn, p.Args)
		if err != nil {
			return "", err
		}
		ctx, cancel := context.WithTimeout(ctx, r.opts.Timeout)
		defer cancel()
		var result any
		if err := conn.Call(ctx, "ipc.call", map[string]any{"target": p.Target, "function": p.Function, "args": args}, &result); err != nil {
			return "", err
		}
		return format(result), nil
	}
	return r.exec(ctx, p)
}

func find(t Target, name string) (Function, bool) {
	for _, f := range t.Functions {
		if f.Name == name {
			return f, true
		}
	}
	return Function{}, false
}

// coerce types the command line's text by the function's declaration, as
// qs ipc does.
func coerce(fn Function, args []string) ([]any, error) {
	if len(args) != len(fn.Args) {
		return nil, axerr.New(axerr.BadRequest, "%s takes %d arguments, got %d", fn.Name, len(fn.Args), len(args))
	}
	out := make([]any, len(args))
	for i, a := range fn.Args {
		text := args[i]
		switch a.Type {
		case "int":
			n, err := strconv.Atoi(text)
			if err != nil {
				return nil, axerr.New(axerr.BadRequest, "%s: %q isn't a whole number", a.Name, text)
			}
			out[i] = n
		case "real":
			f, err := strconv.ParseFloat(text, 64)
			if err != nil {
				return nil, axerr.New(axerr.BadRequest, "%s: %q isn't a number", a.Name, text)
			}
			out[i] = f
		case "bool":
			b, err := strconv.ParseBool(text)
			if err != nil {
				return nil, axerr.New(axerr.BadRequest, "%s: %q isn't true or false", a.Name, text)
			}
			out[i] = b
		default:
			out[i] = text
		}
	}
	return out, nil
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

// exec calls through `qs ipc --pid <shell> call`, for targets the shell
// hasn't registered (or before it has connected).
func (r *Router) exec(ctx context.Context, p CallParams) (string, error) {
	pid := 0
	if r.opts.ShellPID != nil {
		pid = r.opts.ShellPID()
	}
	if pid == 0 {
		return "", axerr.New(axerr.Unavailable, "the shell isn't running")
	}
	ctx, cancel := context.WithTimeout(ctx, r.opts.Timeout)
	defer cancel()
	argv := append([]string{"ipc", "--pid", strconv.Itoa(pid), "call", p.Target, p.Function}, p.Args...)
	cmd := exec.CommandContext(ctx, r.opts.QS, argv...)
	var out, errOut bytes.Buffer
	cmd.Stdout, cmd.Stderr = &out, &errOut
	if err := cmd.Run(); err != nil {
		if ctx.Err() != nil {
			// Timed out (or the caller gave up): the shell didn't answer,
			// which says nothing about the function existing
			return "", axerr.Wrap(axerr.Unavailable, ctx.Err(), "%s.%s didn't answer", p.Target, p.Function)
		}
		msg := strings.TrimSpace(errOut.String())
		if msg == "" {
			msg = err.Error()
		}
		return "", axerr.New(axerr.NotFound, "%s.%s: %s", p.Target, p.Function, msg)
	}
	return strings.TrimRight(out.String(), "\n"), nil
}

// ParseShow reads `qs ipc show`: each target and its functions' typed
// signatures ("target x" then "  function f(a: int): void").
func ParseShow(text string) map[string][]Function {
	out := map[string][]Function{}
	current := ""
	for _, line := range strings.Split(text, "\n") {
		trimmed := strings.TrimSpace(line)
		if name, ok := strings.CutPrefix(trimmed, "target "); ok {
			current = strings.TrimSpace(name)
			out[current] = nil
			continue
		}
		sig, ok := strings.CutPrefix(trimmed, "function ")
		if !ok || current == "" {
			continue
		}
		open, close := strings.Index(sig, "("), strings.LastIndex(sig, ")")
		if open < 0 || close < open {
			continue
		}
		fn := Function{Name: sig[:open], Returns: strings.TrimSpace(strings.TrimPrefix(sig[close+1:], ":"))}
		for _, part := range strings.Split(sig[open+1:close], ",") {
			name, typ, ok := strings.Cut(strings.TrimSpace(part), ":")
			if ok {
				fn.Args = append(fn.Args, Arg{Name: strings.TrimSpace(name), Type: strings.TrimSpace(typ)})
			}
		}
		out[current] = append(out[current], fn)
	}
	return out
}

// Signatures runs `qs ipc --pid <shell> show` for the shell's targets'
// functions.
func (r *Router) Signatures(ctx context.Context) (map[string][]Function, error) {
	pid := 0
	if r.opts.ShellPID != nil {
		pid = r.opts.ShellPID()
	}
	if pid == 0 {
		return nil, axerr.New(axerr.Unavailable, "the shell isn't running")
	}
	ctx, cancel := context.WithTimeout(ctx, r.opts.Timeout)
	defer cancel()
	out, err := exec.CommandContext(ctx, r.opts.QS, "ipc", "--pid", strconv.Itoa(pid), "show").Output()
	if err != nil {
		return nil, err
	}
	return ParseShow(string(out)), nil
}

// Begin starts a registration (its signatures are read meanwhile) and
// returns its generation, for RegisterNames.
func (r *Router) Begin() int {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.generation++
	return r.generation
}

// RegisterNames records the targets the shell registered by name on conn,
// with their functions read from `qs ipc show` (sigs), replacing what it
// registered before (a QML reload registers anew). It does nothing, and
// says so, when a later registration was begun or conn has closed: the
// shell's calls then keep their route (or fall back to qs ipc).
func (r *Router) RegisterNames(conn *rpc.Conn, generation int, names []string, sigs map[string][]Function) bool {
	targets := map[string]Target{}
	for _, n := range names {
		if fns, ok := sigs[n]; ok {
			targets[n] = Target{Name: n, Functions: fns, Enabled: true}
		}
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	select {
	case <-conn.Done():
		return false
	default:
	}
	if generation != r.generation {
		return false
	}
	r.shell, r.targets = conn, targets
	return true
}

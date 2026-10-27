package daemon

import (
	"context"
	"encoding/json"
	"os"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/buildinfo"
	"github.com/axiom-shell/axiom/backend/internal/chat"
	"github.com/axiom-shell/axiom/backend/internal/command"
	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/files"
	"github.com/axiom-shell/axiom/backend/internal/idle"
	"github.com/axiom-shell/axiom/backend/internal/ipcroute"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/lockscreen"
	"github.com/axiom-shell/axiom/backend/internal/nightlight"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/saved"
	"github.com/axiom-shell/axiom/backend/internal/store"
	"github.com/axiom-shell/axiom/backend/internal/supervise"
	"github.com/axiom-shell/axiom/backend/internal/xdg"
)

// Push topics: what a connection gets pushed, as it asked in its hello
const (
	topicConfig = "config" // config.changed, config.state, schema.changed, schema.error
	topicSaved  = "saved"  // saved.state
	topicDaemon = "daemon" // daemon.state, dev.state, daemon.closing
	// compositor.state, compositor.applied, compositor.notify, compositor.bindsMerged
	topicCompositor = "compositor"
	topicIdle       = "idle"      // idle.state
	topicWayland    = "wayland"   // wayland.state, nightlight.state
	topicClipboard  = "clipboard" // clipboard.state
)

// Pushes, each declared once with the type of its params and sent to the
// connections subscribed to its topic. The compositor's are the jsonx
// trees its manager builds, sent as jsonx writes them (encoding/json
// would escape their <, > and &): opaque.
var (
	pushConfigChanged = rpc.Push[configChanged]{Method: "config.changed"}
	pushConfigState   = rpc.Push[store.State]{Method: "config.state"}
	pushSchemaChanged = rpc.Push[schemaChanged]{Method: "schema.changed"}
	pushSchemaError   = rpc.Push[schemaError]{Method: "schema.error"}

	pushSavedState = rpc.Push[saved.State]{Method: "saved.state", Latest: true}

	pushDaemonState   = rpc.Push[DaemonState]{Method: "daemon.state", Latest: true}
	pushDevState      = rpc.Push[DevState]{Method: "dev.state", Latest: true}
	pushDaemonClosing = rpc.Push[daemonClosing]{Method: "daemon.closing"}

	pushCompositorState       = rpc.Push[json.RawMessage]{Method: "compositor.state", Latest: true}
	pushCompositorApplied     = rpc.Push[json.RawMessage]{Method: "compositor.applied"}
	pushCompositorNotify      = rpc.Push[json.RawMessage]{Method: "compositor.notify"}
	pushCompositorBindsMerged = rpc.Push[json.RawMessage]{Method: "compositor.bindsMerged"}

	pushIdleState = rpc.Push[idle.State]{Method: "idle.state", Latest: true}

	pushWaylandState    = rpc.Push[waylandState]{Method: "wayland.state", Latest: true}
	pushNightLightState = rpc.Push[nightlight.State]{Method: "nightlight.state", Latest: true}

	pushClipboardState = rpc.Push[clipboardState]{Method: "clipboard.state", Latest: true}

	// Not a hello topic: sent only to a connection watching commands
	// (exec.watch), every watched command's output in one
	pushExecOutputs = rpc.Push[command.Outputs]{Method: "exec.outputs", Latest: true}

	// Not a hello topic either: each piece of a reply, sent only to the
	// connection that asked for it (chat.send), one message each
	pushChatDelta = rpc.Push[chat.Delta]{Method: "chat.delta"}

	// Nor this: a watched file changed, sent only to the connections
	// watching it (file.watch), one message each
	pushFileChanged = rpc.Push[files.Changed]{Method: "file.changed"}

	// Nor niri's event stream: sent only to the connection watching it
	// (niri.watch), one message each. niri.started when the stream
	// (re)connects, before the events of niri's full state; niri.event
	// with each event as niri wrote it ({"WindowFocusChanged": {…}})
	pushNiriStarted = rpc.Push[struct{}]{Method: "niri.started"}
	pushNiriEvent   = rpc.Push[json.RawMessage]{Method: "niri.event"}
)

// compositorPushes are the compositor's pushes by method, for its
// manager's Push.
var compositorPushes = map[string]rpc.Push[json.RawMessage]{
	pushCompositorState.Method:       pushCompositorState,
	pushCompositorApplied.Method:     pushCompositorApplied,
	pushCompositorNotify.Method:      pushCompositorNotify,
	pushCompositorBindsMerged.Method: pushCompositorBindsMerged,
}

// session is what the daemon knows of one connection.
type session struct {
	Client string // "shell", "cli"
	PID    int
	// The topics pushed to it (all: every one, now and later)
	all    bool
	topics map[string]bool
}

type sessionKey struct{}

func sessionOf(c *rpc.Conn) *session {
	v, ok := c.Value(sessionKey{})
	if !ok {
		return nil
	}
	return v.(*session)
}

// fromShell: the connection is the shell's (its hello said so, and the
// daemon checked its peer is the shell it runs)
func fromShell(c *rpc.Conn) bool {
	s := sessionOf(c)
	return s != nil && s.Client == "shell"
}

// subscribedTo keeps the connections that asked for topic.
func subscribedTo(topic string) func(*rpc.Conn) bool {
	return func(c *rpc.Conn) bool {
		s := sessionOf(c)
		return s != nil && (s.all || s.topics[topic])
	}
}

// HelloParams open a session. The protocol must be this binary's; a client
// that read a schema says which (its md5), and must have read this one.
// Subscribe is true (every topic), false, or a list of topics.
type HelloParams struct {
	Protocol   int             `json:"protocol"`
	Client     string          `json:"client"`
	SchemaHash string          `json:"schemaHash,omitempty"`
	Subscribe  json.RawMessage `json:"subscribe,omitempty"`
	PID        int             `json:"pid"`
}

// UnmarshalJSON decodes a hello leniently, past rpc.DecodeStrict: a peer
// from another version may send a key this binary lacks, and must still
// hear the protocol mismatch (Incompatible), never a bad params.
func (p *HelloParams) UnmarshalJSON(data []byte) error {
	type plain HelloParams
	return json.Unmarshal(data, (*plain)(p))
}

// compatible refuses a client of another protocol, or one that read
// another schema than hash (the one this axiom built or was given).
func (p HelloParams) compatible(hash string) error {
	if p.Protocol != buildinfo.Protocol() {
		return axerr.New(axerr.Incompatible, "this axiom speaks protocol %d, the client %d: the shell's files and the binary are from different versions", buildinfo.Protocol(), p.Protocol)
	}
	if p.SchemaHash != "" && p.SchemaHash != hash {
		return axerr.New(axerr.Incompatible, "the client read another schema than this axiom has (restart the shell)")
	}
	return nil
}

// topics reads Subscribe.
func (p HelloParams) topics() (all bool, topics map[string]bool, err error) {
	if len(p.Subscribe) == 0 {
		return false, nil, nil
	}
	if err := json.Unmarshal(p.Subscribe, &all); err == nil {
		return all, nil, nil
	}
	var list []string
	if err := json.Unmarshal(p.Subscribe, &list); err != nil {
		return false, nil, axerr.New(axerr.BadRequest, "subscribe is true, false or a list of topics")
	}
	topics = map[string]bool{}
	for _, t := range list {
		switch t {
		case topicConfig, topicSaved, topicDaemon, topicCompositor, topicIdle, topicWayland, topicClipboard:
			topics[t] = true
		default:
			return false, nil, axerr.New(axerr.BadRequest, "no topic %q (config, saved, daemon, compositor, idle, wayland, clipboard)", t)
		}
	}
	return false, topics, nil
}

// HelloResult describes the daemon to a client.
type HelloResult struct {
	Protocol   int         `json:"protocol"`
	Version    string      `json:"version"`
	Commit     string      `json:"commit"`
	SchemaHash string      `json:"schemaHash"`
	PID        int         `json:"pid"`
	Display    string      `json:"display"`
	Tree       string      `json:"tree"`
	Dirs       xdg.Dirs    `json:"dirs"`
	State      store.State `json:"state"`
	// Compatible is false when the tree's schema isn't this binary's and
	// dev mode is off (the shell then runs read-only and says why); it
	// changes at runtime with dev mode, pushed as daemon.state
	Compatible bool     `json:"compatible"`
	Reason     string   `json:"reason,omitempty"`
	Dev        DevState `json:"dev"`
}

// DaemonState is daemon.state: what in the hello changes while it runs.
type DaemonState struct {
	Compatible bool   `json:"compatible"`
	Reason     string `json:"reason,omitempty"`
}

// daemonClosing announces that the daemon closes every connection on
// purpose: a re-exec (connect again) or a quit.
type daemonClosing struct {
	Reexec bool `json:"reexec"`
}

// closingWait is how long a re-exec or quit waits for the clients told
// it's closing to close their side first.
const closingWait = 300 * time.Millisecond

// announceClosing tells the daemon topic's subscribers that the daemon is
// about to close their connection, and waits (at most wait) for them to
// close it themselves: a peer that closes first sees no error (the
// shell's socket warns on every close it didn't make).
func announceClosing(server *rpc.Server, reexec bool, wait time.Duration) {
	if server == nil {
		return
	}
	keep := subscribedTo(topicDaemon)
	var told []*rpc.Conn
	for _, c := range server.Conns() {
		if keep(c) {
			told = append(told, c)
		}
	}
	pushDaemonClosing.Send(server, daemonClosing{Reexec: reexec}, subscribedTo(topicDaemon))
	deadline := time.After(wait)
	for _, c := range told {
		select {
		case <-c.Done():
		case <-deadline:
			return
		}
	}
}

// StatusResult is daemon.status.
type StatusResult struct {
	HelloResult
	Uptime  string            `json:"uptime"`
	Shell   *supervise.Status `json:"shell,omitempty"`
	Clients int               `json:"clients"`
}

type configResult struct {
	Revision int64           `json:"revision"`
	Config   json.RawMessage `json:"config"`
	State    store.State     `json:"state"`
}

type configChanged struct {
	Revision int64           `json:"revision"`
	Config   json.RawMessage `json:"config"`
}

// schemaChanged is schema.changed: the schema rebuilt in dev mode, and
// the file the shell reads it from.
type schemaChanged struct {
	Hash string `json:"hash"`
	Path string `json:"path"`
}

// schemaError is schema.error: why the schema's source didn't build.
type schemaError struct {
	Issues  []axerr.Issue `json:"issues"`
	Message string        `json:"message"`
}

type setParams struct {
	Ops      []config.Op `json:"ops"`
	Takeover bool        `json:"takeover"`
}

type restoreParams struct {
	Config   json.RawMessage `json:"config"`
	Takeover bool            `json:"takeover"`
}

type revisionResult struct {
	Revision int64 `json:"revision"`
}

func rawJSON(v any) json.RawMessage { return json.RawMessage(jsonx.MarshalCompact(v)) }

// corePart: the session, the daemon itself and the shell it runs.
func (d *Daemon) corePart() part {
	return part{name: "core", methods: d.coreMethods}
}

func (d *Daemon) coreMethods(reg *rpc.Registry) {
	rpc.Handle(reg, "daemon.hello", func(ctx context.Context, c *rpc.Conn, p HelloParams) (HelloResult, error) {
		_, hash := d.currentSchema()
		if err := p.compatible(hash); err != nil {
			return HelloResult{}, err
		}
		// Only the shell this daemon runs may say it is the shell: it
		// reports the lock and registers IPC targets
		if p.Client == "shell" && !d.isShell(c.PeerPID()) {
			return HelloResult{}, axerr.New(axerr.Refused, "only the shell axiom runs may connect as the shell")
		}
		all, topics, err := p.topics()
		if err != nil {
			return HelloResult{}, err
		}
		c.SetValue(sessionKey{}, &session{Client: p.Client, PID: p.PID, all: all, topics: topics})
		return d.hello(), nil
	})

	rpc.Handle(reg, "daemon.status", func(ctx context.Context, c *rpc.Conn, _ struct{}) (StatusResult, error) {
		res := StatusResult{HelloResult: d.hello(), Uptime: time.Since(d.started).Round(time.Second).String(), Clients: len(d.server.Conns())}
		if d.shell != nil {
			st := d.shell.Status()
			res.Shell = &st
		}
		return res, nil
	})

	rpc.Handle(reg, "daemon.shutdown", func(ctx context.Context, c *rpc.Conn, _ struct{}) (struct{}, error) {
		d.opts.Log.Info("asked to shut down", "client", sessionOf(c).Client)
		go func() {
			announceClosing(d.server, false, closingWait)
			d.stop()
		}()
		return struct{}{}, nil
	})

	rpc.Handle(reg, "daemon.reexec", func(ctx context.Context, c *rpc.Conn, _ struct{}) (struct{}, error) {
		d.reexecSoon(d.executable)
		return struct{}{}, nil
	})

	rpc.Handle(reg, "shell.restart", func(ctx context.Context, c *rpc.Conn, _ struct{}) (struct{}, error) {
		if d.shell == nil {
			return struct{}{}, axerr.New(axerr.Unavailable, "this daemon runs no shell")
		}
		return struct{}{}, d.restartShell(ctx)
	})
}

// reexecSoon re-execs into target once the reply that asked for it has
// gone out (the exec closes every connection).
func (d *Daemon) reexecSoon(target string) {
	d.tasks.Go(func(ctx context.Context) {
		select {
		case <-time.After(50 * time.Millisecond):
		case <-ctx.Done():
			return
		}
		if err := d.reexec(target); err != nil {
			d.opts.Log.Error("re-exec", "err", err)
		}
	})
}

// pushState tells the clients what changed in the hello's answer.
func (d *Daemon) pushState() {
	ok, reason := d.compatible()
	if ok && d.compositor != nil {
		// A mode the compositor's manager kept but couldn't save is saved now
		d.compositor.ConfigWritable()
	}
	pushDaemonState.Send(d.server, DaemonState{Compatible: ok, Reason: reason}, subscribedTo(topicDaemon))
}

// configPart: config.json, through the store.
func (d *Daemon) configPart() part {
	return part{name: "config", methods: d.configMethods, onConfig: d.onConfigEvent}
}

// onConfigEvent pushes a config change to the subscribed connections and
// keeps the snapshot current.
func (d *Daemon) onConfigEvent(ev store.Event) {
	if ev.Config != nil {
		if err := d.writeSnapshot(); err != nil {
			d.opts.Log.Error("writing the config snapshot", "err", err)
		}
		pushConfigChanged.Send(d.server, configChanged{Revision: ev.State.Revision, Config: rawJSON(ev.Config)}, subscribedTo(topicConfig))
	}
	pushConfigState.Send(d.server, ev.State, subscribedTo(topicConfig))
}

func (d *Daemon) configMethods(reg *rpc.Registry) {
	rpc.Handle(reg, "config.get", func(ctx context.Context, c *rpc.Conn, _ struct{}) (configResult, error) {
		cfg, st := d.store.Config()
		return configResult{Revision: st.Revision, Config: rawJSON(cfg), State: st}, nil
	})

	rpc.Handle(reg, "config.set", func(ctx context.Context, c *rpc.Conn, p setParams) (revisionResult, error) {
		if err := d.writable(); err != nil {
			return revisionResult{}, err
		}
		rev, err := d.store.Set(p.Ops, store.SetOptions{Takeover: p.Takeover})
		return revisionResult{Revision: rev}, err
	})

	// A whole config the shell's editors made (format 2): written as
	// config.set's ops would be
	rpc.Handle(reg, "config.replace", func(ctx context.Context, c *rpc.Conn, p restoreParams) (revisionResult, error) {
		if err := d.writable(); err != nil {
			return revisionResult{}, err
		}
		v, err := jsonx.Unmarshal(p.Config)
		obj, ok := v.(*jsonx.Object)
		if err != nil || !ok {
			return revisionResult{}, axerr.New(axerr.BadRequest, "config.replace takes a config object")
		}
		rev, err := d.store.Replace(obj, store.SetOptions{Takeover: p.Takeover})
		return revisionResult{Revision: rev}, err
	})

	// A config of any format axiom reads, put in place of the running one
	// (loaded as config.json is): it lifts a file that doesn't load
	rpc.Handle(reg, "config.restore", func(ctx context.Context, c *rpc.Conn, p restoreParams) (revisionResult, error) {
		if err := d.writable(); err != nil {
			return revisionResult{}, err
		}
		v, err := jsonx.Unmarshal(p.Config)
		if _, ok := v.(*jsonx.Object); err != nil || !ok {
			return revisionResult{}, axerr.New(axerr.BadRequest, "config.restore takes a config object")
		}
		rev, err := d.store.Restore(v, store.SetOptions{Takeover: p.Takeover})
		return revisionResult{Revision: rev}, err
	})

	rpc.Handle(reg, "config.ackFirstRun", func(ctx context.Context, c *rpc.Conn, _ struct{}) (struct{}, error) {
		d.store.AckFirstRun()
		return struct{}{}, nil
	})
}

// ipcPart: the shell's IPC targets, and the lock screen behind them.
func (d *Daemon) ipcPart() part {
	return part{name: "ipc", methods: d.ipcMethods}
}

func (d *Daemon) ipcMethods(reg *rpc.Registry) {
	rpc.Handle(reg, "ipc.register", func(ctx context.Context, c *rpc.Conn, p struct {
		Targets []ipcroute.Target `json:"targets"`
	}) (struct{}, error) {
		if !fromShell(c) {
			return struct{}{}, axerr.New(axerr.Refused, "only the shell registers IPC targets")
		}
		names := make([]string, 0, len(p.Targets))
		for _, t := range p.Targets {
			names = append(names, t.Name)
		}
		// The functions and their types come from quickshell itself; a
		// later registration (a QML reload) or the connection closing
		// meanwhile wins
		generation := d.router.Begin()
		d.tasks.Go(func(ctx context.Context) {
			sigs, err := d.router.Signatures(ctx)
			if err != nil {
				if ctx.Err() == nil {
					d.opts.Log.Warn("reading the shell's IPC functions (qs ipc show)", "err", err)
				}
				return
			}
			if d.router.RegisterNames(c, generation, names, sigs) {
				d.opts.Log.Debug("the shell registered its IPC targets", "targets", len(names))
			}
		})
		return struct{}{}, nil
	})

	rpc.Handle(reg, "ipc.call", func(ctx context.Context, c *rpc.Conn, p ipcroute.CallParams) (string, error) {
		// The lock screen goes through the locker, which confirms it: and
		// nothing but lock can be asked of it
		if p.Target == "lockscreen" {
			if p.Function != "lock" {
				return "", axerr.New(axerr.Refused, "the lock screen only takes lock (it unlocks with your password, never by request)")
			}
			return "", d.locker.Lock(ctx)
		}
		return d.router.Call(ctx, p)
	})

	rpc.Handle(reg, "ipc.list", func(ctx context.Context, c *rpc.Conn, _ struct{}) ([]ipcroute.Target, error) {
		return d.router.Targets(), nil
	})

	rpc.Handle(reg, "lock.lock", func(ctx context.Context, c *rpc.Conn, _ struct{}) (struct{}, error) {
		return struct{}{}, d.locker.Lock(ctx)
	})

	rpc.Handle(reg, "lock.state", func(ctx context.Context, c *rpc.Conn, p lockscreen.State) (struct{}, error) {
		if !fromShell(c) {
			return struct{}{}, axerr.New(axerr.Refused, "only the shell reports the lock state")
		}
		d.locker.Report(p)
		return struct{}{}, nil
	})
}

// writable refuses writes from a binary built for another schema outside
// dev mode: it would validate the shell's edits against the wrong shape.
func (d *Daemon) writable() error {
	if ok, reason := d.compatible(); !ok {
		return axerr.New(axerr.Incompatible, "%s", reason)
	}
	return nil
}

func (d *Daemon) hello() HelloResult {
	info := buildinfo.Get()
	_, st := d.store.Config()
	_, hash := d.currentSchema()
	ok, reason := d.compatible()
	return HelloResult{
		Protocol: info.Protocol, Version: info.Version, Commit: info.Commit,
		SchemaHash: hash, PID: os.Getpid(), Display: d.runtime.Display,
		Tree: d.opts.Tree, Dirs: d.dirs, State: st,
		Compatible: ok, Reason: reason, Dev: d.dev.State(),
	}
}

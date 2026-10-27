// Package daemon is `axiom run`: the parent of the shell. It takes the
// display's instance lock, builds the schema from the tree, opens the
// config, hands the shell both as files in the runtime directory (so the
// shell reads its config at once, already normalized), serves the socket,
// and supervises quickshell. Its pieces are parts (tasks.go): the core,
// the config, IPC and the lock, sharing, and dev mode.
package daemon

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"sync"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/buildinfo"
	"github.com/axiom-shell/axiom/backend/internal/clipboard"
	"github.com/axiom-shell/axiom/backend/internal/command"
	"github.com/axiom-shell/axiom/backend/internal/compositor/manager"
	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
	"github.com/axiom-shell/axiom/backend/internal/idle"
	"github.com/axiom-shell/axiom/backend/internal/ipcroute"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/lockscreen"
	"github.com/axiom-shell/axiom/backend/internal/nightlight"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/saved"
	"github.com/axiom-shell/axiom/backend/internal/schema"
	"github.com/axiom-shell/axiom/backend/internal/store"
	"github.com/axiom-shell/axiom/backend/internal/supervise"
	"github.com/axiom-shell/axiom/backend/internal/topics"
	"github.com/axiom-shell/axiom/backend/internal/tree"
	"github.com/axiom-shell/axiom/backend/internal/wayland/client"
	"github.com/axiom-shell/axiom/backend/internal/wayland/ctm"
	"github.com/axiom-shell/axiom/backend/internal/wayland/datacontrol"
	"github.com/axiom-shell/axiom/backend/internal/wayland/gamma"
	"github.com/axiom-shell/axiom/backend/internal/wayland/idlenotify"
	"github.com/axiom-shell/axiom/backend/internal/wayland/outputs"
	"github.com/axiom-shell/axiom/backend/internal/wayland/seat"
	"github.com/axiom-shell/axiom/backend/internal/wayland/vkbd"
	"github.com/axiom-shell/axiom/backend/internal/wayland/wire"
	"github.com/axiom-shell/axiom/backend/internal/xdg"
)

// Options configure a daemon.
type Options struct {
	Tree string // the axiom tree the shell runs from
	// Dev starts in dev mode whatever the saved choice ($XDG_STATE_HOME/
	// axiom/dev.json, which `axiom dev on|off` sets)
	Dev     bool
	NoShell bool   // don't start quickshell (tests, headless use)
	QS      string // the quickshell binary (default "qs")
	Go      string // the go binary dev mode builds with (default "go")
	Getenv  func(string) string
	Log     *slog.Logger
	// LogLevel, when set, follows dev mode: debug while it's on
	LogLevel *slog.LevelVar
	// ShellOutput gets the shell's stdout and stderr (nil: discarded)
	ShellOutput io.Writer

	// isShell replaces the check that a peer is the shell (tests)
	isShell func(pid int) bool
	// topics are polled topics added to the daemon's own (tests)
	topics []topics.Source
	// registered sees the registry once every part registered (tests)
	registered func(*rpc.Registry)
}

// Files in the runtime directory
const (
	SchemaFile   = "config.schema.json" // the schema, built from the tree
	SnapshotFile = "config.json"        // the config, normalized, for the shell's first read
	ShellPIDFile = "shell.pid"
)

// incompatibleReason is why a tree whose schema isn't this binary's runs
// read-only outside dev mode.
const incompatibleReason = "this axiom binary was built for another version of the shell's files: update the binary"

// Daemon is a running daemon.
type Daemon struct {
	opts    Options
	runtime xdg.Runtime
	dirs    xdg.Dirs
	started time.Time

	// The built schema (dev mode rebuilds it on the watch goroutine while
	// handlers read the hash), and whether it is the one this binary was
	// built with
	schemaMu    sync.Mutex
	schemaBytes []byte
	schemaHash  string
	treeMatches bool

	// executable is the image running; installed the binary it came from
	// (they differ while dev mode runs its own build)
	executable string
	installed  string
	instance   *fsx.Lock
	listener   net.Listener

	store     *store.Store
	saved     *saved.Service
	server    *rpc.Server
	shell     *supervise.Supervisor
	router    *ipcroute.Router
	locker    *lockscreen.Locker
	dev       *devMode
	savedKick *kicker
	// compositor is the compositor's config layer (nil without the tree's
	// tables)
	compositor *manager.Manager
	// The clients on the daemon's Wayland connection: the outputs, the
	// seat, idle notifications, and the connection itself
	outputs      *outputs.Tracker
	seat         *seat.Tracker
	idleNotifier *idlenotify.Notifier
	keyboard     *vkbd.Keyboard
	ctm          *ctm.Control
	gamma        *gamma.Control
	wayland      *waylandSession
	// nightLight warms the screens (on ctm or gamma)
	nightLight *nightlight.Service
	// clip is the clipboard's data control; clipboard its history
	clip      *datacontrol.Device
	clipboard *clipboard.History
	// idle is the Idle section's service
	idle *idle.Service
	// topics are the polled topics and their subscribers
	topics *topics.Hub
	// The commands the shell watches (exec.watch)
	watches *command.Watches
	// The commands running as its children (handed on by a re-exec)
	children command.Children
	tasks    *tasks
	stop     context.CancelFunc

	// isShell says whether a connection's peer pid is the shell's (a
	// hello as "shell" from anything else is refused)
	isShell func(pid int) bool
}

// Run runs the daemon until ctx ends or it is told to shut down.
func Run(ctx context.Context, opts Options) error {
	if opts.Log == nil {
		opts.Log = slog.New(slog.DiscardHandler)
	}
	if opts.QS == "" {
		opts.QS = "qs"
	}
	if opts.Go == "" {
		opts.Go = "go"
	}
	runtime, err := xdg.ForDisplay(opts.Getenv, true)
	if err != nil {
		return err
	}
	d := &Daemon{opts: opts, runtime: runtime, dirs: xdg.Resolve(opts.Getenv), started: time.Now()}
	d.isShell = opts.isShell
	if d.isShell == nil {
		d.isShell = func(pid int) bool { return pid > 0 && pid == d.shellPID() }
	}
	if d.executable, err = os.Executable(); err == nil {
		d.executable, _ = filepath.EvalSymlinks(d.executable)
	}
	d.installed = d.executable
	h, err := inherited(opts.Getenv)
	if err != nil {
		return err
	}
	var listener net.Listener
	if h != nil {
		if listener, err = d.adopt(h); err != nil {
			return err
		}
		if h.Installed != "" {
			d.installed = h.Installed
		}
		if h.Started > 0 {
			d.started = time.UnixMilli(h.Started)
		}
	} else if d.instance, err = fsx.TryLock(runtime.Lock()); err != nil {
		if axerr.KindOf(err) == axerr.Running {
			return &axerr.Error{Kind: axerr.Running, Message: "axiom is already running on " + runtime.Display, Err: err}
		}
		return err
	}
	defer d.instance.Release()

	// Dev mode: as the image before a re-exec had it, else --dev, else
	// the saved choice
	devOn := opts.Dev || loadDevChoice(d.dirs)
	if h != nil {
		devOn = h.Dev
	}
	d.dev = newDevMode(d, devOn)

	if err := d.loadSchema(); err != nil {
		return err
	}
	built, _ := d.currentSchema()
	parsed, err := jsonx.Unmarshal(built)
	if err != nil {
		return axerr.Wrap(axerr.Internal, err, "the built schema")
	}
	storeOpts := store.Options{
		Dir:      d.dirs.Config,
		Pipeline: config.V2Pipeline{S: schema.New(parsed)},
		Log:      opts.Log.With("part", "config"),
	}
	if h != nil {
		d.store, err = store.OpenAdopting(storeOpts, os.NewFile(uintptr(h.ConfigLock), "config.json.lock"))
	} else {
		d.store, err = store.Open(storeOpts)
	}
	if err != nil {
		return err
	}
	defer d.store.Close()
	if err := d.writeSnapshot(); err != nil {
		return err
	}

	if listener == nil {
		if listener, err = rpc.Listen(runtime.Socket()); err != nil {
			return err
		}
	}
	d.listener = listener
	ctx, d.stop = context.WithCancel(ctx)
	defer d.stop()
	d.tasks = &tasks{ctx: ctx}
	defer d.tasks.Wait()

	d.router = ipcroute.New(ipcroute.Options{QS: opts.QS, ShellPID: d.shellPID})
	d.locker = lockscreen.New(lockscreen.Options{
		AskShell: func(ctx context.Context) error {
			_, err := d.router.Call(ctx, ipcroute.CallParams{Target: "lockscreen", Function: "lock"})
			return err
		},
		StartLocked: d.startLocked,
		Mode:        func() string { return d.lockSetting("mode") },
		Command:     func() string { return d.lockSetting("lockCommand") },
		Log:         opts.Log.With("part", "lock"),
		Go:          d.tasks.Go,
	})
	d.saved = saved.New(saved.Options{
		Dir:      d.dirs.Config,
		Examples: filepath.Join(opts.Tree, "examples"),
		Home:     opts.Getenv("HOME"),
		UIState:  filepath.Join(d.dirs.UI, "savedconfigs.json"),
		Store:    d.store,
		Pipeline: d.store.Pipeline,
		Log:      opts.Log.With("part", "saved"),
		OnState: func(st saved.State) {
			// Also called while it opens, before there is a server
			if d.server != nil {
				pushSavedState.Send(d.server, st, subscribedTo(topicSaved))
			}
		},
	})
	// Whether the config still is its saved snapshot: off the store's
	// delivery, since an apply may hold the service meanwhile
	d.savedKick = newKicker(func(context.Context) { d.saved.Changed() })

	d.compositor = d.newCompositor()
	d.outputs = outputs.New(opts.Log.With("part", "wayland"))
	d.seat = seat.New()
	d.wayland = &waylandSession{onChange: d.pushWayland}
	d.idleNotifier = idlenotify.New(idlenotify.Options{
		Seat:     d.seat,
		Log:      opts.Log.With("part", "wayland"),
		OnChange: func() { d.idle.NotifierChanged() },
	})
	d.keyboard = vkbd.New(vkbd.Options{Seat: d.seat, OnChange: d.pushWayland, Gap: 2 * time.Millisecond})
	d.newNightLight()
	d.newClipboard()
	d.idle = d.newIdle()
	d.topics = topics.New(topics.Options{Log: opts.Log.With("part", "topics"), Context: ctx, Go: d.tasks.Go})
	d.watches = command.NewWatches(command.WatchOptions{Method: pushExecOutputs.Method, Options: d.commandOptions, Log: opts.Log.With("part", "exec"), Context: ctx, Go: d.tasks.Go})
	parts := []part{d.corePart(), d.configPart(), d.ipcPart(), d.sharingPart(), d.compositorPart(), d.topicsPart(), d.toolsPart(), d.execPart(), d.calendarPart(), d.themePart(), d.hookupPart(), d.selfUpdatePart(), d.brightnessPart(), d.idlePart(), d.waylandPart(), d.clipboardPart(), d.dev.part()}
	reg := d.registry(parts)
	if opts.registered != nil {
		opts.registered(reg)
	}
	d.server = &rpc.Server{
		Registry: reg,
		Log:      opts.Log.With("part", "rpc"),
		OnClose: func(c *rpc.Conn) {
			d.router.Forget(c)
			d.topics.Forget(c)
			d.watches.Forget(c)
		},
	}
	d.store.Subscribe(func(ev store.Event) {
		for _, p := range parts {
			if p.onConfig != nil {
				p.onConfig(ev)
			}
		}
	})

	serve := func(name string, fn func(context.Context) error) {
		d.tasks.Go(func(ctx context.Context) {
			if err := fn(ctx); err != nil {
				opts.Log.Error(name+" stopped", "err", err)
				d.stop()
			}
		})
	}
	serve("the socket", func(ctx context.Context) error { return d.server.Serve(ctx, listener) })
	for _, p := range parts {
		if p.run != nil {
			serve(p.name, p.run)
		}
	}
	// The daemon's own Wayland connection (its outputs), which also stops
	// it with the compositor: a daemon left over from a session that
	// ended would hold the display's lock, and the next session's `axiom
	// run` would find it taken
	if socket, err := wire.SocketPath(opts.Getenv); err != nil {
		opts.Log.Warn("no Wayland connection", "err", err)
	} else {
		serve("the Wayland connection", func(ctx context.Context) error {
			d.followCompositor(ctx, socket)
			return nil
		})
	}
	if !opts.NoShell {
		adopt := 0
		if h != nil {
			adopt = h.Shell
		}
		d.shell = supervise.New(supervise.Options{
			Command:  []string{opts.QS, "-p", opts.Tree},
			Env:      d.shellEnv(),
			EnvFunc:  d.shellEnvNow,
			PIDFile:  runtime.File(ShellPIDFile),
			Output:   opts.ShellOutput,
			Log:      opts.Log.With("part", "shell"),
			AdoptPID: adopt,
			OnExit:   func(int, bool) { d.locker.ShellExited() },
			OnStop:   func(int) { d.locker.ShellStopped() },
		})
		serve("the shell", d.shell.Run)
		if _, hash := d.currentSchema(); h != nil && h.Schema != "" && h.Schema != hash {
			// The shell read the schema of before (an update re-exec'd
			// into the new binary): its hello would be refused
			d.tasks.Go(func(ctx context.Context) {
				opts.Log.Info("the schema changed across the re-exec: restarting the shell")
				restart := d.restartShell
				if h.Locked {
					restart = d.startLocked
				}
				if err := restart(ctx); err != nil && ctx.Err() == nil {
					opts.Log.Error("restarting the shell for the new schema", "err", err)
				}
			})
		}
	}
	opts.Log.Info("axiom is running", "display", runtime.Display, "tree", opts.Tree, "socket", runtime.Socket(), "version", buildinfo.Get().Version, "reexec", h != nil, "dev", d.dev.Enabled())
	<-ctx.Done()
	d.tasks.Wait()
	opts.Log.Info("axiom stopped")
	return nil
}

// followCompositor runs the Wayland connection until ctx ends, and stops
// the daemon when the compositor is gone. If the connection fails
// otherwise (a protocol error), an idle one (wire.Watch) still watches
// for that.
func (d *Daemon) followCompositor(ctx context.Context, socket string) {
	log := d.opts.Log
	err := client.Run(ctx, socket, d.outputs, d.seat, d.idleNotifier, d.keyboard, d.ctm, d.gamma, d.clip, d.wayland)
	// Unavailable: no compositor to connect to, nor to watch
	if err != nil && !errors.Is(err, wire.ErrGone) && axerr.KindOf(err) != axerr.Unavailable {
		log.Warn("the Wayland connection failed: monitors aren't known", "err", err)
		err = wire.Watch(ctx, socket)
	}
	if errors.Is(err, wire.ErrGone) {
		log.Info("the compositor is gone: stopping")
		d.stop()
	} else if err != nil {
		log.Warn("not watching the compositor", "err", err)
	}
}

// registry is every part's methods, behind the hello.
func (d *Daemon) registry(parts []part) *rpc.Registry {
	reg := rpc.NewRegistry()
	reg.Before = func(c *rpc.Conn, method string) error {
		if method != "daemon.hello" && sessionOf(c) == nil {
			return axerr.New(axerr.BadRequest, "say daemon.hello first")
		}
		return nil
	}
	for _, p := range parts {
		if p.methods != nil {
			p.methods(reg)
		}
	}
	return reg
}

// loadSchema builds the tree's schema and writes it for the shell. A tree
// whose schema isn't the one this binary was built with is a different
// axiom: allowed in dev mode, otherwise the shell is told why it can't
// save (compatible).
func (d *Daemon) loadSchema() error {
	data, err := tree.BuildSchema(d.opts.Tree)
	if err != nil {
		return err
	}
	d.setSchema(data, buildinfo.SchemaHash(data))
	if ok, reason := d.compatible(); !ok {
		d.opts.Log.Error(reason, "tree", d.opts.Tree)
	} else if !d.matches() {
		d.opts.Log.Warn("the tree's schema isn't the one this binary was built with (fine in dev mode)")
	}
	return fsx.WriteFile(d.runtime.File(SchemaFile), data, 0o600)
}

// compatible: the config may be written. Outside dev mode only when the
// tree's schema is the one this binary was built with: otherwise the
// shell's edits would be validated against the wrong shape.
func (d *Daemon) compatible() (bool, string) {
	if d.matches() || d.dev.Enabled() {
		return true, ""
	}
	return false, incompatibleReason
}

// embeddedMatches: hash is the schema this binary embeds (embedded, its
// hash, empty for a binary built without its assets). Without one it fails
// closed: no schema counts as its own, so the config stays read-only
// outside dev mode.
func embeddedMatches(embedded, hash string) bool {
	return embedded != "" && embedded == hash
}

func (d *Daemon) matches() bool {
	d.schemaMu.Lock()
	defer d.schemaMu.Unlock()
	return d.treeMatches
}

func (d *Daemon) shellPID() int {
	if d.shell == nil {
		return 0
	}
	return d.shell.Status().PID
}

// startLocked (re)starts the shell so that it locks before anything else.
func (d *Daemon) startLocked(ctx context.Context) error {
	if d.shell == nil {
		return axerr.New(axerr.Unavailable, "this daemon runs no shell")
	}
	return d.shell.Restart(ctx, map[string]string{"AXIOM_LOCK_ON_START": "1"})
}

// restartShell restarts the shell (axiom restart). Locked, the next one
// locks first: the compositor holds the session locked meanwhile, and
// nothing but PAM may end that.
func (d *Daemon) restartShell(ctx context.Context) error {
	if d.locker.State().Locked {
		return d.startLocked(ctx)
	}
	return d.shell.Restart(ctx, nil)
}

// lockSetting is a Lockscreen setting (mode, lockCommand).
func (d *Daemon) lockSetting(key string) string {
	cfg, _ := d.store.Config()
	v, _ := config.Lookup(cfg, config.Keys("Lockscreen", key))
	s, _ := v.(string)
	return s
}

// writeSnapshot writes the current config for the shell's first read.
func (d *Daemon) writeSnapshot() error {
	cfg, _ := d.store.Config()
	return fsx.WriteFile(d.runtime.File(SnapshotFile), jsonx.Marshal(cfg), 0o600)
}

// shellEnv is what the shell is started with every time.
func (d *Daemon) shellEnv() map[string]string {
	return map[string]string{
		"AXIOM_SOCKET":     d.runtime.Socket(),
		"AXIOM_SCHEMA":     d.runtime.File(SchemaFile),
		"AXIOM_CONFIG":     d.runtime.File(SnapshotFile),
		"AXIOM_DAEMON_PID": itoa(os.Getpid()),
		"AXIOM_TREE":       d.opts.Tree,
		// What binds and generated compositor configs call: the installed
		// binary, never a dev build that goes when dev mode does
		"AXIOM_BIN": d.installed,
	}
}

// shellEnvNow is what may change between starts: whether the config is
// writable (the shell reads the hello's answer too, which follows dev
// mode at runtime).
func (d *Daemon) shellEnvNow() map[string]string {
	if ok, reason := d.compatible(); !ok {
		return map[string]string{"AXIOM_INCOMPATIBLE": reason}
	}
	return nil
}

func itoa(n int) string { return strconv.Itoa(n) }

// currentSchema is the built schema and its hash.
func (d *Daemon) currentSchema() ([]byte, string) {
	d.schemaMu.Lock()
	defer d.schemaMu.Unlock()
	return d.schemaBytes, d.schemaHash
}

// setSchema records a built schema, and whether it is this binary's.
func (d *Daemon) setSchema(data []byte, hash string) {
	matches := embeddedMatches(buildinfo.Get().SchemaHash, hash)
	d.schemaMu.Lock()
	d.schemaBytes, d.schemaHash, d.treeMatches = data, hash, matches
	d.schemaMu.Unlock()
}

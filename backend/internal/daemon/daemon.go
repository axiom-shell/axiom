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
	"github.com/axiom-shell/axiom/backend/internal/compositor/ipc"
	"github.com/axiom-shell/axiom/backend/internal/compositor/manager"
	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/devconfig"
	"github.com/axiom-shell/axiom/backend/internal/files"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
	"github.com/axiom-shell/axiom/backend/internal/idle"
	"github.com/axiom-shell/axiom/backend/internal/inputmethod"
	"github.com/axiom-shell/axiom/backend/internal/ipcroute"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/lockscreen"
	"github.com/axiom-shell/axiom/backend/internal/nightlight"
	"github.com/axiom-shell/axiom/backend/internal/nmnet"
	"github.com/axiom-shell/axiom/backend/internal/nmvpn"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/saved"
	"github.com/axiom-shell/axiom/backend/internal/schema"
	"github.com/axiom-shell/axiom/backend/internal/store"
	"github.com/axiom-shell/axiom/backend/internal/supervise"
	"github.com/axiom-shell/axiom/backend/internal/sysmon"
	"github.com/axiom-shell/axiom/backend/internal/topics"
	"github.com/axiom-shell/axiom/backend/internal/tree"
	"github.com/axiom-shell/axiom/backend/internal/udisks"
	"github.com/axiom-shell/axiom/backend/internal/wayland/client"
	"github.com/axiom-shell/axiom/backend/internal/wayland/ctm"
	"github.com/axiom-shell/axiom/backend/internal/wayland/datacontrol"
	"github.com/axiom-shell/axiom/backend/internal/wayland/gamma"
	"github.com/axiom-shell/axiom/backend/internal/wayland/idlenotify"
	"github.com/axiom-shell/axiom/backend/internal/wayland/keyhold"
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
	Dev bool
	// TreeOverride: the tree was given (--tree, $AXIOM_TREE), and wins
	// over dev mode's at the session start
	TreeOverride bool
	NoShell      bool   // don't start quickshell (tests, headless use)
	QS           string // the quickshell binary (default "qs")
	Go           string // the go binary dev mode builds with (default "go")
	Getenv       func(string) string
	Log          *slog.Logger
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
	// releases replaces the official releases' download url (tests)
	releases string
	// exec replaces execve for the session start's exec and the dev
	// image's way back (tests)
	exec func(exe string, argv, env []string) error
	// reexec replaces the re-exec into another image (tests)
	reexec func(exe string, img image) error
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
	// installTree is the installed axiom tree (self-update's, the
	// greeter's), whatever tree the shell runs on (opts.Tree: a dev tree
	// while dev mode runs it); configDir the folder of the config the
	// store runs on: dirs.Config, or devConfigDir in the dev image
	installTree string
	configDir   string
	// upgradesTried: the binaries (path, inode, time) a newer client's
	// hello already re-exec'd into or found wanting, never tried again;
	// upgrading the one it is re-executing into
	upgradeMu     sync.Mutex
	upgradesTried map[string]bool
	upgrading     string
	instance      *fsx.Lock
	listener      net.Listener

	store  *store.Store
	saved  *saved.Service
	server *rpc.Server
	shell  *supervise.Supervisor
	// shellEntry is the QML dir the shell runs from (`qs -p`), which
	// names its quickshell instance (`axiom log` reads it)
	shellEntry string
	router     *ipcroute.Router
	locker     *lockscreen.Locker
	dev        *devMode
	savedKick  *kicker
	// compositor is the compositor's config layer (nil without the tree's
	// tables)
	compositor *manager.Manager
	// The clients on the daemon's Wayland connection: the outputs, the
	// seat, idle notifications, and the connection itself
	outputs      *outputs.Tracker
	seat         *seat.Tracker
	idleNotifier *idlenotify.Notifier
	keyboard     *vkbd.Keyboard
	// keyHolder holds the keyboard for the window switcher (switcher.go)
	keyHolder    *keyhold.Holder
	switcherHold switcherHold
	ctm          *ctm.Control
	gamma        *gamma.Control
	wayland      *waylandSession
	// nightLight warms the screens (on ctm or gamma)
	nightLight *nightlight.Service
	// clip is the clipboard's data control; clipboard its history
	clip      *datacontrol.Device
	clipboard *clipboard.History
	// vpn is NetworkManager's VPNs and the secret agent
	vpn *nmvpn.Service
	// drives are UDisks2's removable drives
	drives *udisks.Service
	// inputMethod is the input method framework (fcitx5 or ibus)
	inputMethod *inputmethod.Service
	// net is the rest the Wi-Fi menu asks NetworkManager
	net *nmnet.Service
	// idle is the Idle section's service
	idle *idle.Service
	// topics are the polled topics and their subscribers
	topics *topics.Hub
	// sysmon is the `system` topic and the graphs' history
	sysmon *sysmon.Monitor
	// The commands the shell watches (exec.watch)
	watches *command.Watches
	// The files the shell watches (file.watch)
	files *files.Files
	// niri's event stream for each connection watching it (niri.watch);
	// nil when not under niri
	niriStreams *ipc.NiriStreams
	// The commands running as its children (handed on by a re-exec)
	children command.Children
	tasks    *tasks
	stop     context.CancelFunc

	// isShell says whether a connection's peer pid is the shell's (a
	// hello as "shell" from anything else is refused)
	isShell func(pid int) bool
}

// Run runs the daemon until ctx ends or it is told to shut down.
func Run(ctx context.Context, opts Options) (err error) {
	if opts.Log == nil {
		opts.Log = slog.New(slog.DiscardHandler)
	}
	if opts.QS == "" {
		opts.QS = "qs"
	}
	if opts.Go == "" {
		opts.Go = "go"
	}
	// A compositor's variable left over from an earlier session reaches
	// nothing: not the daemon's parts, not the shell
	stale := ipc.StaleVars(opts.Getenv)
	opts.Getenv = ipc.LiveEnv(opts.Getenv)
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
	h, err := inherited(opts.Getenv, d.dirs)
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
	// A dev image the installed binary exec'd into (at session start or
	// a runtime switch) goes back to it if it fails before it serves
	// (devstart.go)
	if d.fallsBack(h) {
		defer func() {
			if err != nil && ctx.Err() == nil {
				d.fallBackLive(h, listener, err)
			}
		}()
	}

	// The session start: dev mode's fresh build is exec'd into now (or its
	// stale one built once running); then the image, as the image before a
	// re-exec named it, else (dev mode as --dev or the saved choice) the
	// tree run found on the live config
	choice := loadDevChoice(d.dirs)
	plan := d.sessionStart(h, choice)
	img, installTree := startImage(h, choice, opts, d.dirs)
	if h != nil && h.Fresh && img.ConfigDir != devConfigDir(d.dirs) {
		opts.Log.Warn("started for dev mode, but dev.json names no dev tree now: running the install tree")
	}
	opts.Tree, d.opts.Tree = img.Tree, img.Tree
	d.installTree, d.configDir = installTree, img.ConfigDir
	if opts.Tree == "" {
		// `axiom run` found none, and no handoff named one
		closeConfigLock(h)
		return axerr.New(axerr.NotFound, "no axiom tree to run (pass --tree)")
	}
	d.dev = newDevMode(d, img.Dev)
	d.dev.begin(ctx, choice, plan)

	if err := d.loadSchema(); err != nil {
		closeConfigLock(h)
		return err
	}
	built, _ := d.currentSchema()
	parsed, err := jsonx.Unmarshal(built)
	if err != nil {
		closeConfigLock(h)
		return axerr.Wrap(axerr.Internal, err, "the built schema")
	}
	pipeline := config.Pipeline{S: schema.New(parsed)}
	storeOpts := store.Options{
		Dir:      d.configDir,
		Pipeline: pipeline,
		Log:      opts.Log.With("part", "config"),
		// The takeover settings in effect, read when config.json isn't
		// JSON: one per machine, so the dev config's too
		TakeoversFile: filepath.Join(d.dirs.State, store.TakeoversFile),
	}
	// The writer lock goes on only with the config it locks: a re-exec
	// onto the other config (into or out of the dev image) drops it
	adopting := h.carried() && h.ConfigLockDir == d.configDir
	if adopting {
		d.store, err = store.OpenAdopting(storeOpts, os.NewFile(uintptr(h.ConfigLock), store.FileName+".lock"))
	} else {
		closeConfigLock(h)
		d.store, err = d.openStore(storeOpts)
	}
	if err != nil {
		return err
	}
	defer d.store.Close()
	// A re-exec that comes up on the defaults (an older dev build refusing
	// a newer file) leaves the snapshot of before: a QML reload keeps the
	// config the shell had running, as ConfigManager does on the hello.
	// Another config's snapshot is never kept
	if _, st := d.store.Config(); !adopting || !st.Defaults {
		if err := d.writeSnapshot(); err != nil {
			return err
		}
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

	d.router = ipcroute.New()
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
	if h.carried() && h.Locked {
		// The adopted shell held the lock: until it reports again, it dies
		// (or restarts for a new schema) locked
		d.locker.Report(lockscreen.State{Holding: true})
	}
	d.saved = saved.New(saved.Options{
		Dir:      d.dirs.Config,
		Examples: filepath.Join(opts.Tree, "data", "examples"),
		Home:     opts.Getenv("HOME"),
		// The active snapshot is the config's own: dev's apart
		UIState:  d.uiStateFile(),
		Store:    d.store,
		Pipeline: d.store.Pipeline,
		// saved/ is shared: dev never writes over a snapshot live restores
		LiveRestores: d.dev.liveRestores,
		Log:          opts.Log.With("part", "saved"),
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
	if d.compositor != nil {
		// The saved monitor profile follows hotplugs
		d.outputs.OnChange(d.compositor.OutputsChanged)
	}
	d.seat = seat.New()
	d.wayland = &waylandSession{onChange: d.pushWayland}
	d.idleNotifier = idlenotify.New(idlenotify.Options{
		Seat:     d.seat,
		Log:      opts.Log.With("part", "wayland"),
		OnChange: func() { d.idle.NotifierChanged() },
	})
	d.keyboard = vkbd.New(vkbd.Options{Seat: d.seat, OnChange: d.pushWayland, Gap: 2 * time.Millisecond})
	d.keyHolder = keyhold.New(keyhold.Options{Seat: d.seat, Log: opts.Log.With("part", "wayland")})
	d.newNightLight()
	d.newClipboard()
	d.newVPN()
	d.newDrives()
	d.newInputMethod()
	d.idle = d.newIdle()
	d.topics = topics.New(topics.Options{Log: opts.Log.With("part", "topics"), Context: ctx, Go: d.tasks.Go})
	d.sysmon = d.newSysmon()
	d.watches = command.NewWatches(command.WatchOptions{Method: pushExecOutputs.Method, Options: d.commandOptions, Log: opts.Log.With("part", "exec"), Context: ctx, Go: d.tasks.Go})
	d.files = files.New(files.Options{Method: pushFileChanged.Method, Log: opts.Log.With("part", "files"), Context: ctx, Go: d.tasks.Go})
	d.niriStreams = niriStreams(opts.Getenv, opts.Log, ctx, d.tasks.Go)
	parts := []part{d.corePart(), d.configPart(), d.ipcPart(), d.sharingPart(), d.compositorPart(), d.compositorSocketPart(), d.topicsPart(), d.toolsPart(), d.execPart(), d.filesPart(), d.calendarPart(), d.chatPart(), d.secretsPart(), d.themePart(), d.hookupPart(), d.selfUpdatePart(), d.greeterInstallPart(), d.cursorPart(), d.inputPart(), d.brightnessPart(), d.idlePart(), d.waylandPart(), d.switcherPart(), d.clipboardPart(), d.vpnPart(), d.drivesPart(), d.inputMethodPart(), d.netPart(), d.dev.part()}
	parts = append(parts, d.machineParts()...)
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
			d.sysmon.Forget(c)
			d.watches.Forget(c)
			d.files.Forget(c)
			d.releaseSwitcher(c)
			if d.niriStreams != nil {
				d.niriStreams.Forget(c)
			}
		},
	}
	d.store.Subscribe(func(ev store.Event) {
		for _, p := range parts {
			if p.onConfig != nil {
				p.onConfig(ev)
			}
		}
	})

	// The shell's supervisor before the socket serves: an adopted shell
	// reconnects the moment the re-exec'd image listens, and its hello
	// is checked against the pid this knows
	if !opts.NoShell {
		adopt := 0
		if h.carried() {
			adopt = h.Shell
		}
		d.shellEntry = tree.QMLDir(opts.Tree)
		d.shell = supervise.New(supervise.Options{
			Command:  ShellCommand(opts.QS, d.shellEntry),
			NoTHP:    true,
			Env:      d.shellEnv(),
			EnvFunc:  d.shellEnvNow,
			Environ:  ipc.WithoutVars(os.Environ(), stale),
			PIDFile:  runtime.File(ShellPIDFile),
			Output:   opts.ShellOutput,
			Log:      opts.Log.With("part", "shell"),
			AdoptPID: adopt,
			OnExit:   func(int, bool) { d.locker.ShellExited() },
			OnStop:   func(int) { d.locker.ShellStopped() },
		})
	}
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
	if d.shell != nil {
		serve("the shell", d.shell.Run)
		_, hash := d.currentSchema()
		if why := needsShellRestart(h, d.shellEntry, d.configDir, hash); why != "" {
			d.tasks.Go(func(ctx context.Context) {
				opts.Log.Info(why + " across the re-exec: restarting the shell")
				if err := d.restartShell(ctx); err != nil && ctx.Err() == nil {
					opts.Log.Error("restarting the shell after the re-exec", "err", err)
				}
			})
		}
	}
	opts.Log.Info("axiom is running", "display", runtime.Display, "tree", opts.Tree, "socket", runtime.Socket(), "version", buildinfo.Get().Version, "config", d.store.Path(), "reexec", h != nil, "dev", d.dev.Enabled(), "devActive", d.dev.active())
	<-ctx.Done()
	d.tasks.Wait()
	opts.Log.Info("axiom stopped")
	return nil
}

// needsShellRestart is why the shell an image adopts across a re-exec (h)
// must restart ("": it needn't): it runs from another QML dir than entry
// (another tree; an image of before the handoff said ran the old layout),
// reads another config than configDir's (into or out of the dev image), or
// read another schema (an update re-exec'd into the new binary), whose
// hello would be refused.
func needsShellRestart(h *handoff, entry, configDir, schemaHash string) string {
	switch {
	case !h.carried():
		return ""
	case h.ShellEntry != entry:
		return "the shell's tree changed"
	case h.ConfigLockDir != configDir:
		return "the config changed"
	case h.Schema != "" && h.Schema != schemaHash:
		return "the schema changed"
	}
	return ""
}

// closeConfigLock closes a re-exec's config writer lock, not taken over
// (the next image runs on the other config, or doesn't start).
func closeConfigLock(h *handoff) {
	if h.carried() {
		os.NewFile(uintptr(h.ConfigLock), store.FileName+".lock").Close()
	}
}

// openStore opens the config afresh. The dev image's is readied first:
// seeded from live the first time, its takeover settings live's.
func (d *Daemon) openStore(opts store.Options) (*store.Store, error) {
	if d.configDir == devConfigDir(d.dirs) {
		p, err := devconfig.Prepare(d.devConfigFiles(), opts.Pipeline)
		if err != nil {
			return nil, err
		}
		d.dev.prepared = p // before anything reads it
		d.opts.Log.Info("the dev config", "path", filepath.Join(d.configDir, store.FileName), "seeded", p.Seeded, "liveChanged", p.LiveChanged, "patched", p.Patched, "note", p.Note)
	}
	return store.Open(opts)
}

// devConfigFiles are the files the dev config is kept with.
func (d *Daemon) devConfigFiles() devconfig.Files {
	return devconfig.Files{
		Live: filepath.Join(d.dirs.Config, store.FileName),
		Dev:  filepath.Join(devConfigDir(d.dirs), store.FileName),
		Base: d.dirs.State + "dev/base.json",
	}
}

// uiStateFile remembers the config's active snapshot (saved/ is shared,
// the pointer is each config's).
func (d *Daemon) uiStateFile() string {
	if d.configDir == devConfigDir(d.dirs) {
		return filepath.Join(d.dirs.UI, "dev", "savedconfigs.json")
	}
	return filepath.Join(d.dirs.UI, "savedconfigs.json")
}

// followCompositor runs the Wayland connection until ctx ends, and stops
// the daemon when the compositor is gone. If the connection fails
// otherwise (a protocol error), an idle one (wire.Watch) still watches
// for that.
func (d *Daemon) followCompositor(ctx context.Context, socket string) {
	log := d.opts.Log
	err := client.Run(ctx, socket, d.outputs, d.seat, d.idleNotifier, d.keyboard, d.keyHolder, d.ctm, d.gamma, d.clip, d.wayland)
	// Unavailable: no compositor to connect to, nor to watch
	if err != nil && !errors.Is(err, wire.ErrGone) && axerr.KindOf(err) != axerr.Unavailable {
		log.Warn("the Wayland connection failed: monitors aren't known", "err", err)
		// Nothing on it works any more: what it offered reads off, so
		// the shell falls back and Idle sees no notifier
		d.idleNotifier.Stop()
		d.wayland.Failed()
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
	if d.locker.Held() {
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

// ShellCommand runs qs on entry (the tree's QML dir, or its greeter.qml). Its log
// rule drops Qt's text-input-v3 warnings ("Trying to enable/disable …"),
// which are Qt's own bookkeeping, not a fault: a surface whose wl_surface
// goes before Qt moves the focus off its text field (a layer window hiding:
// the launcher closing) is never disabled client side, so every later
// enable or disable compares against that gone surface and warns. The
// compositor's text-input leave has disabled it already: typing works.
// Quickshell's rule reaches Qt's categories (a QT_LOGGING_RULES pragma
// comes too late to). It applies after the user's QT_LOGGING_RULES, so it
// overrides only that one category's warnings; their other rules stand.
func ShellCommand(qs, entry string) []string {
	return []string{qs, "-p", entry, "--log-rules", "qt.qpa.wayland.textinput.warning=false"}
}

// shellEnv is what the shell is started with every time.
func (d *Daemon) shellEnv() map[string]string {
	return map[string]string{
		"AXIOM_SOCKET":     d.runtime.Socket(),
		"AXIOM_SCHEMA":     d.runtime.File(SchemaFile),
		"AXIOM_CONFIG":     d.runtime.File(SnapshotFile),
		"AXIOM_DAEMON_PID": itoa(os.Getpid()),
		// The tree the shell runs on, and the installed one (whose
		// packaging marker says how axiom was installed)
		"AXIOM_TREE":         d.opts.Tree,
		"AXIOM_INSTALL_TREE": d.installTree,
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

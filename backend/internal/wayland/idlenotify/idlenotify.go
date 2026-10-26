// Package idlenotify tells when the user has been idle for a while, over
// ext_idle_notifier_v1 (v2 for notifications that ignore inhibitors):
// one notification per timeout, on the seat, kept armed through the
// notifier or the seat going away and coming back. The idle service
// (internal/idle) decides what each timeout does.
package idlenotify

import (
	"log/slog"
	"sync"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/wayland/client"
	"github.com/axiom-shell/axiom/backend/internal/wayland/seat"
	"github.com/axiom-shell/axiom/backend/internal/wayland/wire"
)

// The interface and its opcodes (ext-idle-notify-v1.xml)
const (
	ifaceNotifier = "ext_idle_notifier_v1"
	maxVersion    = 2 // get_input_idle_notification

	opNotifierDestroy          = 0
	opGetIdleNotification      = 1 // (id, timeout ms, seat): respects inhibitors
	opGetInputIdleNotification = 2 // (id, timeout ms, seat): input only (v2)
	opNotificationDestroy      = 0
	evIdled                    = 0
	evResumed                  = 1
)

// Options configure the notifier.
type Options struct {
	Seat *seat.Tracker
	Log  *slog.Logger
	// OnChange is told when the notifier comes or goes (Available), on
	// the connection's goroutine
	OnChange func()
}

// Notifier arms idle notifications; it is a client.Client.
type Notifier struct {
	opts Options

	mu      sync.Mutex
	s       *client.Session
	manager uint32
	version uint32
	global  uint32
	seat    uint32
	watches map[*watch]struct{}
	warned  bool
}

type watch struct {
	timeout          time.Duration
	respect          bool
	onIdle, onResume func()
	obj              uint32 // its notification, 0 while it can't be armed
}

// New returns a notifier; watches arm once the compositor's notifier and
// a seat are bound.
func New(opts Options) *Notifier {
	if opts.Log == nil {
		opts.Log = slog.New(slog.DiscardHandler)
	}
	n := &Notifier{opts: opts, watches: map[*watch]struct{}{}}
	opts.Seat.OnChange(func(id uint32) {
		n.mu.Lock()
		n.seat = id
		n.rearm()
		n.mu.Unlock()
	})
	return n
}

// Available reports whether the compositor offers idle notifications.
func (n *Notifier) Available() bool {
	n.mu.Lock()
	defer n.mu.Unlock()
	return n.manager != 0
}

// Watch calls onIdle once the user has been idle for timeout, and
// onResume when they come back after that. respectInhibitors false asks
// for a notification apps' inhibitors can't hold off (falling back to
// one they can before notifier v2). The callbacks run on the
// connection's goroutine and must not block. cancel disarms it.
func (n *Notifier) Watch(timeout time.Duration, respectInhibitors bool, onIdle, onResume func()) (cancel func()) {
	w := &watch{timeout: timeout, respect: respectInhibitors, onIdle: onIdle, onResume: onResume}
	n.mu.Lock()
	n.watches[w] = struct{}{}
	n.arm(w)
	n.mu.Unlock()
	return func() {
		n.mu.Lock()
		defer n.mu.Unlock()
		if _, ok := n.watches[w]; ok {
			delete(n.watches, w)
			n.disarm(w)
		}
	}
}

// arm makes w's notification, when it can be; n.mu is held.
func (n *Notifier) arm(w *watch) {
	if n.manager == 0 || n.seat == 0 || w.obj != 0 {
		return
	}
	op := uint16(opGetIdleNotification)
	if !w.respect {
		if n.version >= 2 {
			op = opGetInputIdleNotification
		} else if !n.warned {
			n.warned = true
			n.opts.Log.Warn("the compositor's idle notifier is v1: inhibitors can't be ignored")
		}
	}
	c := n.s.Conn
	w.obj = c.NewObject(func(op uint16, _ *wire.Args) {
		switch op {
		case evIdled:
			w.onIdle()
		case evResumed:
			w.onResume()
		}
	})
	ms := w.timeout.Milliseconds()
	if ms < 1 {
		ms = 1
	}
	c.Send(n.manager, op, wire.Uint(w.obj), wire.Uint(uint32(min(ms, 1<<32-1))), wire.Uint(n.seat))
}

// disarm destroys w's notification; n.mu is held.
func (n *Notifier) disarm(w *watch) {
	if w.obj == 0 {
		return
	}
	if n.manager != 0 {
		n.s.Conn.Send(w.obj, opNotificationDestroy)
	}
	n.s.Conn.Forget(w.obj)
	w.obj = 0
}

// rearm makes every notification again (a new seat, a new notifier);
// n.mu is held.
func (n *Notifier) rearm() {
	for w := range n.watches {
		n.disarm(w)
		n.arm(w)
	}
}

// Interfaces (client.Client)
func (n *Notifier) Interfaces() []string { return []string{ifaceNotifier} }

// Start forgets an earlier connection's objects (client.Client).
func (n *Notifier) Start(s *client.Session) {
	n.mu.Lock()
	defer n.mu.Unlock()
	n.s, n.manager, n.version, n.global = s, 0, 0, 0
	for w := range n.watches {
		w.obj = 0
	}
}

// Global binds the notifier and arms every watch (client.Client).
func (n *Notifier) Global(g client.Global) {
	n.mu.Lock()
	if n.manager != 0 {
		n.mu.Unlock()
		return
	}
	n.manager, n.version, _ = n.s.Bind(g, maxVersion, nil)
	n.global = g.Name
	n.rearm()
	n.mu.Unlock()
	n.changed()
}

// Removed drops the notifier (client.Client): watches wait for another.
func (n *Notifier) Removed(name uint32) {
	n.mu.Lock()
	if name != n.global {
		n.mu.Unlock()
		return
	}
	for w := range n.watches {
		n.disarm(w)
	}
	n.s.Conn.Send(n.manager, opNotifierDestroy)
	n.s.Conn.Forget(n.manager)
	n.manager, n.global = 0, 0
	n.mu.Unlock()
	n.changed()
}

// Ready (client.Client)
func (n *Notifier) Ready() { n.changed() }

func (n *Notifier) changed() {
	if n.opts.OnChange != nil {
		n.opts.OnChange()
	}
}

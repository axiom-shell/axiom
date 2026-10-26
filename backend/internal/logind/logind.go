// Package logind is what axiom asks of systemd-logind over the system
// bus: the session's lock requests (`loginctl lock-session`), the
// announcement of sleep, with a delay inhibitor that holds it until the
// screen is locked, the apps keeping the system awake (idle inhibitors),
// and suspending.
package logind

import (
	"context"
	"errors"
	"os"
	"strings"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
)

// logind's names
const (
	busName      = "org.freedesktop.login1"
	managerPath  = dbus.ObjectPath("/org/freedesktop/login1")
	ifaceManager = "org.freedesktop.login1.Manager"
	ifaceSession = "org.freedesktop.login1.Session"
	ifaceUser    = "org.freedesktop.login1.User"
)

// Logind is logind on one bus connection, for one session.
type Logind struct {
	conn    *dbus.Conn
	session dbus.ObjectPath
}

// Open finds this session: $XDG_SESSION_ID, else the session of this
// process, else the user's display session (a daemon started outside
// the session's scope, by a systemd user unit, has no session of its
// own).
func Open(ctx context.Context, conn *dbus.Conn, getenv func(string) string) (*Logind, error) {
	l := &Logind{conn: conn}
	ways := []func() error{
		func() error { return l.find(ctx, "GetSessionByPID", "u", uint32(os.Getpid())) },
		func() error { return l.display(ctx) },
	}
	if id := getenv("XDG_SESSION_ID"); id != "" {
		ways = append([]func() error{func() error { return l.find(ctx, "GetSession", "s", id) }}, ways...)
	}
	var errs []error
	for _, way := range ways {
		err := way()
		if err == nil {
			return l, nil
		}
		errs = append(errs, err)
	}
	return nil, axerr.Wrap(axerr.Unavailable, errors.Join(errs...), "finding the logind session")
}

func (l *Logind) find(ctx context.Context, method, sig string, arg any) error {
	m, err := l.conn.Call(ctx, busName, managerPath, ifaceManager, method, sig, arg)
	if err != nil {
		return err
	}
	return m.Store(&l.session)
}

// display reads the user's Display property: (session id, path).
func (l *Logind) display(ctx context.Context) error {
	m, err := l.conn.Call(ctx, busName, managerPath, ifaceManager, "GetUser", "u", uint32(os.Getuid()))
	if err != nil {
		return err
	}
	var user dbus.ObjectPath
	if err := m.Store(&user); err != nil {
		return err
	}
	v, err := l.conn.GetProperty(ctx, busName, user, ifaceUser, "Display")
	if err != nil {
		return err
	}
	pair, ok := v.Value.([]any)
	if !ok || len(pair) != 2 {
		return errors.New("logind: a Display property of the wrong shape")
	}
	path, _ := pair[1].(dbus.ObjectPath)
	if path == "" || path == "/" {
		return errors.New("logind: the user has no display session")
	}
	l.session = path
	return nil
}

// Session is the session's object path.
func (l *Logind) Session() dbus.ObjectPath { return l.session }

// Suspend suspends the system, as `systemctl suspend` would.
func (l *Logind) Suspend(ctx context.Context) error {
	_, err := l.conn.Call(ctx, busName, managerPath, ifaceManager, "Suspend", "b", false)
	return err
}

// InhibitSleep takes a delay inhibitor on sleep: logind waits (up to
// InhibitDelayMax) for it to be closed after announcing sleep. The
// caller closes the file to let sleep go on.
func (l *Logind) InhibitSleep(ctx context.Context, who, why string) (*os.File, error) {
	m, err := l.conn.Call(ctx, busName, managerPath, ifaceManager, "Inhibit", "ssss", "sleep", who, why, "delay")
	if err != nil {
		return nil, err
	}
	defer m.Close()
	var fd dbus.UnixFD
	if err := m.Store(&fd); err != nil {
		return nil, err
	}
	return m.File(fd)
}

// InhibitDelayMax is how long logind waits on a delay inhibitor.
func (l *Logind) InhibitDelayMax(ctx context.Context) (time.Duration, error) {
	v, err := l.conn.GetProperty(ctx, busName, managerPath, ifaceManager, "InhibitDelayMaxUSec")
	if err != nil {
		return 0, err
	}
	us, ok := v.Value.(uint64)
	if !ok {
		return 0, errors.New("logind: InhibitDelayMaxUSec isn't a uint64")
	}
	return time.Duration(us) * time.Microsecond, nil
}

// Inhibitor is one app holding something off.
type Inhibitor struct {
	What string `json:"what"`
	Who  string `json:"who"`
	Why  string `json:"why"`
	Mode string `json:"mode"`
	PID  uint32 `json:"pid"`
}

// IdleInhibitors are the inhibitors blocking idle (systemd-inhibit
// --what=idle, and the apps asking logind for it).
func (l *Logind) IdleInhibitors(ctx context.Context) ([]Inhibitor, error) {
	m, err := l.conn.Call(ctx, busName, managerPath, ifaceManager, "ListInhibitors", "")
	if err != nil {
		return nil, err
	}
	var rows []any
	if err := m.Store(&rows); err != nil {
		return nil, err
	}
	var out []Inhibitor
	for _, r := range rows {
		f, ok := r.([]any)
		if !ok || len(f) != 6 {
			continue
		}
		var in Inhibitor
		var uid uint32
		if dbus.Store(f, &in.What, &in.Who, &in.Why, &in.Mode, &uid, &in.PID) != nil {
			continue
		}
		if in.Mode == "block" && hasWhat(in.What, "idle") {
			out = append(out, in)
		}
	}
	return out, nil
}

// hasWhat reports whether a colon-separated "what" list holds what.
func hasWhat(list, what string) bool {
	for _, w := range strings.Split(list, ":") {
		if w == what {
			return true
		}
	}
	return false
}

// Event is one thing logind announced.
type Event struct {
	// Lock: the session was asked to lock (loginctl lock-session)
	Lock bool
	// Sleep: the system is about to sleep (true) or woke (false); set
	// with SleepChanged
	SleepChanged, Sleep bool
	// IdleBlocked: an idle inhibitor came or went; set with
	// IdleChanged
	IdleChanged, IdleBlocked bool
}

// Watch calls fn with every event until ctx ends (nil) or the bus
// connection does (an error). The current idle block comes first.
func (l *Logind) Watch(ctx context.Context, fn func(Event)) error {
	subs := []dbus.Match{
		{Sender: busName, Path: l.session, Interface: ifaceSession, Member: "Lock"},
		{Sender: busName, Path: managerPath, Interface: ifaceManager, Member: "PrepareForSleep"},
		dbus.PropertiesChangedMatch(busName, managerPath, ifaceManager),
	}
	merged := make(chan *dbus.Message, 16)
	stop := make(chan struct{})
	defer close(stop)
	for _, m := range subs {
		sub, err := l.conn.Subscribe(ctx, m)
		if err != nil {
			return err
		}
		defer sub.Close()
		go func() {
			for msg := range sub.C {
				select {
				case merged <- msg:
				case <-stop:
					return
				}
			}
		}()
	}
	blocked, err := l.idleBlocked(ctx)
	if err != nil {
		return err
	}
	fn(Event{IdleChanged: true, IdleBlocked: blocked})
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-l.conn.Done():
			return axerr.Wrap(axerr.Unavailable, l.conn.Err(), "the system bus connection ended")
		case msg := <-merged:
			switch {
			case msg.Member == "Lock":
				fn(Event{Lock: true})
			case msg.Member == "PrepareForSleep":
				var start bool
				if msg.Store(&start) == nil {
					fn(Event{SleepChanged: true, Sleep: start})
				}
			default:
				_, changed, invalidated, err := dbus.PropertiesChanged(msg)
				if err != nil {
					continue
				}
				if v, ok := changed["BlockInhibited"]; ok {
					s, _ := v.Value.(string)
					fn(Event{IdleChanged: true, IdleBlocked: hasWhat(s, "idle")})
				} else if contains(invalidated, "BlockInhibited") {
					if b, err := l.idleBlocked(ctx); err == nil {
						fn(Event{IdleChanged: true, IdleBlocked: b})
					}
				}
			}
		}
	}
}

func (l *Logind) idleBlocked(ctx context.Context) (bool, error) {
	v, err := l.conn.GetProperty(ctx, busName, managerPath, ifaceManager, "BlockInhibited")
	if err != nil {
		return false, err
	}
	s, _ := v.Value.(string)
	return hasWhat(s, "idle"), nil
}

func contains(list []string, s string) bool {
	for _, x := range list {
		if x == s {
			return true
		}
	}
	return false
}

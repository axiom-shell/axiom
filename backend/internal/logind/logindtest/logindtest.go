// Package logindtest is a fake systemd-logind on a dbustest bus: one
// session, Suspend counted and SetBrightness recorded, delay inhibitors
// as pipes the test can watch, idle inhibitors listed (the test's, and
// those taken with Inhibit until their client closes them, which block
// idle as logind's do), BlockInhibited changed and signals sent by the
// test.
package logindtest

import (
	"context"
	"fmt"
	"io"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/dbus/dbustest"
)

// logind's names, as the fake answers them
const (
	BusName      = "org.freedesktop.login1"
	ManagerPath  = dbus.ObjectPath("/org/freedesktop/login1")
	SessionPath  = dbus.ObjectPath("/org/freedesktop/login1/session/_37")
	SessionID    = "7"
	ifaceManager = "org.freedesktop.login1.Manager"
	ifaceSession = "org.freedesktop.login1.Session"
)

// Fake is the fake logind.
type Fake struct {
	Conn *dbus.Conn
	// Inhibited gets the read end of each delay inhibitor's pipe: it
	// reads EOF once the client closed the inhibitor
	Inhibited chan *os.File

	mu         sync.Mutex
	blocked    string
	suspended  int
	inhibitors []any
	taken      map[int][]any // idle inhibitors taken with Inhibit, by id
	nextTaken  int
	brightness []string
}

// New exports the fake on bus, owning logind's name.
func New(t *testing.T, bus *dbustest.Bus) *Fake {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	conn, err := dbus.Dial(ctx, bus.Address, dbus.Options{})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { conn.Close() })
	f := &Fake{Conn: conn, blocked: "handle-power-key", Inhibited: make(chan *os.File, 8), taken: map[int][]any{}}
	_, err = conn.Export(ManagerPath, dbus.Interface{Name: ifaceManager, Methods: map[string]dbus.Method{
		"GetSession": {In: "s", Out: "o", Fn: func(_ context.Context, m *dbus.Message) ([]any, error) {
			if m.Body[0] != SessionID {
				return nil, dbus.NewError("org.freedesktop.login1.NoSuchSession", "no session")
			}
			return []any{SessionPath}, nil
		}},
		"GetSessionByPID": {In: "u", Out: "o", Fn: func(context.Context, *dbus.Message) ([]any, error) {
			return nil, dbus.NewError("org.freedesktop.login1.NoSessionForPID", "no session for the pid")
		}},
		"GetUser": {In: "u", Out: "o", Fn: func(context.Context, *dbus.Message) ([]any, error) {
			return []any{dbus.ObjectPath("/org/freedesktop/login1/user/_1000")}, nil
		}},
		"Suspend": {In: "b", Fn: func(context.Context, *dbus.Message) ([]any, error) {
			f.mu.Lock()
			f.suspended++
			f.mu.Unlock()
			return nil, nil
		}},
		"Inhibit": {In: "ssss", Out: "h", Fn: func(_ context.Context, m *dbus.Message) ([]any, error) {
			idle := m.Body[0] == "idle" && m.Body[3] == "block"
			if !idle && (m.Body[0] != "sleep" || m.Body[3] != "delay") {
				return nil, dbus.NewError(dbus.ErrInvalidArgs, "unexpected inhibitor")
			}
			r, w, err := os.Pipe()
			if err != nil {
				return nil, err
			}
			if idle {
				f.takeIdle(r, m.Body[1].(string), m.Body[2].(string))
			} else {
				f.Inhibited <- r
			}
			fd := dbus.UnixFD(w.Fd())
			// The reply is sent once this returns: logind's own copy
			// goes after it, as the real one closes it
			time.AfterFunc(300*time.Millisecond, func() { w.Close() })
			return []any{fd}, nil
		}},
		"ListInhibitors": {Out: "a(ssssuu)", Fn: func(context.Context, *dbus.Message) ([]any, error) {
			f.mu.Lock()
			defer f.mu.Unlock()
			rows := append([]any{}, f.inhibitors...)
			for i := 1; i <= f.nextTaken; i++ {
				if row, ok := f.taken[i]; ok {
					rows = append(rows, row)
				}
			}
			return []any{rows}, nil
		}},
	}})
	if err != nil {
		t.Fatal(err)
	}
	_, err = conn.Export(SessionPath, dbus.Interface{Name: ifaceSession, Methods: map[string]dbus.Method{
		"SetBrightness": {In: "ssu", Fn: func(_ context.Context, m *dbus.Message) ([]any, error) {
			f.mu.Lock()
			defer f.mu.Unlock()
			f.brightness = append(f.brightness, fmt.Sprintf("%v %v %v", m.Body...))
			return nil, nil
		}},
	}})
	if err != nil {
		t.Fatal(err)
	}
	_, err = conn.Export(ManagerPath, dbus.Interface{Name: "org.freedesktop.DBus.Properties", Methods: map[string]dbus.Method{
		"Get": {In: "ss", Out: "v", Fn: func(_ context.Context, m *dbus.Message) ([]any, error) {
			f.mu.Lock()
			defer f.mu.Unlock()
			switch m.Body[1] {
			case "BlockInhibited":
				return []any{dbus.MakeVariant(f.blockedLocked())}, nil
			case "InhibitDelayMaxUSec":
				return []any{dbus.MakeVariant(uint64(5000000))}, nil
			}
			return nil, dbus.NewError(dbus.ErrInvalidArgs, "no such property")
		}},
	}})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := conn.RequestName(ctx, BusName, dbus.NameDoNotQueue); err != nil {
		t.Fatal(err)
	}
	return f
}

// Getenv is the environment that finds the fake's session.
func Getenv(k string) string {
	if k == "XDG_SESSION_ID" {
		return SessionID
	}
	return ""
}

// Suspended is how many times Suspend was called.
func (f *Fake) Suspended() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.suspended
}

// Brightness lists the session's SetBrightness calls, as "subsystem name
// value".
func (f *Fake) Brightness() []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]string{}, f.brightness...)
}

// SetInhibitors sets what ListInhibitors lists: rows of (what, who, why,
// mode, uid, pid).
func (f *Fake) SetInhibitors(rows ...[]any) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.inhibitors = nil
	for _, r := range rows {
		f.inhibitors = append(f.inhibitors, r)
	}
}

// SetBlocked changes BlockInhibited (with "idle" added while an idle
// inhibitor taken with Inhibit is held) and announces it, as logind
// does, only when that changes it.
func (f *Fake) SetBlocked(t *testing.T, what string) {
	t.Helper()
	f.mu.Lock()
	was := f.blockedLocked()
	f.blocked = what
	changed := f.blockedLocked() != was
	f.mu.Unlock()
	if !changed {
		return
	}
	if err := f.announce(); err != nil {
		t.Fatal(err)
	}
}

func (f *Fake) announce() error {
	f.mu.Lock()
	what := f.blockedLocked()
	f.mu.Unlock()
	return f.Conn.Emit(ManagerPath, "org.freedesktop.DBus.Properties", "PropertiesChanged", "sa{sv}as",
		ifaceManager, map[string]dbus.Variant{"BlockInhibited": dbus.MakeVariant(what)}, []string{})
}

func (f *Fake) blockedLocked() string {
	if len(f.taken) == 0 || hasIdle(f.blocked) {
		return f.blocked
	}
	if f.blocked == "" {
		return "idle"
	}
	return f.blocked + ":idle"
}

func hasIdle(list string) bool {
	for _, w := range strings.Split(list, ":") {
		if w == "idle" {
			return true
		}
	}
	return false
}

// takeIdle lists an idle inhibitor (this process's pid: the fake runs in
// the test's) until every copy of its write end is closed.
func (f *Fake) takeIdle(r *os.File, who, why string) {
	f.mu.Lock()
	f.nextTaken++
	id := f.nextTaken
	was := f.blockedLocked()
	f.taken[id] = []any{"idle", who, why, "block", uint32(os.Getuid()), uint32(os.Getpid())}
	changed := f.blockedLocked() != was
	f.mu.Unlock()
	if changed {
		f.announce()
	}
	go func() {
		io.Copy(io.Discard, r)
		r.Close()
		f.mu.Lock()
		was := f.blockedLocked()
		delete(f.taken, id)
		changed := f.blockedLocked() != was
		f.mu.Unlock()
		if changed {
			f.announce()
		}
	}()
}

// IdleHeld is how many idle inhibitors taken with Inhibit are held.
func (f *Fake) IdleHeld() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return len(f.taken)
}

// Lock sends the session's Lock signal (loginctl lock-session).
func (f *Fake) Lock() error { return f.Conn.Emit(SessionPath, ifaceSession, "Lock", "") }

// LockSession sends Lock for another session.
func (f *Fake) LockSession(path dbus.ObjectPath) error {
	return f.Conn.Emit(path, ifaceSession, "Lock", "")
}

// PrepareForSleep announces sleep (true) or waking (false).
func (f *Fake) PrepareForSleep(start bool) error {
	return f.Conn.Emit(ManagerPath, ifaceManager, "PrepareForSleep", "b", start)
}

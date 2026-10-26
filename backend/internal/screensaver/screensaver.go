// Package screensaver answers org.freedesktop.ScreenSaver on the session
// bus, the interface browsers, video players and games ask to keep the
// screen on through (Inhibit, UnInhibit), as hypridle did. An inhibitor
// lasts until it is released or its app leaves the bus. When another
// program holds the name (the compositor: niri answers it itself), the
// server reports who and waits for the name to come free.
package screensaver

import (
	"context"
	"log/slog"
	"os"
	"slices"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/dbus"
)

const (
	busName = "org.freedesktop.ScreenSaver"
	iface   = "org.freedesktop.ScreenSaver"
	// Inhibitors at most, all apps together: past that, Inhibit fails
	maxInhibitors = 512
)

// The paths apps call it at: freedesktop's, and the one KDE's apps use
var paths = []dbus.ObjectPath{"/org/freedesktop/ScreenSaver", "/ScreenSaver"}

// Inhibitor is one app keeping the screen on.
type Inhibitor struct {
	App    string `json:"app"`
	Reason string `json:"reason"`
	sender string
}

// Owner is who holds the name when the server doesn't.
type Owner struct {
	PID  uint32 `json:"pid"`
	Name string `json:"name"` // its process name (/proc/<pid>/comm)
}

// Options configure the server.
type Options struct {
	Log *slog.Logger
	// OnChange is told when the inhibitors or the name's owner change
	OnChange func()
	// OnActivity is told of SimulateUserActivity
	OnActivity func()
}

// Server is the ScreenSaver service.
type Server struct {
	opts Options

	mu         sync.Mutex
	owned      bool
	owner      *Owner
	next       uint32
	inhibitors map[uint32]Inhibitor
}

// New returns a server; Run serves it.
func New(opts Options) *Server {
	if opts.Log == nil {
		opts.Log = slog.New(slog.DiscardHandler)
	}
	return &Server{opts: opts, inhibitors: map[uint32]Inhibitor{}}
}

// Inhibitors are the apps keeping the screen on now, oldest first.
func (s *Server) Inhibitors() []Inhibitor {
	s.mu.Lock()
	defer s.mu.Unlock()
	cookies := make([]uint32, 0, len(s.inhibitors))
	for c := range s.inhibitors {
		cookies = append(cookies, c)
	}
	slices.Sort(cookies)
	out := make([]Inhibitor, 0, len(cookies))
	for _, c := range cookies {
		out = append(out, s.inhibitors[c])
	}
	return out
}

// Owned reports whether the server holds the name; when another program
// does, who.
func (s *Server) Owned() (bool, *Owner) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.owned, s.owner
}

// Run serves the interface on conn until ctx ends or the connection does,
// then gives the name back and forgets every inhibitor.
func (s *Server) Run(ctx context.Context, conn *dbus.Conn) error {
	for _, p := range paths {
		unexport, err := conn.Export(p, dbus.Interface{Name: iface, Methods: s.methods()})
		if err != nil {
			return err
		}
		defer unexport()
	}
	sub, err := conn.Subscribe(ctx, dbus.NameOwnerChanged(""))
	if err != nil {
		return err
	}
	defer sub.Close()
	defer func() {
		s.mu.Lock()
		owned := s.owned
		s.owned, s.owner, s.inhibitors = false, nil, map[uint32]Inhibitor{}
		s.mu.Unlock()
		if owned && conn.Err() == nil {
			release, cancel := context.WithTimeout(context.Background(), dbusTimeout)
			conn.ReleaseName(release, busName)
			cancel()
		}
		s.changed()
	}()
	s.take(ctx, conn)
	for {
		select {
		case <-ctx.Done():
			return nil
		case m, ok := <-sub.C:
			if !ok {
				return conn.Err()
			}
			var name, old, new string
			if m.Store(&name, &old, &new) != nil {
				continue
			}
			switch {
			case name == busName && new == "":
				// Whoever held it let go: it's ours to take
				s.take(ctx, conn)
			case new == "" && strings.HasPrefix(name, ":"):
				s.dropSender(name)
			}
		}
	}
}

// take asks for the name, and when it is held, finds out by whom.
func (s *Server) take(ctx context.Context, conn *dbus.Conn) {
	reply, err := conn.RequestName(ctx, busName, dbus.NameDoNotQueue)
	if err != nil {
		s.opts.Log.Warn("asking for org.freedesktop.ScreenSaver", "err", err)
		return
	}
	owned := reply == dbus.NamePrimaryOwner || reply == dbus.NameAlreadyOwner
	var owner *Owner
	if !owned {
		owner = &Owner{}
		if pid, err := conn.ConnectionPID(ctx, busName); err == nil {
			owner.PID = pid
			comm, _ := os.ReadFile("/proc/" + strconv.Itoa(int(pid)) + "/comm")
			owner.Name = strings.TrimSpace(string(comm))
		}
		s.opts.Log.Info("org.freedesktop.ScreenSaver is held by another program", "pid", owner.PID, "name", owner.Name)
	}
	s.mu.Lock()
	s.owned, s.owner = owned, owner
	s.mu.Unlock()
	s.changed()
}

func (s *Server) dropSender(sender string) {
	s.mu.Lock()
	dropped := false
	for c, in := range s.inhibitors {
		if in.sender == sender {
			delete(s.inhibitors, c)
			dropped = true
		}
	}
	s.mu.Unlock()
	if dropped {
		s.changed()
	}
}

func (s *Server) methods() map[string]dbus.Method {
	return map[string]dbus.Method{
		"Inhibit": {In: "ss", Out: "u", Fn: func(_ context.Context, m *dbus.Message) ([]any, error) {
			var in Inhibitor
			if err := m.Store(&in.App, &in.Reason); err != nil {
				return nil, dbus.NewError(dbus.ErrInvalidArgs, "%v", err)
			}
			in.sender = m.Sender
			s.mu.Lock()
			if len(s.inhibitors) >= maxInhibitors {
				s.mu.Unlock()
				return nil, dbus.NewError(dbus.ErrLimitsExceeded, "too many inhibitors")
			}
			s.next++
			if s.next == 0 {
				s.next = 1
			}
			cookie := s.next
			s.inhibitors[cookie] = in
			s.mu.Unlock()
			s.opts.Log.Debug("inhibited", "app", in.App, "reason", in.Reason)
			s.changed()
			return []any{cookie}, nil
		}},
		"UnInhibit": {In: "u", Fn: func(_ context.Context, m *dbus.Message) ([]any, error) {
			var cookie uint32
			if err := m.Store(&cookie); err != nil {
				return nil, dbus.NewError(dbus.ErrInvalidArgs, "%v", err)
			}
			s.mu.Lock()
			in, ok := s.inhibitors[cookie]
			// Only the app that inhibited can release it
			if ok && in.sender == m.Sender {
				delete(s.inhibitors, cookie)
			}
			s.mu.Unlock()
			if ok && in.sender == m.Sender {
				s.changed()
			}
			return nil, nil
		}},
		"SimulateUserActivity": {Fn: func(context.Context, *dbus.Message) ([]any, error) {
			if s.opts.OnActivity != nil {
				s.opts.OnActivity()
			}
			return nil, nil
		}},
		// There is no screensaver to be active: the lock screen is
		// another thing
		"GetActive": {Out: "b", Fn: func(context.Context, *dbus.Message) ([]any, error) {
			return []any{false}, nil
		}},
	}
}

func (s *Server) changed() {
	if s.opts.OnChange != nil {
		s.opts.OnChange()
	}
}

// How long giving the name back may take when the server stops
const dbusTimeout = 2 * time.Second

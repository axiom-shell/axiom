package rpc

import (
	"context"
	"errors"
	"log/slog"
	"net"
	"os"
	"sync"
	"syscall"

	"golang.org/x/sys/unix"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

// Server accepts connections on a listener and serves them with one
// registry.
type Server struct {
	Registry *Registry
	Limits   Limits
	Log      *slog.Logger
	// MaxConns bounds connections at once (default 64)
	MaxConns int
	// CheckPeer vets each connection before it's served (default:
	// SamePeerUser). An error closes it.
	CheckPeer func(net.Conn) error
	// OnConnect and OnClose see each connection come and go.
	OnConnect func(*Conn)
	OnClose   func(*Conn)

	mu     sync.Mutex
	conns  map[*Conn]struct{}
	served sync.WaitGroup // each connection until its handlers are done
}

// Serve accepts until ctx ends or the listener fails, then closes every
// connection and waits for their handlers.
func (s *Server) Serve(ctx context.Context, ln net.Listener) error {
	if s.Log == nil {
		s.Log = slog.New(slog.DiscardHandler)
	}
	if s.MaxConns == 0 {
		s.MaxConns = 64
	}
	if s.CheckPeer == nil {
		s.CheckPeer = SamePeerUser
	}
	if s.Limits == (Limits{}) {
		s.Limits = DefaultLimits()
	}
	s.mu.Lock()
	s.conns = map[*Conn]struct{}{}
	s.mu.Unlock()

	go func() {
		<-ctx.Done()
		ln.Close()
	}()
	defer s.served.Wait()
	defer s.closeAll()
	for {
		nc, err := ln.Accept()
		if err != nil {
			if ctx.Err() != nil || errors.Is(err, net.ErrClosed) {
				return nil
			}
			return err
		}
		if err := s.CheckPeer(nc); err != nil {
			s.Log.Warn("refused a connection", "err", err)
			nc.Close()
			continue
		}
		s.mu.Lock()
		if len(s.conns) >= s.MaxConns {
			s.mu.Unlock()
			s.Log.Warn("refused a connection: too many")
			nc.Close()
			continue
		}
		c := NewConn(nc, s.Registry, s.Limits, s.Log)
		s.conns[c] = struct{}{}
		s.mu.Unlock()
		if s.OnConnect != nil {
			s.OnConnect(c)
		}
		s.served.Add(1)
		go func() {
			defer s.served.Done()
			<-c.Done()
			c.Wait()
			s.mu.Lock()
			delete(s.conns, c)
			s.mu.Unlock()
			if s.OnClose != nil {
				s.OnClose(c)
			}
		}()
	}
}

// Conns is the connections now open.
func (s *Server) Conns() []*Conn {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make([]*Conn, 0, len(s.conns))
	for c := range s.conns {
		out = append(out, c)
	}
	return out
}

// Broadcast notifies every connection keep accepts (nil: all).
func (s *Server) Broadcast(method string, params any, keep func(*Conn) bool) {
	raw, err := marshalParams(params)
	if err != nil {
		s.Log.Error("broadcast", "method", method, "err", err)
		return
	}
	for _, c := range s.Conns() {
		if keep == nil || keep(c) {
			c.Notify(method, raw)
		}
	}
}

// BroadcastLatest is Broadcast for a state: each connection keeps only
// the newest unsent one (Conn.NotifyLatest).
func (s *Server) BroadcastLatest(method string, params any, keep func(*Conn) bool) {
	raw, err := marshalParams(params)
	if err != nil {
		s.Log.Error("broadcast", "method", method, "err", err)
		return
	}
	for _, c := range s.Conns() {
		if keep == nil || keep(c) {
			c.NotifyLatest(method, raw)
		}
	}
}

func (s *Server) closeAll() {
	for _, c := range s.Conns() {
		c.Close()
	}
}

// SamePeerUser accepts a unix-socket peer running as this process's user,
// by the kernel's credentials (SO_PEERCRED), never by anything it says.
func SamePeerUser(nc net.Conn) error {
	uid, err := PeerUID(nc)
	if err != nil {
		return err
	}
	if uid != os.Geteuid() {
		return axerr.New(axerr.Refused, "peer runs as uid %d", uid)
	}
	return nil
}

// PeerUID is a unix-socket peer's uid.
func PeerUID(nc net.Conn) (int, error) {
	cred, err := peerCred(nc)
	if err != nil {
		return -1, err
	}
	return int(cred.Uid), nil
}

// PeerPID is the pid of the process that connected a unix socket, by the
// kernel's credentials.
func PeerPID(nc net.Conn) (int, error) {
	cred, err := peerCred(nc)
	if err != nil {
		return -1, err
	}
	return int(cred.Pid), nil
}

func peerCred(nc net.Conn) (*unix.Ucred, error) {
	uc, ok := nc.(*net.UnixConn)
	if !ok {
		return nil, axerr.New(axerr.Refused, "not a unix socket")
	}
	raw, err := uc.SyscallConn()
	if err != nil {
		return nil, err
	}
	var cred *unix.Ucred
	var credErr error
	if err := raw.Control(func(fd uintptr) {
		cred, credErr = unix.GetsockoptUcred(int(fd), unix.SOL_SOCKET, unix.SO_PEERCRED)
	}); err != nil {
		return nil, err
	}
	if credErr != nil {
		return nil, credErr
	}
	return cred, nil
}

// Listen binds a unix socket at path and narrows it to 0600. Its
// directory must already be private (xdg.PrivateDir): that is what keeps
// others out between the bind and the chmod, not the umask, which is
// process-wide and can't be changed safely with other goroutines running.
// The caller holds the lock that makes removing a stale socket safe.
func Listen(path string) (*net.UnixListener, error) {
	if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
		return nil, axerr.Wrap(axerr.Unavailable, err, "removing the stale socket %s", path)
	}
	ln, err := net.ListenUnix("unix", &net.UnixAddr{Name: path, Net: "unix"})
	if err != nil {
		return nil, axerr.Wrap(axerr.Unavailable, err, "listening on %s", path)
	}
	if err := os.Chmod(path, 0o600); err != nil {
		ln.Close()
		return nil, axerr.Wrap(axerr.Unavailable, err, "narrowing %s", path)
	}
	ln.SetUnlinkOnClose(true)
	return ln, nil
}

// Dial connects to the socket at path after checking it's a socket owned
// by this user (so a planted one is never talked to).
func Dial(ctx context.Context, path string, reg *Registry, log *slog.Logger) (*Conn, error) {
	info, err := os.Lstat(path)
	if err != nil {
		return nil, axerr.Wrap(axerr.Unavailable, err, "no daemon at %s", path)
	}
	st, ok := info.Sys().(*syscall.Stat_t)
	if info.Mode()&os.ModeSocket == 0 || !ok || int(st.Uid) != os.Geteuid() {
		return nil, axerr.New(axerr.Refused, "%s isn't a socket of this user", path)
	}
	var d net.Dialer
	nc, err := d.DialContext(ctx, "unix", path)
	if err != nil {
		return nil, axerr.Wrap(axerr.Unavailable, err, "connecting to %s", path)
	}
	return NewConn(nc, reg, DefaultLimits(), log), nil
}

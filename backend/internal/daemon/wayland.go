package daemon

import (
	"sync"

	"github.com/axiom-shell/axiom/backend/internal/wayland/client"
)

// waylandSession remembers the daemon's Wayland connection for what asks
// about the compositor behind it; a client.Client binding nothing.
type waylandSession struct {
	mu sync.Mutex
	s  *client.Session
}

// CompositorPID is the compositor's process id (0 before the connection).
func (w *waylandSession) CompositorPID() int {
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.s == nil {
		return 0
	}
	return w.s.Conn.PeerPID()
}

func (w *waylandSession) Interfaces() []string { return nil }
func (w *waylandSession) Start(s *client.Session) {
	w.mu.Lock()
	w.s = s
	w.mu.Unlock()
}
func (w *waylandSession) Global(client.Global) {}
func (w *waylandSession) Removed(uint32)       {}
func (w *waylandSession) Ready()               {}

package daemon

import (
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/wayland/client"
)

// Every flag reads off before the connection is ready, and once it
// failed (a protocol error): then ready, so the shell falls back
func TestWaylandNowOffUnlessLive(t *testing.T) {
	t.Parallel()
	pushed := 0
	d := &Daemon{wayland: &waylandSession{onChange: func() { pushed++ }}}
	if got := d.waylandNow(); got != (waylandState{}) {
		t.Errorf("before Ready: %+v", got)
	}
	d.wayland.Failed()
	if got := d.waylandNow(); got != (waylandState{Ready: true}) {
		t.Errorf("failed: %+v", got)
	}
	if pushed != 1 {
		t.Errorf("told %d times, want 1", pushed)
	}
}

// The input method's global is only reported: offered, and gone again,
// each told once the connection is ready
func TestWaylandInputMethodGlobal(t *testing.T) {
	t.Parallel()
	pushed := 0
	w := &waylandSession{onChange: func() { pushed++ }}
	w.Start(nil)
	w.Global(client.Global{Name: 7, Interface: inputMethodGlobal, Version: 1})
	if pushed != 1 {
		t.Errorf("a global before Ready was told: %d", pushed)
	}
	w.Ready()
	if !w.inputMethod() || pushed != 2 {
		t.Errorf("after Ready: %v, told %d", w.inputMethod(), pushed)
	}
	w.Removed(7)
	if w.inputMethod() || pushed != 3 {
		t.Errorf("removed: %v, told %d", w.inputMethod(), pushed)
	}
	w.Global(client.Global{Name: 9, Interface: inputMethodGlobal, Version: 1})
	if !w.inputMethod() || pushed != 4 {
		t.Errorf("added later: %v, told %d", w.inputMethod(), pushed)
	}
	w.Start(nil)
	if w.inputMethod() {
		t.Error("a new connection kept the old one's global")
	}
}

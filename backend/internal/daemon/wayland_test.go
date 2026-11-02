package daemon

import "testing"

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

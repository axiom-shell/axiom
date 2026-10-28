package daemon

import (
	"slices"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/rpc"
)

// The contract lists exactly the methods a running daemon registers (and
// the greeter's own), and every push and topic once
func TestContractIsTheRegistry(t *testing.T) {
	t.Parallel()
	td := newTestDaemon(t)
	got := make(chan []string, 1)
	td.registered = func(reg *rpc.Registry) { got <- reg.Methods() }
	td.start(t, nil)
	var running []string
	select {
	case running = <-got:
	case <-time.After(10 * time.Second):
		t.Fatal("no registry")
	}
	greeterOnly := rpc.NewRegistry()
	greeterOnlyMethods(greeterOnly, func(string) string { return "" }, func() any { return nil }, func(any) {})
	running = append(running, greeterOnly.Methods()...)
	slices.Sort(running)

	c := BuildContract()
	var listed []string
	for _, m := range c.Methods {
		listed = append(listed, m.Method)
	}
	if !slices.Equal(listed, running) {
		t.Errorf("contract methods %v\nrunning daemon's %v", listed, running)
	}
	seen := map[string]bool{}
	for _, p := range c.Pushes {
		if seen[p.Method] {
			t.Errorf("push %s listed twice", p.Method)
		}
		seen[p.Method] = true
	}
	if len(c.Topics) == 0 || c.Topics[0].Request.Kind == "" {
		t.Errorf("topics %+v", c.Topics)
	}
}

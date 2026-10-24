package wire_test

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/wayland/wire"
	"github.com/axiom-shell/axiom/backend/internal/wayland/wire/wiretest"
)

// A sync's id comes back with the compositor's delete_id and is reused.
func TestConnReusesDeletedIDs(t *testing.T) {
	t.Parallel()
	f := wiretest.New(t, nil, nil)
	c, err := wire.Dial(f.Socket)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go c.Run(ctx)
	done := make(chan struct{})
	if err := c.Sync(func() { close(done) }); err != nil {
		t.Fatal(err)
	}
	<-done
	// delete_id follows done: once it's handled, the next object gets 2
	deadline := time.Now().Add(5 * time.Second)
	for {
		id := c.NewObject(nil)
		if id == 2 {
			break
		}
		c.Forget(id)
		if time.Now().After(deadline) {
			t.Fatalf("id %d, want 2 reused", id)
		}
		time.Sleep(5 * time.Millisecond)
	}
}

// A protocol error ends Run with the compositor's message; a bound
// object's events reach its handler.
func TestConnDispatchesAndReportsErrors(t *testing.T) {
	t.Parallel()
	f := wiretest.New(t, []wiretest.Global{{Name: 5, Interface: "wl_seat", Version: 9}},
		func(c *wiretest.Compositor, r wiretest.Request) {
			if r.Interface == "wl_seat" {
				id := r.Args.Uint()
				c.Send(id, 1, wire.String("seat0"))
				c.Send(1, 0, wire.Uint(id), wire.Uint(3), wire.String("bad request"))
			}
		})
	c, err := wire.Dial(f.Socket)
	if err != nil {
		t.Fatal(err)
	}
	seat := make(chan string, 1)
	var registry uint32
	registry, err = c.Registry(func(op uint16, a *wire.Args) {
		if op == wire.EvGlobal {
			name, iface, version := a.Uint(), a.String(), a.Uint()
			c.Bind(registry, name, iface, version, func(op uint16, a *wire.Args) { seat <- a.String() })
		}
	})
	if err != nil {
		t.Fatal(err)
	}
	err = c.Run(context.Background())
	if got := <-seat; got != "seat0" {
		t.Errorf("seat name %q", got)
	}
	if err == nil || !strings.Contains(err.Error(), "bad request") {
		t.Errorf("Run returned %v", err)
	}
}

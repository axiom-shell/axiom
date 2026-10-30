package wire_test

import (
	"context"
	"io"
	"strings"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/testkit"
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
	var id uint32
	if !testkit.Eventually(func() bool {
		if id = c.NewObject(nil); id != 2 {
			c.Forget(id)
		}
		return id == 2
	}) {
		t.Fatalf("id %d, want 2 reused", id)
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

// Descriptors, fixed numbers and arrays cross both ways: a request's fd
// reaches the compositor, and an event's comes back to the handler.
func TestConnPassesDescriptorsAndValues(t *testing.T) {
	t.Parallel()
	type got struct {
		text  string
		fixed float64
		array []byte
	}
	requests := make(chan got, 1)
	var obj uint32
	f := wiretest.New(t, nil, func(c *wiretest.Compositor, r wiretest.Request) {
		fd, err := r.Args.Fd()
		if err != nil {
			t.Error(err)
			return
		}
		defer fd.Close()
		b, _ := io.ReadAll(fd)
		requests <- got{string(b), r.Args.Fixed(), r.Args.Array()}
		reply, _ := wire.SealedFile("reply", []byte("from the compositor"))
		defer reply.Close()
		c.Send(r.Object, 0, wire.Fixed(-1.5), wire.Fd(reply), wire.Array([]byte{9, 8, 7, 6, 5}))
	})
	c, err := wire.Dial(f.Socket)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go c.Run(ctx)

	events := make(chan got, 1)
	obj = c.NewObject(func(op uint16, a *wire.Args) {
		fixed := a.Fixed()
		fd, err := a.Fd()
		if err != nil {
			t.Error(err)
			return
		}
		defer fd.Close()
		b, _ := io.ReadAll(fd)
		events <- got{string(b), fixed, a.Array()}
	})
	data, err := wire.SealedFile("keymap", []byte("xkb_keymap {}"))
	if err != nil {
		t.Fatal(err)
	}
	defer data.Close()
	if _, err := data.Write([]byte("x")); err == nil {
		t.Error("a sealed file took a write")
	}
	if err := c.Send(obj, 1, wire.Fd(data), wire.Fixed(2.25), wire.Array([]byte{1, 2, 3})); err != nil {
		t.Fatal(err)
	}
	for _, ch := range []chan got{requests, events} {
		select {
		case g := <-ch:
			if ch == requests && (g.text != "xkb_keymap {}" || g.fixed != 2.25 || string(g.array) != "\x01\x02\x03") {
				t.Errorf("request %+v", g)
			}
			if ch == events && (g.text != "from the compositor" || g.fixed != -1.5 || len(g.array) != 5) {
				t.Errorf("event %+v", g)
			}
		case <-time.After(testkit.Bound(3 * time.Second)):
			t.Fatal("timed out")
		}
	}
}

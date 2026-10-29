package datacontrol

import (
	"context"
	"io"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/testkit"
	"github.com/axiom-shell/axiom/backend/internal/wayland/client"
	"github.com/axiom-shell/axiom/backend/internal/wayland/seat"
	"github.com/axiom-shell/axiom/backend/internal/wayland/wire"
	"github.com/axiom-shell/axiom/backend/internal/wayland/wire/wiretest"
)

type fake struct {
	*wiretest.Compositor
	mu        sync.Mutex
	iface     string
	manager   uint32
	device    uint32
	sources   map[uint32][]string // source → mimes offered
	selection uint32              // the source set_selection named
	served    map[string]string   // what an offer of ours holds, by mime
	destroyed []uint32
	selected  chan uint32
}

func newFake(t *testing.T, ifaces ...string) *fake {
	f := &fake{sources: map[uint32][]string{}, served: map[string]string{}, selected: make(chan uint32, 4)}
	globals := []wiretest.Global{{Name: 1, Interface: "wl_seat", Version: 7}}
	for i, iface := range ifaces {
		globals = append(globals, wiretest.Global{Name: uint32(2 + i), Interface: iface, Version: 2})
	}
	f.Compositor = wiretest.New(t, globals, f.request)
	return f
}

func (f *fake) request(c *wiretest.Compositor, r wiretest.Request) {
	f.mu.Lock()
	defer f.mu.Unlock()
	switch {
	case r.Interface == ExtManager || r.Interface == WlrManager:
		f.iface, f.manager = r.Interface, r.Args.Uint()
	case r.Interface != "":
	case r.Object == f.manager && r.Opcode == opGetDataDevice:
		f.device = r.Args.Uint()
	case r.Object == f.manager && r.Opcode == opCreateDataSource:
		f.sources[r.Args.Uint()] = nil
	case hasKey(f.sources, r.Object) && r.Opcode == opSourceOffer:
		f.sources[r.Object] = append(f.sources[r.Object], r.Args.String())
	case r.Object == f.device && r.Opcode == opSetSelection:
		f.selection = r.Args.Uint()
		f.selected <- f.selection
	case r.Object >= 0xff000000 && r.Opcode == opOfferReceive:
		mime := r.Args.String()
		fd, err := r.Args.Fd()
		if err != nil {
			return
		}
		data := f.served[mime]
		go func() { fd.WriteString(data); fd.Close() }()
	case r.Object >= 0xff000000 && r.Opcode == opOfferDestroy:
		f.destroyed = append(f.destroyed, r.Object)
	}
}

func hasKey(m map[uint32][]string, k uint32) bool { _, ok := m[k]; return ok }

// offer announces a selection with mimes holding data.
func (f *fake) offer(id uint32, data map[string]string) {
	f.mu.Lock()
	device := f.device
	f.served = data
	f.mu.Unlock()
	f.Send(device, evDataOffer, wire.Uint(id))
	for m := range data {
		f.Send(id, evOfferMime, wire.String(m))
	}
	f.Send(device, evSelection, wire.Uint(id))
}

func start(t *testing.T, f *fake) (*Device, chan *Offer) {
	t.Helper()
	st := seat.New()
	offers := make(chan *Offer, 8)
	d := New(Options{Seat: st, OnSelection: func(o *Offer) { offers <- o }})
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- client.Run(ctx, f.Socket, st, d) }()
	t.Cleanup(func() { cancel(); <-done })
	if !testkit.Eventually(func() bool { f.mu.Lock(); defer f.mu.Unlock(); return f.device != 0 }) {
		t.Fatal("no device")
	}
	return d, offers
}

func next[T any](t *testing.T, ch chan T) T {
	t.Helper()
	select {
	case v := <-ch:
		return v
	case <-time.After(testkit.Bound(3 * time.Second)):
		t.Fatal("timed out")
	}
	var zero T
	return zero
}

func TestPrefersExt(t *testing.T) {
	t.Parallel()
	f := newFake(t, WlrManager, ExtManager)
	d, _ := start(t, f)
	if d.Protocol() != "ext" || f.iface != ExtManager {
		t.Errorf("bound %q (%s)", d.Protocol(), f.iface)
	}
	f2 := newFake(t, WlrManager)
	d2, _ := start(t, f2)
	if d2.Protocol() != "wlr" {
		t.Errorf("bound %q", d2.Protocol())
	}
}

func TestReadsTheSelection(t *testing.T) {
	t.Parallel()
	f := newFake(t, ExtManager)
	d, offers := start(t, f)
	f.offer(0xff000001, map[string]string{"text/plain;charset=utf-8": "héllo"})
	o := next(t, offers)
	if o == nil || !o.Has("text/plain;charset=utf-8") {
		t.Fatalf("offer %+v", o)
	}
	data, err := o.Receive(context.Background(), "text/plain;charset=utf-8", 1<<10, time.Second)
	if err != nil || string(data) != "héllo" {
		t.Fatalf("read %q, %v", data, err)
	}
	if _, err := o.Receive(context.Background(), "text/plain;charset=utf-8", 2, time.Second); err == nil {
		t.Error("read past the limit")
	}
	if got := d.Mimes(); len(got) != 1 {
		t.Errorf("mimes %v", got)
	}
	// The next selection replaces it: the old offer goes
	f.offer(0xff000002, map[string]string{"text/plain": "two"})
	next(t, offers)
	if _, err := o.Receive(context.Background(), "text/plain", 10, time.Second); err == nil {
		t.Error("read a replaced offer")
	}
	var destroyed []uint32
	if !testkit.Eventually(func() bool {
		f.mu.Lock()
		destroyed = append([]uint32(nil), f.destroyed...)
		f.mu.Unlock()
		return len(destroyed) == 1 && destroyed[0] == 0xff000001
	}) {
		t.Fatalf("destroyed %v", destroyed)
	}
	// Cleared
	f.Send(f.device, evSelection, wire.Uint(0))
	if o := next(t, offers); o != nil {
		t.Errorf("cleared to %+v", o)
	}
}

func TestSetServesFromMemory(t *testing.T) {
	t.Parallel()
	f := newFake(t, ExtManager)
	d, _ := start(t, f)
	if err := d.Set([]string{"text/plain;charset=utf-8", "text/plain"}, map[string][]byte{
		"text/plain;charset=utf-8": []byte("copied"),
		"text/plain":               []byte("copied"),
	}); err != nil {
		t.Fatal(err)
	}
	src := next(t, f.selected)
	f.mu.Lock()
	mimes := f.sources[src]
	f.mu.Unlock()
	if len(mimes) != 2 || mimes[0] != "text/plain;charset=utf-8" {
		t.Fatalf("offered %v", mimes)
	}
	// A paste: the compositor hands the source a pipe's write end
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	defer r.Close()
	f.Send(src, evSourceSend, wire.String("text/plain"), wire.Fd(w))
	w.Close()
	r.SetReadDeadline(time.Now().Add(3 * time.Second))
	data, err := io.ReadAll(r)
	if err != nil || string(data) != "copied" {
		t.Errorf("pasted %q, %v", data, err)
	}
}

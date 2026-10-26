// Package datacontrol reads and sets the clipboard over
// ext_data_control_v1, or wlr's zwlr_data_control_v1 where that's all
// there is (the two have the same requests and events), in place of
// wl-paste and wl-copy: the selection's offers as they come, read
// through a pipe off the connection's goroutine, and selections of the
// daemon's own, served from memory. The primary selection is left alone.
package datacontrol

import (
	"context"
	"io"
	"log/slog"
	"os"
	"slices"
	"sync"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/wayland/client"
	"github.com/axiom-shell/axiom/backend/internal/wayland/seat"
	"github.com/axiom-shell/axiom/backend/internal/wayland/wire"
)

// The interfaces, by protocol, and their opcodes (ext-data-control-v1.xml;
// wlr-data-control-unstable-v1.xml has the same)
const (
	ExtManager = "ext_data_control_manager_v1"
	WlrManager = "zwlr_data_control_manager_v1"

	opCreateDataSource = 0 // manager (id)
	opGetDataDevice    = 1 // manager (id, seat)
	opManagerDestroy   = 2
	opSetSelection     = 0 // device (source | 0)
	opDeviceDestroy    = 1
	evDataOffer        = 0 // device (new offer)
	evSelection        = 1 // device (offer | 0)
	evFinished         = 2 // device
	evPrimarySelection = 3 // device (offer | 0): not read, let go at once
	opSourceOffer      = 0 // source (mime)
	opSourceDestroy    = 1
	evSourceSend       = 0 // source (mime, fd)
	evSourceCancelled  = 1
	opOfferReceive     = 0 // offer (mime, fd)
	opOfferDestroy     = 1
	evOfferMime        = 0 // offer (mime)
)

// Options configure the device.
type Options struct {
	Seat *seat.Tracker
	Log  *slog.Logger
	// OnSelection is told of every new selection, on the connection's
	// goroutine: it must not block (read the offer elsewhere). nil: the
	// clipboard was cleared.
	OnSelection func(*Offer)
	// OnChange is told when the protocol comes or goes
	OnChange func()
	// Go runs work that outlives a call (serving a paste) on a goroutine
	// its owner stops (nil: a plain goroutine)
	Go func(func(context.Context))
}

// Device is the clipboard; it is a client.Client.
type Device struct {
	opts Options

	mu      sync.Mutex
	s       *client.Session
	offered map[string]client.Global // by interface
	ready   bool
	iface   string // the protocol bound, "" without
	manager uint32
	device  uint32
	pending map[uint32]*Offer // offers announced, not yet the selection
	current *Offer
	sources map[uint32]map[string][]byte
}

// Offer is a selection on offer: its types, read with Receive while it's
// still the selection.
type Offer struct {
	d     *Device
	id    uint32
	mimes []string
	alive bool // until the next selection replaces it
}

// New returns a device; it binds once the connection's first globals are
// known (ext's manager is preferred).
func New(opts Options) *Device {
	if opts.Log == nil {
		opts.Log = slog.New(slog.DiscardHandler)
	}
	d := &Device{opts: opts, offered: map[string]client.Global{}}
	opts.Seat.OnChange(func(uint32) {
		d.mu.Lock()
		d.bind()
		d.mu.Unlock()
	})
	return d
}

// Protocol is the protocol bound: "ext", "wlr" or "" (none offered).
func (d *Device) Protocol() string {
	d.mu.Lock()
	defer d.mu.Unlock()
	switch d.iface {
	case ExtManager:
		return "ext"
	case WlrManager:
		return "wlr"
	}
	return ""
}

// Mimes are the current selection's types (nil: none, or a clipboard
// nobody serves).
func (d *Device) Mimes() []string {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.current == nil {
		return nil
	}
	return append([]string(nil), d.current.mimes...)
}

// Current is the current selection, nil without one.
func (d *Device) Current() *Offer {
	d.mu.Lock()
	defer d.mu.Unlock()
	return d.current
}

// Mimes are the offer's types, in the order the source gave them.
func (o *Offer) Mimes() []string { return append([]string(nil), o.mimes...) }

// Has reports whether the offer has a type.
func (o *Offer) Has(mime string) bool { return slices.Contains(o.mimes, mime) }

// Receive reads the offer as mime: at most max bytes (an error past
// that), within timeout. It blocks: never on the connection's goroutine.
func (o *Offer) Receive(ctx context.Context, mime string, max int, timeout time.Duration) ([]byte, error) {
	r, w, err := os.Pipe()
	if err != nil {
		return nil, axerr.Wrap(axerr.Internal, err, "a pipe for the clipboard")
	}
	defer r.Close()
	d := o.d
	d.mu.Lock()
	if !o.alive {
		d.mu.Unlock()
		w.Close()
		return nil, axerr.New(axerr.Unavailable, "the clipboard changed meanwhile")
	}
	err = d.s.Conn.Send(o.id, opOfferReceive, wire.String(mime), wire.Fd(w))
	d.mu.Unlock()
	// Ours goes: the source holds the write end now
	w.Close()
	if err != nil {
		return nil, axerr.Wrap(axerr.Unavailable, err, "asking for the clipboard")
	}
	deadline := time.Now().Add(timeout)
	if dl, ok := ctx.Deadline(); ok && dl.Before(deadline) {
		deadline = dl
	}
	r.SetReadDeadline(deadline)
	data, err := io.ReadAll(io.LimitReader(r, int64(max)+1))
	if err != nil {
		return nil, axerr.Wrap(axerr.Unavailable, err, "reading the clipboard")
	}
	if len(data) > max {
		return nil, axerr.New(axerr.BadRequest, "the clipboard holds more than %d bytes", max)
	}
	return data, nil
}

// Set makes the daemon the clipboard's source, offering each of mimes
// (in order) with data[mime]: copying, as wl-copy did.
func (d *Device) Set(mimes []string, data map[string][]byte) error {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.device == 0 {
		return axerr.New(axerr.Unavailable, "the compositor offers no clipboard control")
	}
	c := d.s.Conn
	var src uint32
	src = c.NewObject(func(op uint16, a *wire.Args) { d.sourceEvent(src, op, a) })
	if err := c.Send(d.manager, opCreateDataSource, wire.Uint(src)); err != nil {
		return axerr.Wrap(axerr.Unavailable, err, "making a clipboard source")
	}
	d.sources[src] = data
	for _, m := range mimes {
		c.Send(src, opSourceOffer, wire.String(m))
	}
	return c.Send(d.device, opSetSelection, wire.Uint(src))
}

func (d *Device) sourceEvent(src uint32, op uint16, a *wire.Args) {
	switch op {
	case evSourceSend:
		mime := a.String()
		f, err := a.Fd()
		if err != nil {
			return
		}
		d.mu.Lock()
		data := d.sources[src][mime]
		d.mu.Unlock()
		// A paste is written off the connection's goroutine: the reader
		// may be slow, or never read
		write := func(context.Context) {
			defer f.Close()
			f.SetWriteDeadline(time.Now().Add(10 * time.Second))
			f.Write(data)
		}
		if d.opts.Go != nil {
			d.opts.Go(write)
		} else {
			go write(context.Background())
		}
	case evSourceCancelled:
		// Another selection replaced it
		d.mu.Lock()
		delete(d.sources, src)
		if d.s != nil {
			d.s.Conn.Send(src, opSourceDestroy)
			d.s.Conn.Forget(src)
		}
		d.mu.Unlock()
	}
}

// bind makes the device once a manager and the seat are known; d.mu is
// held.
func (d *Device) bind() {
	seatID := d.opts.Seat.ID()
	if !d.ready || d.device != 0 || seatID == 0 || d.s == nil {
		return
	}
	g, ok := d.offered[ExtManager]
	if !ok {
		if g, ok = d.offered[WlrManager]; !ok {
			return
		}
	}
	c := d.s.Conn
	var err error
	if d.manager, _, err = d.s.Bind(g, 1, nil); err != nil {
		return
	}
	d.iface = g.Interface
	d.device = c.NewObject(d.deviceEvent)
	c.Send(d.manager, opGetDataDevice, wire.Uint(d.device), wire.Uint(seatID))
	d.opts.Log.Debug("clipboard control", "protocol", g.Interface)
}

func (d *Device) deviceEvent(op uint16, a *wire.Args) {
	switch op {
	case evDataOffer:
		id := a.Uint()
		o := &Offer{d: d, id: id, alive: true}
		d.mu.Lock()
		d.pending[id] = o
		d.mu.Unlock()
		d.s.Conn.Adopt(id, func(op uint16, a *wire.Args) {
			if op == evOfferMime {
				m := a.String()
				d.mu.Lock()
				o.mimes = append(o.mimes, m)
				d.mu.Unlock()
			}
		})
	case evSelection:
		id := a.Uint()
		d.mu.Lock()
		old := d.current
		next := d.pending[id]
		delete(d.pending, id)
		d.current = next
		if old != nil {
			d.drop(old)
		}
		// Offers announced but not made the selection (a primary
		// selection's) go too
		for oid, o := range d.pending {
			d.drop(o)
			delete(d.pending, oid)
		}
		d.mu.Unlock()
		if d.opts.OnSelection != nil {
			d.opts.OnSelection(next)
		}
	case evPrimarySelection:
		id := a.Uint()
		d.mu.Lock()
		if o := d.pending[id]; o != nil {
			d.drop(o)
			delete(d.pending, id)
		}
		d.mu.Unlock()
	case evFinished:
		// The device is gone (the seat went): make another
		d.mu.Lock()
		d.reset()
		d.bind()
		d.mu.Unlock()
	}
}

// drop destroys an offer; d.mu is held.
func (d *Device) drop(o *Offer) {
	if !o.alive {
		return
	}
	o.alive = false
	d.s.Conn.Send(o.id, opOfferDestroy)
	d.s.Conn.Forget(o.id)
}

// reset forgets the device and its offers; d.mu is held.
func (d *Device) reset() {
	if d.device != 0 && d.s != nil {
		d.s.Conn.Send(d.device, opDeviceDestroy)
		d.s.Conn.Forget(d.device)
	}
	if d.current != nil {
		d.drop(d.current)
	}
	for _, o := range d.pending {
		d.drop(o)
	}
	d.device, d.current, d.pending = 0, nil, map[uint32]*Offer{}
}

// Interfaces (client.Client)
func (d *Device) Interfaces() []string { return []string{ExtManager, WlrManager} }

// Start (client.Client)
func (d *Device) Start(s *client.Session) {
	d.mu.Lock()
	d.s, d.ready, d.iface, d.manager, d.device = s, false, "", 0, 0
	d.offered, d.pending, d.current, d.sources = map[string]client.Global{}, map[uint32]*Offer{}, nil, map[uint32]map[string][]byte{}
	d.mu.Unlock()
}

// Global notes a manager offered (client.Client).
func (d *Device) Global(g client.Global) {
	d.mu.Lock()
	d.offered[g.Interface] = g
	before := d.iface
	d.bind()
	bound := d.iface != before
	d.mu.Unlock()
	if bound {
		d.changed()
	}
}

// Removed drops the manager in use (client.Client): the other one, if
// offered, takes over.
func (d *Device) Removed(name uint32) {
	d.mu.Lock()
	var gone string
	for iface, g := range d.offered {
		if g.Name == name {
			gone = iface
		}
	}
	if gone == "" {
		d.mu.Unlock()
		return
	}
	delete(d.offered, gone)
	if gone == d.iface {
		d.reset()
		d.s.Conn.Send(d.manager, opManagerDestroy)
		d.s.Conn.Forget(d.manager)
		d.iface, d.manager = "", 0
		d.bind()
	}
	d.mu.Unlock()
	d.changed()
}

// Ready binds the device on the protocol preferred among those offered
// (client.Client).
func (d *Device) Ready() {
	d.mu.Lock()
	d.ready = true
	d.bind()
	d.mu.Unlock()
	d.changed()
}

func (d *Device) changed() {
	if d.opts.OnChange != nil {
		d.opts.OnChange()
	}
}

package bluez

import (
	"slices"
	"sync"
	"time"
)

// Event is devices connecting or disconnecting, for the OSD's card:
// those within Join of each other are one event (the radio turning on
// reconnects several), and the disconnects of the radio turning off are
// none (its own change says it). Only BlueZ's signals make one, never a
// sync.
type Event struct {
	// Kind is "connected" or "disconnected"
	Kind    string        `json:"kind"`
	Devices []EventDevice `json:"devices"`
}

// EventDevice is a device of an event, as the state shows it.
type EventDevice struct {
	Address string `json:"address"`
	Name    string `json:"name"`
	// Icon is BlueZ's freedesktop icon name, "" none
	Icon string `json:"icon"`
	// Battery is its level, 0–100, or -1 when it reports none
	Battery int `json:"battery"`
}

const (
	kindConnected    = "connected"
	kindDisconnected = "disconnected"
	// joinCap: a run of changes each within Join of the last is one
	// event until it's this many Joins long
	joinCap = 3
)

// events gathers the connects and disconnects BlueZ's signals make into
// events, sent through OnEvent once Join passes without another.
type events struct {
	join  time.Duration
	send  func(Event)
	state func() State

	mu sync.Mutex
	// pending by kind: the devices in order, as they were when they changed
	pending map[string][]EventDevice
	timers  map[string]*time.Timer
	first   map[string]time.Time
	// offUntil: the radio turned off; disconnects until then are its own
	offUntil time.Time
}

func newEvents(join time.Duration, state func() State, send func(Event)) *events {
	return &events{
		join: join, send: send, state: state,
		pending: map[string][]EventDevice{}, timers: map[string]*time.Timer{}, first: map[string]time.Time{},
	}
}

// changed compares two states a signal moved between: a device known in
// both connecting or disconnecting, and the adapter powering off.
func (e *events) changed(prev, next State) {
	if e.send == nil {
		return
	}
	was := map[string]Device{}
	for _, d := range prev.Devices {
		was[d.Address] = d
	}
	now := time.Now()
	e.mu.Lock()
	defer e.mu.Unlock()
	if prev.Adapter != nil && prev.Adapter.Powered && (next.Adapter == nil || !next.Adapter.Powered) {
		// Its devices dropping with it, before or after, are its own
		e.offUntil = now.Add(e.join)
		e.stop(kindDisconnected)
	}
	for _, d := range next.Devices {
		p, ok := was[d.Address]
		if !ok || p.Connected == d.Connected {
			continue
		}
		if d.Connected {
			e.add(kindConnected, kindDisconnected, eventDevice(d), now)
		} else if now.Before(e.offUntil) {
			// The radio's
			e.drop(kindConnected, d.Address)
		} else {
			// Its battery as it was, before the disconnect took it
			e.add(kindDisconnected, kindConnected, eventDevice(p), now)
		}
	}
}

// add gathers a change of kind; one undoing the opposite kind still
// pending (a blip) cancels it instead.
func (e *events) add(kind, opposite string, d EventDevice, now time.Time) {
	if e.drop(opposite, d.Address) {
		return
	}
	e.pending[kind] = append(slices.DeleteFunc(e.pending[kind], func(x EventDevice) bool { return x.Address == d.Address }), d)
	if t := e.timers[kind]; t != nil {
		t.Stop()
	} else {
		e.first[kind] = now
	}
	wait := min(e.join, e.first[kind].Add(joinCap*e.join).Sub(now))
	e.timers[kind] = time.AfterFunc(max(wait, 0), func() { e.flush(kind) })
}

// drop takes a pending device out (e.mu held); true when it was there.
func (e *events) drop(kind, address string) bool {
	n := len(e.pending[kind])
	e.pending[kind] = slices.DeleteFunc(e.pending[kind], func(x EventDevice) bool { return x.Address == address })
	if len(e.pending[kind]) == n {
		return false
	}
	if len(e.pending[kind]) == 0 {
		e.stop(kind)
	}
	return true
}

// stop forgets what's pending of a kind (e.mu held).
func (e *events) stop(kind string) {
	if t := e.timers[kind]; t != nil {
		t.Stop()
	}
	delete(e.timers, kind)
	delete(e.pending, kind)
	delete(e.first, kind)
}

// reset forgets everything pending: BlueZ was read afresh.
func (e *events) reset() {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.stop(kindConnected)
	e.stop(kindDisconnected)
	e.offUntil = time.Time{}
}

// flush sends what's pending of a kind: devices connected as they are
// now (their battery may have come in since), those still so.
func (e *events) flush(kind string) {
	e.mu.Lock()
	devs := e.pending[kind]
	e.stop(kind)
	e.mu.Unlock()
	st := e.state()
	out := []EventDevice{}
	for _, d := range devs {
		i := slices.IndexFunc(st.Devices, func(x Device) bool { return x.Address == d.Address })
		switch {
		case kind == kindConnected && i >= 0 && st.Devices[i].Connected:
			out = append(out, eventDevice(st.Devices[i]))
		case kind == kindDisconnected && (i < 0 || !st.Devices[i].Connected):
			out = append(out, d)
		}
	}
	if len(out) > 0 {
		e.send(Event{Kind: kind, Devices: out})
	}
}

func eventDevice(d Device) EventDevice {
	return EventDevice{Address: d.Address, Name: d.Name, Icon: d.Icon, Battery: d.Battery}
}

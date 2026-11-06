package bluez

import (
	"slices"
	"sync"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/dbus/dbustest"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

const join = 60 * time.Millisecond

// eventLog records the events a service sends.
type eventLog struct {
	mu  sync.Mutex
	got []Event
}

func (l *eventLog) add(e Event) {
	l.mu.Lock()
	l.got = append(l.got, e)
	l.mu.Unlock()
}

func (l *eventLog) take() []Event {
	l.mu.Lock()
	defer l.mu.Unlock()
	out := l.got
	l.got = nil
	return out
}

// startEvents runs a service against a fake BlueZ holding objs, recording
// its events, once synced.
func startEvents(t *testing.T, objs dbus.ManagedObjects) (*fakeBlueZ, *harness, *eventLog, *dbustest.Bus) {
	t.Helper()
	bus := dbustest.New(t)
	f := newFakeBlueZ(t, bus, objs)
	log := &eventLog{}
	h := startWith(t, bus, func(o *Options) {
		o.Join = join
		o.OnEvent = log.add
	})
	h.wait(t, "sync", func(st State) bool { return st.Available })
	return f, h, log, bus
}

// quiet waits past any event the changes so far could make.
func quiet() { time.Sleep(joinCap*join + 100*time.Millisecond) }

func eventAddrs(e Event) []string {
	out := []string{}
	for _, d := range e.Devices {
		out = append(out, d.Address)
	}
	return out
}

func waitEvents(t *testing.T, log *eventLog, n int) []Event {
	t.Helper()
	var got []Event
	if !testkit.Eventually(func() bool {
		got = append(got, log.take()...)
		return len(got) >= n
	}) {
		t.Fatalf("waited for %d events, got %+v", n, got)
	}
	quiet()
	return append(got, log.take()...)
}

const speaker = "AA:00:00:00:00:05"

func withSpeaker() dbus.ManagedObjects {
	objs := fixture()
	objs[devPath(hci0, speaker)] = withBattery(device(hci0, speaker, "Speaker", true, false, map[string]dbus.Variant{"Icon": v("audio-card")}), 60)
	return objs
}

// Connects close together are one event, disconnects another; each
// device as the state shows it
func TestEventsJoin(t *testing.T) {
	t.Parallel()
	f, _, log, _ := startEvents(t, withSpeaker())
	f.changed(devPath(hci0, mouse), ifaceDevice, "Connected", true)
	time.Sleep(join / 3)
	f.changed(devPath(hci0, speaker), ifaceDevice, "Connected", true)
	got := waitEvents(t, log, 1)
	if len(got) != 1 || got[0].Kind != "connected" || !slices.Equal(eventAddrs(got[0]), []string{mouse, speaker}) {
		t.Fatalf("connects: %+v", got)
	}
	if sp := got[0].Devices[1]; sp != (EventDevice{Address: speaker, Name: "Speaker", Icon: "audio-card", Battery: 60}) {
		t.Errorf("speaker %+v", sp)
	}

	f.changed(devPath(hci0, speaker), ifaceDevice, "Connected", false)
	f.changed(devPath(hci0, headset), ifaceDevice, "Connected", false)
	got = waitEvents(t, log, 1)
	// Those settled together in the state's order
	if len(got) != 1 || got[0].Kind != "disconnected" || !slices.Equal(eventAddrs(got[0]), []string{headset, speaker}) {
		t.Fatalf("disconnects: %+v", got)
	}
	// Its battery as it was while connected
	if got[0].Devices[0].Battery != 80 {
		t.Errorf("headset %+v", got[0].Devices[0])
	}

	// One far from the other: two events
	f.changed(devPath(hci0, headset), ifaceDevice, "Connected", true)
	quiet()
	f.changed(devPath(hci0, speaker), ifaceDevice, "Connected", true)
	got = waitEvents(t, log, 2)
	if len(got) != 2 || !slices.Equal(eventAddrs(got[0]), []string{headset}) || !slices.Equal(eventAddrs(got[1]), []string{speaker}) {
		t.Errorf("apart: %+v", got)
	}

	// A blip (gone and back at once) is nothing
	f.changed(devPath(hci0, headset), ifaceDevice, "Connected", false)
	time.Sleep(join / 3)
	f.changed(devPath(hci0, headset), ifaceDevice, "Connected", true)
	quiet()
	if got := log.take(); len(got) != 0 {
		t.Errorf("blip: %+v", got)
	}
}

// The radio turning off drops its devices' disconnects, whichever comes
// first; turning on, their reconnects are one event
func TestEventsRadioOff(t *testing.T) {
	t.Parallel()
	objs := withSpeaker()
	objs[devPath(hci0, speaker)][ifaceDevice]["Connected"] = v(true)
	f, h, log, _ := startEvents(t, objs)

	// The devices first, as BlueZ does
	f.changed(devPath(hci0, headset), ifaceDevice, "Connected", false)
	f.changed(devPath(hci0, speaker), ifaceDevice, "Connected", false)
	f.changed(hci0, ifaceAdapter, "Powered", false)
	h.wait(t, "off", func(st State) bool { return !st.Adapter.Powered })
	quiet()
	if got := log.take(); len(got) != 0 {
		t.Errorf("devices then the radio: %+v", got)
	}

	f.changed(hci0, ifaceAdapter, "Powered", true)
	f.changed(devPath(hci0, headset), ifaceDevice, "Connected", true)
	time.Sleep(join / 2)
	f.changed(devPath(hci0, speaker), ifaceDevice, "Connected", true)
	got := waitEvents(t, log, 1)
	if len(got) != 1 || got[0].Kind != "connected" || !slices.Equal(eventAddrs(got[0]), []string{headset, speaker}) {
		t.Fatalf("radio on: %+v", got)
	}

	// The radio first
	f.changed(hci0, ifaceAdapter, "Powered", false)
	h.wait(t, "off again", func(st State) bool { return !st.Adapter.Powered })
	f.changed(devPath(hci0, headset), ifaceDevice, "Connected", false)
	f.changed(devPath(hci0, speaker), ifaceDevice, "Connected", false)
	quiet()
	if got := log.take(); len(got) != 0 {
		t.Errorf("the radio then devices: %+v", got)
	}
}

// A sync (BlueZ restarting) reads devices connected or not afresh: no
// event, though they changed
func TestEventsNotOnSync(t *testing.T) {
	t.Parallel()
	f, h, log, bus := startEvents(t, fixture())
	f.conn.Close()
	h.wait(t, "gone", func(st State) bool { return !st.Available })
	objs := fixture()
	objs[devPath(hci0, headset)][ifaceDevice]["Connected"] = v(false)
	objs[devPath(hci0, mouse)][ifaceDevice]["Connected"] = v(true)
	newFakeBlueZ(t, bus, objs)
	h.wait(t, "back", func(st State) bool { return st.Available && dev(st, mouse).Connected })
	quiet()
	if got := log.take(); len(got) != 0 {
		t.Errorf("resync: %+v", got)
	}
}

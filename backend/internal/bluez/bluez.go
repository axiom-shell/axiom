// Package bluez is Bluetooth for the shell, over BlueZ on the system bus:
// the default adapter and its devices, kept current from BlueZ's object
// manager signals (nothing polls), and what the shell does with them:
// power, discovery, connect, disconnect, pair and forget; and the
// pairing agent BlueZ asks for PINs, passkeys and confirmations
// (agent.go).
//
// Every call runs on the service's own bus connection, so BlueZ's
// per-client state is the daemon's: a discovery session started here is
// ended only by StopDiscovery from here, never another app's.
package bluez

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"maps"
	"reflect"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
)

const errPrefix = "org.bluez.Error."

// Options configure the service.
type Options struct {
	// SystemBus connects to the system bus (a new connection each call)
	SystemBus func(ctx context.Context) (*dbus.Conn, error)
	// OnChange is told of every new state
	OnChange func(State)
	// OnAgentRequest shows a pairing agent's request (a display again as
	// it changes); it returns false when nobody can answer (no shell),
	// which BlueZ hears as rejected. OnAgentDone hides one BlueZ, the
	// user or the pairing's end ended.
	OnAgentRequest func(AgentRequest) bool
	OnAgentDone    func(id string)
	// OnEvent is told of devices connecting or disconnecting (events.go)
	OnEvent func(Event)
	// Rfkill is the rfkill class folder read for an adapter's block when
	// it's off (default /sys/class/rfkill)
	Rfkill string
	// RfkillDev opens the rfkill control device for writing, where Unblock
	// writes (default /dev/rfkill)
	RfkillDev func() (io.WriteCloser, error)
	// Now is the clock the discoverable countdown starts from (default
	// time.Now)
	Now func() time.Time
	// Retry is how long to wait before connecting to the bus again
	// (default 10 s); Settle how long signals are gathered into one
	// state (default 50 ms); Join how long apart connects (or
	// disconnects) may be and still be one Event (default 1 s)
	Retry, Settle, Join time.Duration
	Log                 *slog.Logger
}

// Service follows BlueZ; Run runs it.
type Service struct {
	o Options

	// pushMu keeps states handed to OnChange in the order built
	pushMu sync.Mutex
	events *events

	mu      sync.Mutex
	conn    *dbus.Conn // while connected and BlueZ runs
	objects dbus.ManagedObjects
	// order is when each device turned up (a counter), seq the next
	order map[dbus.ObjectPath]uint64
	seq   uint64
	// ops are the calls in flight, by device address
	ops   map[string]string
	state State
	// owner is BlueZ's unique name, as NameOwnerChanged last said
	owner string
	// wantDiscovery: the shell asked for a scan (started again when BlueZ
	// comes back); discovering: this connection's session runs
	wantDiscovery, discovering bool
	// discoveryMu makes one Start/StopDiscovery at a time, each for the
	// scan wanted last (never held while taking it from under mu)
	discoveryMu sync.Mutex
	kick        chan struct{}

	// agentWant: the pairing agent should be registered (SetAgent);
	// agentOn: it is, on conn
	agentWant, agentOn bool
	agentKick          chan struct{}
	// agentMu guards the agent's requests, by id (never held while
	// taking mu)
	agentMu  sync.Mutex
	agents   map[string]*pendingAgent
	agentSeq int
}

// New returns a service; Run runs it.
func New(o Options) *Service {
	if o.Log == nil {
		o.Log = slog.New(slog.DiscardHandler)
	}
	if o.Retry == 0 {
		o.Retry = 10 * time.Second
	}
	if o.Settle == 0 {
		o.Settle = 50 * time.Millisecond
	}
	if o.Rfkill == "" {
		o.Rfkill = "/sys/class/rfkill"
	}
	if o.Join == 0 {
		o.Join = time.Second
	}
	if o.RfkillDev == nil {
		o.RfkillDev = openRfkill
	}
	if o.Now == nil {
		o.Now = time.Now
	}
	s := &Service{
		o: o, state: State{Devices: []Device{}},
		order: map[dbus.ObjectPath]uint64{}, ops: map[string]string{},
		kick: make(chan struct{}, 1), agentKick: make(chan struct{}, 1),
		agents: map[string]*pendingAgent{},
	}
	s.events = newEvents(o.Join, s.State, o.OnEvent)
	return s
}

// State is the current state.
func (s *Service) State() State {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.state
}

// Run follows BlueZ until ctx ends, connecting to the bus again whenever
// the connection drops.
func (s *Service) Run(ctx context.Context) error {
	for {
		err := s.runOnce(ctx)
		if ctx.Err() != nil {
			return nil
		}
		s.o.Log.Warn("bluetooth: the system bus is out of reach: retrying", "in", s.o.Retry, "err", err)
		select {
		case <-ctx.Done():
			return nil
		case <-time.After(s.o.Retry):
		}
	}
}

func (s *Service) runOnce(ctx context.Context) error {
	conn, err := s.o.SystemBus(ctx)
	if err != nil {
		return err
	}
	defer conn.Close()
	// Exported before it's registered (sync), so BlueZ finds it there
	unexport, err := conn.Export(agentPath, dbus.Interface{Name: ifaceAgent, Methods: s.agentMethods()})
	if err != nil {
		return err
	}
	defer unexport()
	// Every signal of BlueZ's in one subscription, so they're read in the
	// order sent: a property change of a device just added comes after
	// its InterfacesAdded
	matches := []dbus.Match{dbus.NameOwnerChanged(busName), {Sender: busName}}
	subs := make([]*dbus.Subscription, 0, len(matches))
	signals := make(chan *dbus.Message, 64)
	stop := make(chan struct{})
	var wg sync.WaitGroup
	defer func() {
		close(stop)
		for _, sub := range subs {
			sub.Close()
		}
		wg.Wait()
	}()
	for _, m := range matches {
		sub, err := conn.Subscribe(ctx, m)
		if err != nil {
			return err
		}
		subs = append(subs, sub)
		wg.Add(1)
		go func() {
			defer wg.Done()
			for msg := range sub.C {
				select {
				case signals <- msg:
				case <-stop:
				}
			}
		}()
	}
	defer s.disconnected()
	// Asking starts BlueZ when it's activatable and not running yet
	s.sync(ctx, conn)
	var settle <-chan time.Time
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-conn.Done():
			return conn.Err()
		case <-s.kick:
			// After the signals sent before the call's reply
			if settle == nil {
				settle = time.After(s.o.Settle)
			}
		case <-settle:
			settle = nil
			s.rebuild(true)
		case <-s.agentKick:
			s.applyAgent(ctx, conn)
		case m := <-signals:
			s.pairedSignal(m)
			if s.signal(ctx, conn, m) && settle == nil {
				settle = time.After(s.o.Settle)
			}
		}
	}
}

// sync reads every object again (a start, BlueZ restarting, the bus
// coming back), and starts the scan the shell wants and registers the
// agent, which BlueZ forgot with the old connection or its own restart.
func (s *Service) sync(ctx context.Context, conn *dbus.Conn) {
	objs, err := conn.GetManagedObjects(ctx, busName, rootPath)
	if err != nil {
		if axerr.KindOf(err) != axerr.Unavailable {
			s.o.Log.Warn("bluetooth: reading BlueZ's objects", "err", err)
		}
		s.disconnected()
		return
	}
	owner, _ := conn.NameOwner(ctx, busName)
	s.mu.Lock()
	s.conn, s.objects, s.owner = conn, objs, owner
	s.order, s.seq = map[dbus.ObjectPath]uint64{}, 0
	paths := slices.Sorted(maps.Keys(objs))
	for _, p := range paths {
		s.seen(p)
	}
	s.discovering = false
	s.agentOn = false
	s.mu.Unlock()
	// Asked of the BlueZ that went away
	s.endAgents(dbus.NewError(errCanceled, "BlueZ restarted"))
	s.rebuild(false)
	s.applyAgent(ctx, conn)
	if err := s.applyDiscovery(ctx); err != nil && axerr.KindOf(err) != axerr.Unavailable {
		s.o.Log.Debug("bluetooth: starting the scan again", "err", err)
	}
}

// seen gives a device just known its place in the order (s.mu held).
func (s *Service) seen(p dbus.ObjectPath) {
	if _, ok := s.order[p]; !ok {
		s.order[p] = s.seq
		s.seq++
	}
}

// disconnected: BlueZ or the bus went away.
func (s *Service) disconnected() {
	s.mu.Lock()
	s.conn, s.objects, s.owner = nil, nil, ""
	s.order = map[dbus.ObjectPath]uint64{}
	s.discovering = false
	s.agentOn = false
	s.mu.Unlock()
	s.endAgents(dbus.NewError(errCanceled, "BlueZ went away"))
	s.rebuild(false)
}

// signal applies one of BlueZ's signals and reports whether the state
// may have changed.
func (s *Service) signal(ctx context.Context, conn *dbus.Conn, m *dbus.Message) bool {
	if m.Interface == dbus.BusInterface && m.Member == "NameOwnerChanged" {
		var name, old, owner string
		if m.Store(&name, &old, &owner) != nil || name != busName {
			return false
		}
		// Both matches let the signal through, so it can come twice, the
		// copies interleaved with the next one's: the owner told again, or
		// an owner going that isn't the one known any more, is stale (a
		// new owner is always taken: one signal of a pair may be lost)
		s.mu.Lock()
		stale := owner == s.owner || owner == "" && old != s.owner
		if !stale {
			s.owner = owner
		}
		s.mu.Unlock()
		switch {
		case stale:
		case owner == "":
			s.disconnected()
		default:
			s.sync(ctx, conn)
		}
		return false
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.objects == nil {
		return false
	}
	switch {
	case m.Path == rootPath && m.Member == "InterfacesAdded":
		path, ifaces, err := dbus.InterfacesAdded(m)
		if err != nil {
			return false
		}
		if s.objects[path] == nil {
			s.objects[path] = dbus.Interfaces{}
		}
		maps.Copy(s.objects[path], ifaces)
		s.seen(path)
	case m.Path == rootPath && m.Member == "InterfacesRemoved":
		path, ifaces, err := dbus.InterfacesRemoved(m)
		if err != nil || s.objects[path] == nil {
			return false
		}
		for _, i := range ifaces {
			delete(s.objects[path], i)
		}
		if len(s.objects[path]) == 0 {
			delete(s.objects, path)
			delete(s.order, path)
		}
	case m.Member == "PropertiesChanged":
		iface, changed, invalidated, err := dbus.PropertiesChanged(m)
		p := s.objects[m.Path][iface]
		if err != nil || p == nil {
			return false
		}
		// A copy: a state already handed out may share the old map
		p = maps.Clone(p)
		maps.Copy(p, changed)
		for _, k := range invalidated {
			delete(p, k)
		}
		s.objects[m.Path][iface] = p
	default:
		return false
	}
	return true
}

// rebuild builds the state from the objects and the calls in flight,
// and hands it on when it changed. live: BlueZ's signals (or a call)
// moved it, so its connects and disconnects are events; else BlueZ was
// read afresh (a sync, BlueZ gone), which is none.
func (s *Service) rebuild(live bool) {
	s.pushMu.Lock()
	defer s.pushMu.Unlock()
	s.mu.Lock()
	prev := s.state
	next := build(s.objects, s.order, s.ops, s.o.Rfkill)
	discoverableUntil(prev, next, live, s.o.Now())
	same := reflect.DeepEqual(prev, next)
	s.state = next
	s.mu.Unlock()
	if live {
		s.events.changed(prev, next)
	} else {
		s.events.reset()
	}
	if !same && s.o.OnChange != nil {
		s.o.OnChange(next)
	}
}

// discoverableUntil sets when the adapter stops being discoverable: kept
// from the last state while it stays so, started when a live change
// turned it on (or changed its timeout), unknown (0) when it was already
// on at a sync, as BlueZ doesn't say when its timer started.
func discoverableUntil(prev, next State, live bool, now time.Time) {
	a := next.Adapter
	if a == nil || !a.Discoverable || a.DiscoverableTimeout == 0 {
		return
	}
	if p := prev.Adapter; p != nil && p.Address == a.Address && p.Discoverable && p.DiscoverableTimeout == a.DiscoverableTimeout {
		a.DiscoverableUntil = p.DiscoverableUntil
		return
	}
	if live {
		a.DiscoverableUntil = now.Add(time.Duration(a.DiscoverableTimeout) * time.Second).UnixMilli()
	}
}

// adapter is the connection and the default adapter's path.
func (s *Service) adapter() (*dbus.Conn, dbus.ObjectPath, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.conn == nil {
		return nil, "", axerr.New(axerr.Unavailable, "BlueZ isn't running")
	}
	ap := defaultAdapter(s.objects)
	if ap == "" {
		return nil, "", axerr.New(axerr.Unavailable, "no Bluetooth adapter")
	}
	return s.conn, ap, nil
}

// device finds a device of the default adapter by its address.
func (s *Service) device(address string) (*dbus.Conn, dbus.ObjectPath, props, error) {
	conn, ap, err := s.adapter()
	if err != nil {
		return nil, "", nil, err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	for p, i := range s.objects {
		d, ok := i[ifaceDevice]
		if ok && props(d).str("Adapter") == string(ap) && strings.EqualFold(props(d).str("Address"), address) {
			return conn, p, props(d), nil
		}
	}
	return nil, "", nil, axerr.New(axerr.NotFound, "no device %s", address)
}

// begin marks a call in flight on a device and shows it at once; false
// when another is running on it.
func (s *Service) begin(address, op string) bool {
	s.mu.Lock()
	if _, busy := s.ops[address]; busy {
		s.mu.Unlock()
		return false
	}
	s.ops[address] = op
	s.mu.Unlock()
	s.rebuild(true)
	return true
}

// step changes the call in flight on a device (a pair moving on to
// connect).
func (s *Service) step(address, op string) {
	s.mu.Lock()
	s.ops[address] = op
	s.mu.Unlock()
	s.rebuild(true)
}

// end ends a call in flight. The state is rebuilt in the run loop once
// settled, so the signals sent before the call's reply are in it: a
// connect never flashes disconnected before its Connected arrives.
func (s *Service) end(address string) {
	s.mu.Lock()
	delete(s.ops, address)
	s.mu.Unlock()
	select {
	case s.kick <- struct{}{}:
	default:
	}
}

// SetPowered turns the default adapter on or off.
func (s *Service) SetPowered(ctx context.Context, on bool) error {
	conn, ap, err := s.adapter()
	if err != nil {
		return err
	}
	return mapError(conn.SetProperty(ctx, busName, ap, ifaceAdapter, "Powered", dbus.MakeVariant(on)))
}

// Discovery starts or stops this connection's scan on the default
// adapter. BlueZ keeps one session per client: stopping ends only ours,
// and the adapter keeps scanning while another app's runs.
func (s *Service) Discovery(ctx context.Context, on bool) error {
	s.mu.Lock()
	s.wantDiscovery = on
	s.mu.Unlock()
	return s.applyDiscovery(ctx)
}

// applyDiscovery starts or stops the scan as last wanted. One runs at a
// time and reads the wish once it runs, so an off sent while an on waits
// for BlueZ stops the scan that on started.
func (s *Service) applyDiscovery(ctx context.Context) error {
	s.discoveryMu.Lock()
	defer s.discoveryMu.Unlock()
	s.mu.Lock()
	on, running := s.wantDiscovery, s.discovering
	s.mu.Unlock()
	if on == running {
		return nil
	}
	conn, ap, err := s.adapter()
	if err != nil {
		if !on {
			// The adapter went, and its scan with it
			s.mu.Lock()
			s.discovering = false
			s.mu.Unlock()
			return nil
		}
		return err
	}
	member := "StopDiscovery"
	if on {
		member = "StartDiscovery"
	}
	_, err = conn.Call(ctx, busName, ap, ifaceAdapter, member, "")
	switch dbus.ErrorName(err) {
	case errPrefix + "InProgress":
		// Ours already runs
		err = nil
	case errPrefix + "NotReady":
		// Off: BlueZ ends every session as it powers off
		if !on {
			err = nil
		}
	}
	if err == nil || !on {
		s.mu.Lock()
		s.discovering = on
		s.mu.Unlock()
	}
	return mapError(err)
}

// Connect connects a device (paired, or one BlueZ can reach without).
func (s *Service) Connect(ctx context.Context, address string) error {
	conn, p, d, err := s.device(address)
	if err != nil {
		return err
	}
	if d.bool("Connected") {
		return nil
	}
	if !s.begin(d.str("Address"), opConnecting) {
		return axerr.New(axerr.Busy, "%s is busy", address)
	}
	defer s.end(d.str("Address"))
	return connect(ctx, conn, p)
}

func connect(ctx context.Context, conn *dbus.Conn, p dbus.ObjectPath) error {
	_, err := conn.Call(ctx, busName, p, ifaceDevice, "Connect", "")
	if dbus.ErrorName(err) == errPrefix+"AlreadyConnected" {
		return nil
	}
	return mapError(err)
}

// Disconnect disconnects a device.
func (s *Service) Disconnect(ctx context.Context, address string) error {
	conn, p, d, err := s.device(address)
	if err != nil {
		return err
	}
	if !d.bool("Connected") {
		return nil
	}
	if !s.begin(d.str("Address"), opDisconnecting) {
		return axerr.New(axerr.Busy, "%s is busy", address)
	}
	defer s.end(d.str("Address"))
	_, err = conn.Call(ctx, busName, p, ifaceDevice, "Disconnect", "")
	if dbus.ErrorName(err) == errPrefix+"NotConnected" {
		return nil
	}
	return mapError(err)
}

// Pair trusts a device (so it may reconnect by itself), pairs it, then
// connects it.
func (s *Service) Pair(ctx context.Context, address string) error {
	conn, p, d, err := s.device(address)
	if err != nil {
		return err
	}
	addr := d.str("Address")
	if !s.begin(addr, opPairing) {
		return axerr.New(axerr.Busy, "%s is busy", address)
	}
	defer s.end(addr)
	if err := conn.SetProperty(ctx, busName, p, ifaceDevice, "Trusted", dbus.MakeVariant(true)); err != nil {
		return mapError(err)
	}
	if !d.bool("Paired") {
		_, err := conn.Call(ctx, busName, p, ifaceDevice, "Pair", "")
		// A code shown for it is done with, paired or not
		s.endDisplays(p)
		if err != nil && dbus.ErrorName(err) != errPrefix+"AlreadyExists" {
			return mapError(err)
		}
	}
	s.step(addr, opConnecting)
	return connect(ctx, conn, p)
}

// CancelPair cancels a pair running on a device.
func (s *Service) CancelPair(ctx context.Context, address string) error {
	conn, p, _, err := s.device(address)
	if err != nil {
		return err
	}
	_, err = conn.Call(ctx, busName, p, ifaceDevice, "CancelPairing", "")
	s.endDisplays(p)
	if dbus.ErrorName(err) == errPrefix+"DoesNotExist" {
		// Nothing was pairing
		return nil
	}
	return mapError(err)
}

// Forget removes a device: unpaired, and gone from the list until a scan
// finds it again.
func (s *Service) Forget(ctx context.Context, address string) error {
	conn, p, _, err := s.device(address)
	if err != nil {
		return err
	}
	_, ap, err := s.adapter()
	if err != nil {
		return err
	}
	_, err = conn.Call(ctx, busName, ap, ifaceAdapter, "RemoveDevice", "o", p)
	return mapError(err)
}

// discoverableFor is the timeout set before making the adapter
// discoverable when BlueZ's is 0 (forever): BlueZ's own default
const discoverableFor = uint32(180)

// SetDiscoverable makes the default adapter visible to devices scanning
// (or hides it). BlueZ hides it again after its DiscoverableTimeout; one
// of 0 means never, so it's set to 3 minutes first (BlueZ keeps it for
// the adapter): a phone found it by then, and the computer isn't left
// visible to everyone nearby.
func (s *Service) SetDiscoverable(ctx context.Context, on bool) error {
	conn, ap, err := s.adapter()
	if err != nil {
		return err
	}
	if on {
		s.mu.Lock()
		timeout := props(s.objects[ap][ifaceAdapter]).uint32("DiscoverableTimeout")
		s.mu.Unlock()
		if timeout == 0 {
			if err := conn.SetProperty(ctx, busName, ap, ifaceAdapter, "DiscoverableTimeout", dbus.MakeVariant(discoverableFor)); err != nil {
				return mapError(err)
			}
		}
	}
	return mapError(conn.SetProperty(ctx, busName, ap, ifaceAdapter, "Discoverable", dbus.MakeVariant(on)))
}

// SetAlias renames a device (its Alias, what the shell shows); "" goes
// back to the name the device gives itself.
func (s *Service) SetAlias(ctx context.Context, address, name string) error {
	return s.setDevice(ctx, address, "Alias", strings.TrimSpace(name))
}

// SetTrusted trusts a device (it may connect by itself, unasked) or not.
func (s *Service) SetTrusted(ctx context.Context, address string, on bool) error {
	return s.setDevice(ctx, address, "Trusted", on)
}

// SetBlocked blocks a device (BlueZ disconnects it and refuses its
// connections) or lets it in again.
func (s *Service) SetBlocked(ctx context.Context, address string, on bool) error {
	return s.setDevice(ctx, address, "Blocked", on)
}

func (s *Service) setDevice(ctx context.Context, address, key string, value any) error {
	conn, p, _, err := s.device(address)
	if err != nil {
		return err
	}
	return mapError(conn.SetProperty(ctx, busName, p, ifaceDevice, key, dbus.MakeVariant(value)))
}

// mapError gives a BlueZ error the kind the shell tells apart, with
// BlueZ's message.
func mapError(err error) error {
	if err == nil {
		return nil
	}
	name := dbus.ErrorName(err)
	var de *dbus.Error
	if !strings.HasPrefix(name, errPrefix) || !errors.As(err, &de) {
		// The bus, not BlueZ: its kind already
		return err
	}
	msg := de.Message
	if msg == "" {
		msg = strings.TrimPrefix(name, errPrefix)
	}
	kind := axerr.Failed
	switch strings.TrimPrefix(name, errPrefix) {
	case "InProgress", "Busy":
		kind = axerr.Busy
	case "NotReady":
		kind = axerr.Unavailable
	case "NotAuthorized", "NotPermitted":
		kind = axerr.NotAuthorized
	case "AuthenticationCanceled", "AuthenticationRejected", "Blocked":
		kind = axerr.Refused
	case "DoesNotExist":
		kind = axerr.NotFound
	case "InvalidArguments", "NotSupported":
		kind = axerr.BadRequest
	}
	return axerr.New(kind, "%s", msg)
}

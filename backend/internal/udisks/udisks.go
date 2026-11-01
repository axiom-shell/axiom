// Package udisks is removable drives for the shell, over UDisks2 on the
// system bus: the USB sticks, SD cards and optical discs plugged in, with
// their volumes, kept current from UDisks2's object manager signals
// (nothing polls); mounting, unmounting, unlocking and locking LUKS
// volumes, and ejecting a drive; and an event when a drive is plugged in
// or pulled out, which the shell notifies of.
package udisks

import (
	"context"
	"errors"
	"log/slog"
	"maps"
	"reflect"
	"strings"
	"sync"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
)

// UDisks2's names
const (
	busName  = "org.freedesktop.UDisks2"
	rootPath = dbus.ObjectPath("/org/freedesktop/UDisks2")

	errPrefix         = "org.freedesktop.UDisks2.Error."
	errDeviceBusy     = errPrefix + "DeviceBusy"
	errAlreadyMounted = errPrefix + "AlreadyMounted"
	errNotMounted     = errPrefix + "NotMounted"
)

// Event is a drive plugged in ("added", with the drive) or pulled out
// ("removed", Drive null).
type Event struct {
	Kind    string `json:"kind"`
	DriveID string `json:"driveId"`
	Drive   *Drive `json:"drive"`
}

// Options configure the service.
type Options struct {
	// SystemBus connects to the system bus (a new connection each call)
	SystemBus func(ctx context.Context) (*dbus.Conn, error)
	// IncludeLoop shows loop devices backed by a file as drives
	// (AXIOM_DRIVES_INCLUDE_LOOP=1: the dev fixtures)
	IncludeLoop bool
	// OnChange is told of every new state
	OnChange func(State)
	// OnEvent is told of drives plugged in and pulled out. It mustn't
	// block.
	OnEvent func(Event)
	// Retry is how long to wait before connecting to the bus again
	// (default 10 s); Settle how long a drive plugged in waits for its
	// volumes before it's announced anyway (default 500 ms)
	Retry, Settle time.Duration
	Log           *slog.Logger
}

// Service follows UDisks2's drives; Run runs it.
type Service struct {
	o Options

	mu      sync.Mutex
	conn    *dbus.Conn // while connected and UDisks2 runs
	objects dbus.ManagedObjects
	state   State
	// known are the drives in the last state; pending those plugged in
	// and not announced yet, with when to announce them anyway
	known   map[string]bool
	pending map[string]time.Time
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
		o.Settle = 500 * time.Millisecond
	}
	return &Service{o: o, state: State{Drives: []Drive{}}, known: map[string]bool{}, pending: map[string]time.Time{}}
}

// State is the current state.
func (s *Service) State() State {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.state
}

// Run follows UDisks2 until ctx ends, connecting to the bus again
// whenever the connection drops.
func (s *Service) Run(ctx context.Context) error {
	for {
		err := s.runOnce(ctx)
		if ctx.Err() != nil {
			return nil
		}
		s.o.Log.Warn("drives: the system bus is out of reach: retrying", "in", s.o.Retry, "err", err)
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
	// Every signal of UDisks2's in one subscription, so they're read in
	// the order sent: a property change of an object just added comes
	// after its InterfacesAdded
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
	// Asking starts UDisks2 when it's activatable and not running yet
	s.sync(ctx, conn)
	var due <-chan time.Time
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-conn.Done():
			return conn.Err()
		case <-due:
		case m := <-signals:
			if !s.signal(ctx, conn, m) {
				continue
			}
		}
		due = s.announce()
	}
}

// sync reads every object again: what's there now is no news, so nothing
// is announced (a login, UDisks2 restarting, the bus coming back).
func (s *Service) sync(ctx context.Context, conn *dbus.Conn) {
	objs, err := conn.GetManagedObjects(ctx, busName, rootPath)
	if err != nil {
		if axerr.KindOf(err) != axerr.Unavailable {
			s.o.Log.Warn("drives: reading UDisks2's objects", "err", err)
		}
		s.disconnected()
		return
	}
	s.mu.Lock()
	s.conn, s.objects = conn, objs
	s.pending = map[string]time.Time{}
	s.mu.Unlock()
	s.rebuild(false)
}

// disconnected: UDisks2 or the bus went away.
func (s *Service) disconnected() {
	s.mu.Lock()
	s.conn, s.objects = nil, nil
	s.known, s.pending = map[string]bool{}, map[string]time.Time{}
	changed := s.state.Available || len(s.state.Drives) > 0
	s.state = State{Drives: []Drive{}}
	s.mu.Unlock()
	if changed && s.o.OnChange != nil {
		s.o.OnChange(s.State())
	}
}

// signal applies one of UDisks2's signals and reports whether the state
// may have changed.
func (s *Service) signal(ctx context.Context, conn *dbus.Conn, m *dbus.Message) bool {
	if m.Interface == dbus.BusInterface && m.Member == "NameOwnerChanged" {
		var name, old, owner string
		if m.Store(&name, &old, &owner) != nil || name != busName {
			return false
		}
		if owner == "" {
			s.disconnected()
		} else {
			s.sync(ctx, conn)
		}
		return false
	}
	s.mu.Lock()
	if s.objects == nil {
		s.mu.Unlock()
		return false
	}
	switch {
	case m.Path == rootPath && m.Member == "InterfacesAdded":
		path, ifaces, err := dbus.InterfacesAdded(m)
		if err != nil {
			break
		}
		if s.objects[path] == nil {
			s.objects[path] = dbus.Interfaces{}
		}
		maps.Copy(s.objects[path], ifaces)
	case m.Path == rootPath && m.Member == "InterfacesRemoved":
		path, ifaces, err := dbus.InterfacesRemoved(m)
		if err != nil || s.objects[path] == nil {
			break
		}
		for _, i := range ifaces {
			delete(s.objects[path], i)
		}
		if len(s.objects[path]) == 0 {
			delete(s.objects, path)
		}
	case m.Member == "PropertiesChanged":
		iface, changed, invalidated, err := dbus.PropertiesChanged(m)
		p := s.objects[m.Path][iface]
		if err != nil || p == nil {
			break
		}
		// A copy: a state already handed out may share the old map
		p = maps.Clone(p)
		maps.Copy(p, changed)
		for _, k := range invalidated {
			delete(p, k)
		}
		s.objects[m.Path][iface] = p
	default:
		s.mu.Unlock()
		return false
	}
	s.mu.Unlock()
	s.rebuild(true)
	return true
}

// rebuild builds the state from the objects. A drive that appeared with
// news (a signal, not a sync) waits to be announced; one gone that was
// announced is announced removed.
func (s *Service) rebuild(news bool) {
	var events []Event
	s.mu.Lock()
	next := State{Available: true, Drives: build(s.objects, s.o.IncludeLoop)}
	seen := map[string]bool{}
	for _, d := range next.Drives {
		seen[d.ID] = true
		if news && !s.known[d.ID] {
			s.pending[d.ID] = time.Now().Add(s.o.Settle)
		}
	}
	for id := range s.known {
		if seen[id] {
			continue
		}
		if _, waiting := s.pending[id]; waiting {
			delete(s.pending, id)
		} else if news {
			events = append(events, Event{Kind: "removed", DriveID: id})
		}
	}
	s.known = seen
	same := s.state.Available && reflect.DeepEqual(s.state.Drives, next.Drives)
	s.state = next
	s.mu.Unlock()
	if !same && s.o.OnChange != nil {
		s.o.OnChange(next)
	}
	s.emit(events)
}

// announce announces the drives waiting whose volumes are known or whose
// wait is over, and returns when to look again (nil: none waiting).
func (s *Service) announce() <-chan time.Time {
	var events []Event
	now := time.Now()
	var next time.Time
	s.mu.Lock()
	for _, d := range s.state.Drives {
		at, ok := s.pending[d.ID]
		if !ok {
			continue
		}
		if len(d.Volumes) > 0 || !now.Before(at) {
			drive := d
			events = append(events, Event{Kind: "added", DriveID: d.ID, Drive: &drive})
			delete(s.pending, d.ID)
		} else if next.IsZero() || at.Before(next) {
			next = at
		}
	}
	s.mu.Unlock()
	s.emit(events)
	if next.IsZero() {
		return nil
	}
	return time.After(next.Sub(now))
}

func (s *Service) emit(events []Event) {
	for _, e := range events {
		if s.o.OnEvent != nil {
			s.o.OnEvent(e)
		}
	}
}

// Mount mounts the volume id names (an unlocked LUKS volume's cleartext)
// and returns where. UDisks2 picks the place and options; it may ask the
// shell's polkit agent first.
func (s *Service) Mount(ctx context.Context, id string) (string, error) {
	conn, v, err := s.volume(id)
	if err != nil {
		return "", err
	}
	if v.Encrypted && !v.Unlocked {
		return "", axerr.New(axerr.BadRequest, "%s is locked", v.Device)
	}
	if !v.Mountable {
		return "", axerr.New(axerr.BadRequest, "%s has no filesystem to mount", v.Device)
	}
	if len(v.MountPoints) > 0 {
		return v.MountPoints[0], nil
	}
	m, err := conn.Call(ctx, busName, fsTarget(v), ifaceFS, "Mount", "a{sv}", map[string]dbus.Variant{})
	if dbus.ErrorName(err) == errAlreadyMounted {
		if _, v, err := s.volume(id); err == nil && len(v.MountPoints) > 0 {
			return v.MountPoints[0], nil
		}
		return "", nil
	}
	if err != nil {
		return "", mapError(err, "")
	}
	var at string
	return at, m.Store(&at)
}

// Unmount unmounts the volume id names (an unlocked LUKS volume's
// cleartext); one not mounted is left as it is.
func (s *Service) Unmount(ctx context.Context, id string) error {
	conn, v, err := s.volume(id)
	if err != nil {
		return err
	}
	return unmount(ctx, conn, v)
}

func unmount(ctx context.Context, conn *dbus.Conn, v Volume) error {
	if len(v.MountPoints) == 0 {
		return nil
	}
	_, err := conn.Call(ctx, busName, fsTarget(v), ifaceFS, "Unmount", "a{sv}", map[string]dbus.Variant{})
	if dbus.ErrorName(err) == errNotMounted {
		return nil
	}
	return mapError(err, "")
}

// fsTarget is the block holding a volume's filesystem.
func fsTarget(v Volume) dbus.ObjectPath {
	if v.Unlocked {
		return dbus.ObjectPath(v.CleartextID)
	}
	return dbus.ObjectPath(v.ID)
}

// Unlock opens the LUKS volume id names with passphrase and returns its
// cleartext's id. The passphrase goes only to UDisks2: it is never
// logged, and never in an error.
func (s *Service) Unlock(ctx context.Context, id, passphrase string) (string, error) {
	conn, v, err := s.volume(id)
	if err != nil {
		return "", err
	}
	if !v.Encrypted {
		return "", axerr.New(axerr.BadRequest, "%s isn't encrypted", v.Device)
	}
	if v.Unlocked {
		return v.CleartextID, nil
	}
	m, err := conn.Call(ctx, busName, dbus.ObjectPath(v.ID), ifaceEncrypted, "Unlock", "sa{sv}", passphrase, map[string]dbus.Variant{})
	if err != nil {
		return "", mapError(err, passphrase)
	}
	var ct dbus.ObjectPath
	if err := m.Store(&ct); err != nil {
		return "", err
	}
	// Answered once the state shows it, so a mount right after finds the
	// cleartext (its signals may still be on their way)
	s.await(ctx, func() bool {
		_, v, err := s.volume(string(ct))
		return err == nil && v.ID == id
	})
	return string(ct), nil
}

// await waits until done holds, for at most 2 s.
func (s *Service) await(ctx context.Context, done func() bool) {
	tick := time.NewTicker(20 * time.Millisecond)
	defer tick.Stop()
	limit := time.After(2 * time.Second)
	for !done() {
		select {
		case <-ctx.Done():
			return
		case <-limit:
			return
		case <-tick.C:
		}
	}
}

// Lock closes the LUKS volume id names, unmounting it first.
func (s *Service) Lock(ctx context.Context, id string) error {
	conn, v, err := s.volume(id)
	if err != nil {
		return err
	}
	if !v.Encrypted {
		return axerr.New(axerr.BadRequest, "%s isn't encrypted", v.Device)
	}
	return lock(ctx, conn, v)
}

func lock(ctx context.Context, conn *dbus.Conn, v Volume) error {
	if !v.Unlocked {
		return nil
	}
	if err := unmount(ctx, conn, v); err != nil {
		return err
	}
	_, err := conn.Call(ctx, busName, dbus.ObjectPath(v.ID), ifaceEncrypted, "Lock", "a{sv}", map[string]dbus.Variant{})
	if dbus.ErrorName(err) == errPrefix+"NotUnlocked" {
		return nil
	}
	return mapError(err, "")
}

// Eject makes the drive id names safe to pull out: it unmounts every
// volume, locks the unlocked ones, then ejects the media (optical, or a
// card in a reader), else powers the drive off where it can be, else
// leaves it unmounted. A loop device is deleted.
func (s *Service) Eject(ctx context.Context, id string) error {
	s.mu.Lock()
	conn := s.conn
	var drive *Drive
	for _, d := range s.state.Drives {
		if d.ID == id {
			drive = &d
			break
		}
	}
	s.mu.Unlock()
	if conn == nil {
		return axerr.New(axerr.Unavailable, "UDisks2 isn't running")
	}
	if drive == nil {
		return axerr.New(axerr.NotFound, "no drive %s", id)
	}
	for _, v := range drive.Volumes {
		// lock unmounts the cleartext first
		step := unmount
		if v.Unlocked {
			step = lock
		}
		if err := step(ctx, conn, v); err != nil {
			return err
		}
	}
	none := map[string]dbus.Variant{}
	var err error
	switch {
	case drive.loop:
		_, err = conn.Call(ctx, busName, dbus.ObjectPath(id), ifaceLoop, "Delete", "a{sv}", none)
	case drive.Optical || drive.CanEject && drive.mediaRemovable:
		_, err = conn.Call(ctx, busName, dbus.ObjectPath(id), ifaceDrive, "Eject", "a{sv}", none)
	case drive.CanPowerOff:
		_, err = conn.Call(ctx, busName, dbus.ObjectPath(id), ifaceDrive, "PowerOff", "a{sv}", none)
	}
	return mapError(err, "")
}

// volume finds a volume the state shows, by its id or, unlocked, its
// cleartext's: nothing else (an internal disk) is the shell's to mount.
func (s *Service) volume(id string) (*dbus.Conn, Volume, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.conn == nil {
		return nil, Volume{}, axerr.New(axerr.Unavailable, "UDisks2 isn't running")
	}
	for _, d := range s.state.Drives {
		for _, v := range d.Volumes {
			if v.ID == id || v.Unlocked && v.CleartextID == id {
				return s.conn, v, nil
			}
		}
	}
	return nil, Volume{}, axerr.New(axerr.NotFound, "no volume %s", id)
}

// mapError gives a UDisks2 error the kind the shell tells apart, with
// UDisks2's message (passphrase, when given, never in it).
func mapError(err error, passphrase string) error {
	if err == nil {
		return nil
	}
	name := dbus.ErrorName(err)
	var de *dbus.Error
	if name == "" || !errors.As(err, &de) || axerr.KindOf(err) == axerr.Unavailable {
		// The bus, not UDisks2: unavailable already
		return err
	}
	msg := de.Message
	if passphrase != "" {
		msg = strings.ReplaceAll(msg, passphrase, "…")
	}
	if msg == "" {
		msg = name
	}
	lower := strings.ToLower(msg)
	kind := axerr.Failed
	switch {
	case name == errDeviceBusy || strings.Contains(lower, "target is busy") || strings.Contains(lower, "device is busy"):
		kind = axerr.Busy
	case strings.HasPrefix(name, errPrefix+"NotAuthorized") || name == dbus.ErrAccessDenied:
		kind = axerr.NotAuthorized
	case passphrase != "" && wrongPassphrase(lower):
		kind = axerr.WrongPassphrase
	}
	return axerr.New(kind, "%s", msg)
}

// wrongPassphrase: an unlock's failure says the key didn't fit (libblockdev
// and cryptsetup word it several ways).
func wrongPassphrase(msg string) bool {
	for _, s := range []string{"passphrase", "operation not permitted", "no key available", "bad password", "wrong password"} {
		if strings.Contains(msg, s) {
			return true
		}
	}
	return false
}

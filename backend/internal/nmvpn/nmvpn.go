// Package nmvpn is NetworkManager's VPN connections for the shell, over
// the system bus: the WireGuard and plugin VPN (OpenVPN, …) profiles with
// their state, address and last failure, kept current from NetworkManager's
// signals (nothing polls); bringing one up or down; and a secret agent,
// so a VPN asking for its password at connect time asks the shell, which
// shows a field in the VPN's row.
package nmvpn

import (
	"context"
	"log/slog"
	"maps"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
)

// NetworkManager's names
const (
	busName        = "org.freedesktop.NetworkManager"
	managerPath    = dbus.ObjectPath("/org/freedesktop/NetworkManager")
	settingsPath   = dbus.ObjectPath("/org/freedesktop/NetworkManager/Settings")
	agentMgrPath   = dbus.ObjectPath("/org/freedesktop/NetworkManager/AgentManager")
	agentPath      = dbus.ObjectPath("/org/freedesktop/NetworkManager/SecretAgent")
	ifaceManager   = "org.freedesktop.NetworkManager"
	ifaceSettings  = "org.freedesktop.NetworkManager.Settings"
	ifaceConn      = "org.freedesktop.NetworkManager.Settings.Connection"
	ifaceActive    = "org.freedesktop.NetworkManager.Connection.Active"
	ifaceVPNConn   = "org.freedesktop.NetworkManager.VPN.Connection"
	ifaceIP4Config = "org.freedesktop.NetworkManager.IP4Config"
	ifaceAgentMgr  = "org.freedesktop.NetworkManager.AgentManager"
	ifaceAgent     = "org.freedesktop.NetworkManager.SecretAgent"

	// What the agent registers as
	agentID = "org.axiom.shell"

	errNoSecrets     = "org.freedesktop.NetworkManager.SecretAgent.NoSecrets"
	errUserCanceled  = "org.freedesktop.NetworkManager.SecretAgent.UserCanceled"
	errAgentCanceled = "org.freedesktop.NetworkManager.SecretAgent.AgentCanceled"
)

// NMActiveConnectionState
const (
	activeActivating   = 1
	activeActivated    = 2
	activeDeactivating = 3
	activeDeactivated  = 4
)

// GetSecrets' flag: NetworkManager allows asking the user
const allowInteraction = 0x1

// Where VPN plugins describe themselves (a .name file each)
var defaultPluginDirs = []string{"/usr/lib/NetworkManager/VPN", "/etc/NetworkManager/VPN"}

// State is what the shell shows (VpnManager). Lists are never null.
type State struct {
	// Available: NetworkManager runs
	Available   bool         `json:"available"`
	Connections []Connection `json:"connections"`
}

// Connection is one VPN profile.
type Connection struct {
	UUID string `json:"uuid"`
	Name string `json:"name"`
	// Kind is "wireguard", or the VPN plugin's short name ("openvpn",
	// "openconnect", …)
	Kind string `json:"kind"`
	// Plugin: the plugin it needs is installed (always for WireGuard)
	Plugin      bool `json:"plugin"`
	Autoconnect bool `json:"autoconnect"`
	// State is "off", "connecting", "on" or "disconnecting"
	State string `json:"state"`
	// Device is its interface while up ("" for a plugin VPN NetworkManager
	// doesn't name one for); IPv4 its first address
	Device string `json:"device"`
	IPv4   string `json:"ipv4"`
	// Error is why it last failed or dropped, "" if it didn't: no-secrets,
	// login-failed, timeout, service-failed, plugin-missing, failed
	Error string `json:"error"`
}

// SecretRequest is NetworkManager asking for a VPN's secrets: the shell
// shows a field for each of Fields and answers with Answer.
type SecretRequest struct {
	ID   string `json:"id"`
	UUID string `json:"uuid"`
	Name string `json:"name"`
	Kind string `json:"kind"`
	// User is the profile's user name, to show with the field ("" none)
	User string `json:"user"`
	// Message is what the VPN said to say, if anything
	Message string `json:"message"`
	// Fields are the secrets' keys ("password", "cert-pass", "private-key",
	// …), each a password field
	Fields []string `json:"fields"`
}

// Options configure the service.
type Options struct {
	// SystemBus connects to the system bus (a new connection each call)
	SystemBus func(ctx context.Context) (*dbus.Conn, error)
	// PluginDirs are where VPN plugins' .name files are looked for
	// (default: NetworkManager's)
	PluginDirs []string
	// OnChange is told of every new state
	OnChange func(State)
	// OnSecret shows a secret request; it returns false when nobody can
	// answer (no shell), which NetworkManager hears as no secrets. It
	// mustn't block.
	OnSecret func(SecretRequest) bool
	// OnSecretDone hides a request NetworkManager or the user ended
	OnSecretDone func(id string)
	// Run runs a command (nmcli, to import a VPN), returning its exit
	// code and what it said on stderr
	Run func(ctx context.Context, argv []string) (code int, stderr string, err error)
	// Retry is how long to wait before connecting to the bus again
	// (default 10 s); Settle how long signals are gathered into one
	// reload (default 50 ms)
	Retry, Settle time.Duration
	Log           *slog.Logger
}

// Service follows NetworkManager's VPNs; Run runs it.
type Service struct {
	o Options

	mu    sync.Mutex
	conn  *dbus.Conn // while connected and NetworkManager runs
	state State
	// The last reload's profiles by settings path (cached until updated or
	// removed), and active connection path → profile uuid
	profiles map[dbus.ObjectPath]profile
	active   map[dbus.ObjectPath]string
	// errors are the last failure of each uuid until it's tried again
	errors map[string]string
	// pending are the secret requests waiting for the shell, by id
	pending map[string]*pendingSecret
	next    int

	kick chan struct{}
}

type profile struct {
	uuid, name, kind, service, user string
	autoconnect                     bool
	vpn                             bool
}

type pendingSecret struct {
	path    dbus.ObjectPath
	setting string
	fields  []string
	reply   func([]any, error)
}

// New returns a service; Run runs it.
func New(o Options) *Service {
	if o.Log == nil {
		o.Log = slog.New(slog.DiscardHandler)
	}
	if o.PluginDirs == nil {
		o.PluginDirs = defaultPluginDirs
	}
	if o.Retry == 0 {
		o.Retry = 10 * time.Second
	}
	if o.Settle == 0 {
		o.Settle = 50 * time.Millisecond
	}
	return &Service{
		o:        o,
		state:    State{Connections: []Connection{}},
		profiles: map[dbus.ObjectPath]profile{},
		active:   map[dbus.ObjectPath]string{},
		errors:   map[string]string{},
		pending:  map[string]*pendingSecret{},
		kick:     make(chan struct{}, 1),
	}
}

// State is the current state.
func (s *Service) State() State {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.state
}

// Run follows NetworkManager until ctx ends, connecting to the bus again
// whenever the connection drops.
func (s *Service) Run(ctx context.Context) error {
	for {
		err := s.runOnce(ctx)
		if ctx.Err() != nil {
			return nil
		}
		s.o.Log.Warn("vpn: the system bus is out of reach: retrying", "in", s.o.Retry, "err", err)
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
	unexport, err := conn.Export(agentPath, dbus.Interface{Name: ifaceAgent, Methods: s.agentMethods()})
	if err != nil {
		return err
	}
	defer unexport()
	matches := []dbus.Match{
		dbus.NameOwnerChanged(busName),
		dbus.PropertiesChangedMatch(busName, managerPath, ifaceManager),
		{Sender: busName, Path: settingsPath, Interface: ifaceSettings},
		{Sender: busName, Interface: ifaceConn, Member: "Updated"},
		{Sender: busName, Interface: ifaceActive, Member: "StateChanged"},
		{Sender: busName, Interface: ifaceVPNConn, Member: "VpnStateChanged"},
	}
	subs := make([]*dbus.Subscription, 0, len(matches))
	signals := make(chan *dbus.Message, 64)
	stop := make(chan struct{})
	var wg sync.WaitGroup
	// Closing the subscriptions ends their forwarders
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
	if owner, _ := conn.NameOwner(ctx, busName); owner != "" {
		s.connected(ctx, conn)
	}
	var settle <-chan time.Time
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-conn.Done():
			return conn.Err()
		case <-s.kick:
			if settle == nil {
				settle = time.After(s.o.Settle)
			}
		case <-settle:
			settle = nil
			s.reload(ctx, conn)
		case m := <-signals:
			if s.signal(ctx, conn, m) && settle == nil {
				settle = time.After(s.o.Settle)
			}
		}
	}
}

// signal reads one of NetworkManager's signals and reports whether the
// state needs reading again.
func (s *Service) signal(ctx context.Context, conn *dbus.Conn, m *dbus.Message) bool {
	switch {
	case m.Interface == dbus.BusInterface && m.Member == "NameOwnerChanged":
		var name, old, owner string
		if m.Store(&name, &old, &owner) != nil || name != busName {
			return false
		}
		if owner == "" {
			s.disconnected()
			return false
		}
		s.connected(ctx, conn)
		return false
	case m.Interface == ifaceActive && m.Member == "StateChanged", m.Interface == ifaceVPNConn && m.Member == "VpnStateChanged":
		var state, reason uint32
		if m.Store(&state, &reason) != nil {
			return true
		}
		s.mu.Lock()
		if uuid, ok := s.active[m.Path]; ok {
			switch {
			case m.Interface == ifaceActive && state == activeActivating:
				delete(s.errors, uuid)
			case failed(m.Interface, state):
				// Both signals come for a VPN: the more telling reason stays
				if e := reasonError(reason); e != "" && (e != "failed" || s.errors[uuid] == "") {
					s.errors[uuid] = e
				}
			}
		}
		s.mu.Unlock()
		return true
	case m.Interface == ifaceConn && m.Member == "Updated":
		s.mu.Lock()
		delete(s.profiles, m.Path)
		s.mu.Unlock()
		return true
	case m.Interface == ifaceSettings && m.Member == "ConnectionRemoved":
		var path dbus.ObjectPath
		if m.Store(&path) == nil {
			s.mu.Lock()
			delete(s.profiles, path)
			s.mu.Unlock()
		}
		return true
	}
	return true
}

// failed: a state signal says the connection went down. VpnStateChanged's
// states are NMVpnConnectionState (6 failed, 7 disconnected).
func failed(iface string, state uint32) bool {
	if iface == ifaceVPNConn {
		return state == 6 || state == 7
	}
	return state == activeDeactivated
}

// reasonError names why a connection went down (NMActiveConnectionStateReason,
// which shares its numbers with NMVpnConnectionStateReason), "" when it
// was asked to or no reason is known.
func reasonError(reason uint32) string {
	switch reason {
	case 0, 1, 2, 11: // unknown, none, user disconnected, connection removed
		return ""
	case 6, 7: // connect timeout, service start timeout
		return "timeout"
	case 8: // service start failed
		return "service-failed"
	case 9:
		return "no-secrets"
	case 10:
		return "login-failed"
	}
	return "failed"
}

// connected: NetworkManager runs, register the agent and read the state.
func (s *Service) connected(ctx context.Context, conn *dbus.Conn) {
	s.mu.Lock()
	s.conn = conn
	s.mu.Unlock()
	if _, err := conn.Call(ctx, busName, agentMgrPath, ifaceAgentMgr, "RegisterWithCapabilities", "su", agentID, uint32(0)); err != nil {
		s.o.Log.Warn("vpn: registering as NetworkManager's secret agent", "err", err)
	}
	s.reload(ctx, conn)
}

// disconnected: NetworkManager or the bus went away.
func (s *Service) disconnected() {
	s.mu.Lock()
	s.conn = nil
	s.profiles = map[dbus.ObjectPath]profile{}
	s.active = map[dbus.ObjectPath]string{}
	pending := s.pending
	s.pending = map[string]*pendingSecret{}
	changed := s.state.Available || len(s.state.Connections) > 0
	s.state = State{Connections: []Connection{}}
	s.mu.Unlock()
	for id, p := range pending {
		p.reply(nil, dbus.NewError(errAgentCanceled, "NetworkManager went away"))
		s.secretDone(id)
	}
	if changed {
		s.changed()
	}
}

func (s *Service) changed() {
	if s.o.OnChange != nil {
		s.o.OnChange(s.State())
	}
}

func (s *Service) secretDone(id string) {
	if s.o.OnSecretDone != nil {
		s.o.OnSecretDone(id)
	}
}

// reload reads the profiles (those not cached) and the active connections.
func (s *Service) reload(ctx context.Context, conn *dbus.Conn) {
	m, err := conn.Call(ctx, busName, settingsPath, ifaceSettings, "ListConnections", "")
	var paths []dbus.ObjectPath
	if err == nil {
		err = m.Store(&paths)
	}
	if err != nil {
		s.o.Log.Warn("vpn: listing NetworkManager's connections", "err", err)
		return
	}
	s.mu.Lock()
	cached := maps.Clone(s.profiles)
	s.mu.Unlock()
	profiles := map[dbus.ObjectPath]profile{}
	for _, p := range paths {
		if pr, ok := cached[p]; ok {
			profiles[p] = pr
			continue
		}
		m, err := conn.Call(ctx, busName, p, ifaceConn, "GetSettings", "")
		if err != nil {
			// Removed meanwhile, or not ours to read
			continue
		}
		var settings any
		if m.Store(&settings) == nil {
			profiles[p] = readProfile(settings)
		}
	}

	type activeConn struct {
		uuid, device, ipv4 string
		state              uint32
	}
	var actives []activeConn
	activePaths := map[dbus.ObjectPath]string{}
	if v, err := conn.GetProperty(ctx, busName, managerPath, ifaceManager, "ActiveConnections"); err == nil {
		list, _ := v.Value.([]dbus.ObjectPath)
		for _, ap := range list {
			props, err := conn.GetAll(ctx, busName, ap, ifaceActive)
			if err != nil {
				continue
			}
			kind, _ := props["Type"].Value.(string)
			if kind != "vpn" && kind != "wireguard" {
				continue
			}
			a := activeConn{}
			a.uuid, _ = props["Uuid"].Value.(string)
			a.state, _ = props["State"].Value.(uint32)
			if ip4, ok := props["Ip4Config"].Value.(dbus.ObjectPath); ok && ip4 != "/" {
				a.ipv4 = firstAddress(ctx, conn, ip4)
			}
			// A WireGuard connection is its own device; a plugin VPN's
			// Devices is the one it runs over, and its tunnel isn't named
			if kind == "wireguard" {
				if devs, ok := props["Devices"].Value.([]dbus.ObjectPath); ok && len(devs) > 0 {
					if v, err := conn.GetProperty(ctx, busName, devs[0], "org.freedesktop.NetworkManager.Device", "Interface"); err == nil {
						a.device, _ = v.Value.(string)
					}
				}
			}
			activePaths[ap] = a.uuid
			actives = append(actives, a)
		}
	}

	plugins := s.plugins()
	s.mu.Lock()
	s.profiles = profiles
	// Keep paths Up recorded that NetworkManager no longer lists: their
	// failure may still be on its way
	for ap, uuid := range s.active {
		if _, ok := activePaths[ap]; !ok {
			activePaths[ap] = uuid
		}
	}
	s.active = activePaths
	out := []Connection{}
	for _, pr := range profiles {
		if pr.kind == "" {
			continue
		}
		c := Connection{UUID: pr.uuid, Name: pr.name, Kind: pr.kind, Autoconnect: pr.autoconnect, State: "off", Plugin: !pr.vpn || plugins[pr.service]}
		for _, a := range actives {
			if a.uuid != pr.uuid {
				continue
			}
			c.State, c.Device, c.IPv4 = stateName(a.state), a.device, a.ipv4
		}
		c.Error = s.errors[pr.uuid]
		if !c.Plugin && c.Error == "" {
			c.Error = "plugin-missing"
		}
		out = append(out, c)
	}
	slices.SortFunc(out, func(a, b Connection) int {
		return strings.Compare(strings.ToLower(a.Name), strings.ToLower(b.Name))
	})
	next := State{Available: true, Connections: out}
	same := s.state.Available && slices.Equal(s.state.Connections, next.Connections)
	s.state = next
	s.mu.Unlock()
	if !same {
		s.changed()
	}
}

func stateName(state uint32) string {
	switch state {
	case activeActivating:
		return "connecting"
	case activeActivated:
		return "on"
	case activeDeactivating:
		return "disconnecting"
	}
	return "off"
}

// firstAddress is an IP4Config's first address ("" none).
func firstAddress(ctx context.Context, conn *dbus.Conn, path dbus.ObjectPath) string {
	v, err := conn.GetProperty(ctx, busName, path, ifaceIP4Config, "AddressData")
	if err != nil {
		return ""
	}
	list, _ := v.Value.([]any)
	for _, entry := range list {
		if d, ok := entry.(map[string]dbus.Variant); ok {
			if a, ok := d["address"].Value.(string); ok {
				return a
			}
		}
	}
	return ""
}

// readProfile reads what's shown of a connection's settings (a{sa{sv}});
// its kind is "" when it's no VPN.
func readProfile(settings any) profile {
	c := section(settings, "connection")
	pr := profile{autoconnect: true}
	pr.uuid, _ = c["uuid"].Value.(string)
	pr.name, _ = c["id"].Value.(string)
	if a, ok := c["autoconnect"].Value.(bool); ok {
		pr.autoconnect = a
	}
	switch c["type"].Value {
	case "wireguard":
		pr.kind = "wireguard"
	case "vpn":
		v := section(settings, "vpn")
		pr.vpn = true
		pr.service, _ = v["service-type"].Value.(string)
		pr.kind = pr.service[strings.LastIndex(pr.service, ".")+1:]
		pr.user, _ = v["user-name"].Value.(string)
		if u := vpnData(settings)["username"]; u != "" {
			pr.user = u
		}
		if pr.kind == "" {
			pr.kind = "vpn"
		}
	}
	return pr
}

// section is one setting of a{sa{sv}} (nil when it's missing).
func section(settings any, name string) map[string]dbus.Variant {
	all, _ := settings.(map[any]any)
	s, _ := all[name].(map[string]dbus.Variant)
	return s
}

// vpnData is the vpn setting's data (a{ss}).
func vpnData(settings any) map[string]string {
	out := map[string]string{}
	data, _ := section(settings, "vpn")["data"].Value.(map[any]any)
	for k, v := range data {
		ks, _ := k.(string)
		vs, _ := v.(string)
		out[ks] = vs
	}
	return out
}

// plugins are the VPN services whose plugin is installed.
func (s *Service) plugins() map[string]bool {
	out := map[string]bool{}
	for _, dir := range s.o.PluginDirs {
		names, _ := filepath.Glob(filepath.Join(dir, "*.name"))
		for _, name := range names {
			data, err := os.ReadFile(name)
			if err != nil {
				continue
			}
			for line := range strings.Lines(string(data)) {
				if k, v, ok := strings.Cut(strings.TrimSpace(line), "="); ok && strings.TrimSpace(k) == "service" {
					out[strings.TrimSpace(v)] = true
				}
			}
		}
	}
	return out
}

// Up connects the VPN uuid names.
func (s *Service) Up(ctx context.Context, uuid string) error {
	conn, err := s.connFor(uuid)
	if err != nil {
		return err
	}
	if c := s.find(uuid); c != nil && !c.Plugin {
		return axerr.New(axerr.Unavailable, "the NetworkManager plugin for %s isn't installed", c.Kind)
	}
	m, err := conn.Call(ctx, busName, settingsPath, ifaceSettings, "GetConnectionByUuid", "s", uuid)
	var path dbus.ObjectPath
	if err == nil {
		err = m.Store(&path)
	}
	if err != nil {
		return axerr.Wrap(axerr.NotFound, err, "no VPN %s", uuid)
	}
	s.mu.Lock()
	delete(s.errors, uuid)
	s.mu.Unlock()
	m, err = conn.Call(ctx, busName, managerPath, ifaceManager, "ActivateConnection", "ooo", path, dbus.ObjectPath("/"), dbus.ObjectPath("/"))
	if err != nil {
		s.mu.Lock()
		s.errors[uuid] = "failed"
		s.mu.Unlock()
		s.kickReload()
		return err
	}
	var active dbus.ObjectPath
	if m.Store(&active) == nil {
		s.mu.Lock()
		s.active[active] = uuid
		s.mu.Unlock()
	}
	s.kickReload()
	return nil
}

// Down disconnects the VPN uuid names.
func (s *Service) Down(ctx context.Context, uuid string) error {
	conn, err := s.connFor(uuid)
	if err != nil {
		return err
	}
	// Every path it was up on: reload keeps those of earlier connections
	// (a failure may still come for them), so one picked alone was often
	// gone and the live one stayed up
	s.mu.Lock()
	var paths []dbus.ObjectPath
	for ap, u := range s.active {
		if u == uuid {
			paths = append(paths, ap)
		}
	}
	s.mu.Unlock()
	var firstErr error
	for _, path := range paths {
		_, err := conn.Call(ctx, busName, managerPath, ifaceManager, "DeactivateConnection", "o", path)
		// Gone already: nothing left to hear from it
		if dbus.ErrorName(err) == "org.freedesktop.NetworkManager.ConnectionNotActive" {
			s.mu.Lock()
			delete(s.active, path)
			s.mu.Unlock()
			continue
		}
		if err != nil && firstErr == nil {
			firstErr = err
		}
	}
	s.kickReload()
	return firstErr
}

// Import adds the VPN in a WireGuard (.conf) or OpenVPN (.ovpn) file
// with nmcli: NetworkManager's import is its plugins' code, which only
// libnm clients run, not a D-Bus call.
func (s *Service) Import(ctx context.Context, path string) error {
	var kind string
	switch strings.ToLower(filepath.Ext(path)) {
	case ".conf":
		kind = "wireguard"
	case ".ovpn":
		kind = "openvpn"
		if !s.plugins()["org.freedesktop.NetworkManager.openvpn"] {
			return axerr.New(axerr.Unavailable, "the NetworkManager plugin for openvpn isn't installed")
		}
	default:
		return axerr.New(axerr.BadRequest, "not a VPN file NetworkManager imports (.conf or .ovpn): %s", filepath.Base(path))
	}
	if !filepath.IsAbs(path) {
		return axerr.New(axerr.BadRequest, "the path isn't absolute")
	}
	if s.o.Run == nil {
		return axerr.New(axerr.Unavailable, "no command runner")
	}
	code, stderr, err := s.o.Run(ctx, []string{"nmcli", "connection", "import", "type", kind, "file", path})
	if err != nil {
		return err
	}
	if code != 0 {
		msg := strings.TrimSpace(stderr)
		if msg == "" {
			msg = "nmcli failed"
		}
		return axerr.New(axerr.Refused, "%s", strings.TrimPrefix(msg, "Error: "))
	}
	s.kickReload()
	return nil
}

func (s *Service) connFor(uuid string) (*dbus.Conn, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.conn == nil {
		return nil, axerr.New(axerr.Unavailable, "NetworkManager isn't running")
	}
	if uuid == "" {
		return nil, axerr.New(axerr.BadRequest, "no VPN named")
	}
	return s.conn, nil
}

func (s *Service) find(uuid string) *Connection {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i := range s.state.Connections {
		if s.state.Connections[i].UUID == uuid {
			c := s.state.Connections[i]
			return &c
		}
	}
	return nil
}

func (s *Service) kickReload() {
	select {
	case s.kick <- struct{}{}:
	default:
	}
}

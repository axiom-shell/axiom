package bluez

import (
	"context"
	"fmt"
	"maps"
	"slices"
	"strconv"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
)

// The pairing agent: BlueZ asks it for a PIN, a passkey, a confirmation
// or an authorization while pairing, and tells it a code to show. It is
// registered on the service's own connection, the one Pair runs on, so
// BlueZ asks it for the pairs the shell starts; RequestDefaultAgent makes
// it the one asked for pairs a device starts too.

const (
	ifaceAgentMgr = "org.bluez.AgentManager1"
	ifaceAgent    = "org.bluez.Agent1"
	agentMgrPath  = dbus.ObjectPath("/org/bluez")
	agentPath     = dbus.ObjectPath("/org/axiom/bluetooth/agent")
	// It shows codes and takes them typed
	agentCapability = "KeyboardDisplay"

	errRejected = errPrefix + "Rejected"
	errCanceled = errPrefix + "Canceled"
)

// What an agent request asks (AgentRequest.Kind)
const (
	// A PIN code to type (legacy pairing): answered with value
	KindPin = "pin"
	// A passkey to type (0–999999): answered with value
	KindPasskey = "passkey"
	// Does the device show Code? Accept or not
	KindConfirm = "confirm"
	// May the device pair (it started it, with nothing to compare)?
	KindAuthorize = "authorize"
	// May a device that isn't trusted use a service (Service, a UUID)?
	KindAuthorizeService = "authorizeService"
	// Code to type on the device (a keyboard): nothing to answer, it ends
	// with the pairing; Entered counts the digits typed
	KindDisplay = "display"
)

// AgentRequest is BlueZ asking the user something while pairing
// (bluetooth.agentRequest). A display request is pushed again, with the
// same ID, as its Entered count changes.
type AgentRequest struct {
	ID     string      `json:"id"`
	Kind   string      `json:"kind"`
	Device AgentDevice `json:"device"`
	// Code is the passkey to confirm or show (six digits), or the PIN to
	// show; "" for the others
	Code string `json:"code"`
	// Entered is how many digits of a shown passkey the keyboard typed,
	// -1 when BlueZ doesn't count them (every kind but a passkey shown)
	Entered int `json:"entered"`
	// Service is the UUID an authorizeService asks for, "" for the others
	Service string `json:"service"`
}

// AgentDevice is the device asking, as the state shows it.
type AgentDevice struct {
	Address string `json:"address"`
	Name    string `json:"name"`
	Icon    string `json:"icon"`
}

type pendingAgent struct {
	req  AgentRequest
	path dbus.ObjectPath
	// reply answers BlueZ; nil for a display, which has nothing to answer
	reply func([]any, error)
}

// SetAgent registers the pairing agent (on) or unregisters it, now and
// whenever BlueZ comes back. Off, another agent (blueman) answers.
func (s *Service) SetAgent(on bool) {
	s.mu.Lock()
	s.agentWant = on
	s.mu.Unlock()
	select {
	case s.agentKick <- struct{}{}:
	default:
	}
}

// applyAgent registers or unregisters the agent as wanted, on the
// connection BlueZ was read through (the run loop's).
func (s *Service) applyAgent(ctx context.Context, conn *dbus.Conn) {
	s.mu.Lock()
	want, on, live := s.agentWant, s.agentOn, s.conn == conn && conn != nil
	s.mu.Unlock()
	if !live || want == on {
		return
	}
	if !want {
		_, err := conn.Call(ctx, busName, agentMgrPath, ifaceAgentMgr, "UnregisterAgent", "o", agentPath)
		if err != nil && dbus.ErrorName(err) != errPrefix+"DoesNotExist" {
			s.o.Log.Warn("bluetooth: unregistering the pairing agent", "err", err)
		}
		s.mu.Lock()
		s.agentOn = false
		s.mu.Unlock()
		s.endAgents(dbus.NewError(errRejected, "the pairing agent was turned off"))
		return
	}
	_, err := conn.Call(ctx, busName, agentMgrPath, ifaceAgentMgr, "RegisterAgent", "os", agentPath, agentCapability)
	if err != nil && dbus.ErrorName(err) != errPrefix+"AlreadyExists" {
		s.o.Log.Warn("bluetooth: registering the pairing agent", "err", err)
		return
	}
	// Asked for the pairs a device starts too; another agent being the
	// default already isn't an error BlueZ gives
	if _, err := conn.Call(ctx, busName, agentMgrPath, ifaceAgentMgr, "RequestDefaultAgent", "o", agentPath); err != nil {
		s.o.Log.Warn("bluetooth: making the pairing agent the default", "err", err)
	}
	s.mu.Lock()
	s.agentOn = true
	s.mu.Unlock()
}

// agentMethods answer BlueZ as org.bluez.Agent1.
func (s *Service) agentMethods() map[string]dbus.Method {
	return map[string]dbus.Method{
		"Release":              {Fn: s.agentRelease},
		"RequestPinCode":       {In: "o", Out: "s", Defer: s.ask(KindPin)},
		"RequestPasskey":       {In: "o", Out: "u", Defer: s.ask(KindPasskey)},
		"RequestConfirmation":  {In: "ou", Defer: s.ask(KindConfirm)},
		"RequestAuthorization": {In: "o", Defer: s.ask(KindAuthorize)},
		"AuthorizeService":     {In: "os", Defer: s.ask(KindAuthorizeService)},
		"DisplayPinCode":       {In: "os", Fn: s.displayPinCode},
		"DisplayPasskey":       {In: "ouq", Fn: s.displayPasskey},
		"Cancel":               {Fn: s.agentCancel},
	}
}

// fromBlueZ: the call comes from BlueZ, the only one that may ask.
func (s *Service) fromBlueZ(call *dbus.Message) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.owner != "" && call.Sender == s.owner
}

var errNotBlueZ = dbus.NewError(errRejected, "only BlueZ asks this agent")

// passkey is a passkey as the six digits a device shows.
func passkey(n uint32) string { return fmt.Sprintf("%06d", n) }

// ask is a request the user answers: its reply waits for the shell.
func (s *Service) ask(kind string) func(context.Context, *dbus.Message, func([]any, error)) {
	return func(_ context.Context, call *dbus.Message, reply func([]any, error)) {
		if !s.fromBlueZ(call) {
			reply(nil, errNotBlueZ)
			return
		}
		var dev dbus.ObjectPath
		var code, service string
		var err error
		switch kind {
		case KindConfirm:
			var n uint32
			err = call.Store(&dev, &n)
			code = passkey(n)
		case KindAuthorizeService:
			err = call.Store(&dev, &service)
		default:
			err = call.Store(&dev)
		}
		if err != nil {
			reply(nil, dbus.NewError(dbus.ErrInvalidArgs, "%v", err))
			return
		}
		device, trusted := s.agentDevice(dev)
		// A trusted device's services need no asking
		if kind == KindAuthorizeService && trusted {
			reply(nil, nil)
			return
		}
		req := AgentRequest{Kind: kind, Device: device, Code: code, Entered: -1, Service: service}
		s.agentMu.Lock()
		s.agentSeq++
		req.ID = strconv.Itoa(s.agentSeq)
		s.agents[req.ID] = &pendingAgent{req: req, path: dev, reply: reply}
		s.agentMu.Unlock()
		if s.o.OnAgentRequest == nil || !s.o.OnAgentRequest(req) {
			s.takeAgent(req.ID)
			reply(nil, dbus.NewError(errRejected, "nobody to ask"))
		}
	}
}

func (s *Service) displayPinCode(_ context.Context, call *dbus.Message) ([]any, error) {
	if !s.fromBlueZ(call) {
		return nil, errNotBlueZ
	}
	var dev dbus.ObjectPath
	var pin string
	if err := call.Store(&dev, &pin); err != nil {
		return nil, dbus.NewError(dbus.ErrInvalidArgs, "%v", err)
	}
	return nil, s.display(dev, pin, -1)
}

func (s *Service) displayPasskey(_ context.Context, call *dbus.Message) ([]any, error) {
	if !s.fromBlueZ(call) {
		return nil, errNotBlueZ
	}
	var dev dbus.ObjectPath
	var n uint32
	var entered uint16
	if err := call.Store(&dev, &n, &entered); err != nil {
		return nil, dbus.NewError(dbus.ErrInvalidArgs, "%v", err)
	}
	return nil, s.display(dev, passkey(n), int(entered))
}

// display shows a code, or updates the one shown for the device (BlueZ
// calls DisplayPasskey again as each digit is typed).
func (s *Service) display(dev dbus.ObjectPath, code string, entered int) error {
	device, _ := s.agentDevice(dev)
	s.agentMu.Lock()
	var p *pendingAgent
	for _, q := range s.agents {
		if q.reply == nil && q.path == dev {
			p = q
		}
	}
	if p == nil {
		s.agentSeq++
		p = &pendingAgent{req: AgentRequest{ID: strconv.Itoa(s.agentSeq), Kind: KindDisplay, Device: device}, path: dev}
		s.agents[p.req.ID] = p
	}
	p.req.Code, p.req.Entered = code, entered
	req := p.req
	s.agentMu.Unlock()
	if s.o.OnAgentRequest == nil || !s.o.OnAgentRequest(req) {
		// Nobody to show it: the user reads it nowhere, and the pairing
		// times out on the device's side
		s.takeAgent(req.ID)
		return dbus.NewError(errRejected, "nobody to show it to")
	}
	return nil
}

func (s *Service) agentCancel(_ context.Context, call *dbus.Message) ([]any, error) {
	if !s.fromBlueZ(call) {
		return nil, errNotBlueZ
	}
	s.endAgents(dbus.NewError(errCanceled, "BlueZ canceled the request"))
	return nil, nil
}

// agentRelease: BlueZ unregistered the agent (it's going away).
func (s *Service) agentRelease(_ context.Context, call *dbus.Message) ([]any, error) {
	if !s.fromBlueZ(call) {
		return nil, errNotBlueZ
	}
	s.mu.Lock()
	s.agentOn = false
	s.mu.Unlock()
	s.endAgents(dbus.NewError(errCanceled, "the agent was released"))
	return nil, nil
}

// agentDevice is the device at path as the state shows it, and whether
// it's trusted; the address is read from the path when BlueZ hasn't told
// of the device.
func (s *Service) agentDevice(p dbus.ObjectPath) (AgentDevice, bool) {
	s.mu.Lock()
	d := props(s.objects[p][ifaceDevice])
	s.mu.Unlock()
	if d == nil {
		_, base, _ := strings.Cut(string(p), "/dev_")
		addr := strings.ReplaceAll(base, "_", ":")
		return AgentDevice{Address: addr, Name: addr}, false
	}
	return AgentDevice{Address: d.str("Address"), Name: d.str("Alias"), Icon: d.str("Icon")}, d.bool("Trusted")
}

func (s *Service) takeAgent(id string) *pendingAgent {
	s.agentMu.Lock()
	defer s.agentMu.Unlock()
	p := s.agents[id]
	delete(s.agents, id)
	return p
}

// endAgents ends every request: those waiting are answered err.
func (s *Service) endAgents(err error) {
	s.agentMu.Lock()
	ended := s.agents
	s.agents = map[string]*pendingAgent{}
	s.agentMu.Unlock()
	for _, id := range slices.Sorted(maps.Keys(ended)) {
		if p := ended[id]; p.reply != nil {
			p.reply(nil, err)
		}
		s.agentDone(id)
	}
}

// endDisplays hides the codes shown for a device: its pairing is over.
func (s *Service) endDisplays(dev dbus.ObjectPath) {
	s.agentMu.Lock()
	var ids []string
	for id, p := range s.agents {
		if p.reply == nil && p.path == dev {
			ids = append(ids, id)
			delete(s.agents, id)
		}
	}
	s.agentMu.Unlock()
	for _, id := range ids {
		s.agentDone(id)
	}
}

// pairedSignal ends the codes shown for a device whose signal says it
// paired (a pair the device started has no call here to end it).
func (s *Service) pairedSignal(m *dbus.Message) {
	if m.Member != "PropertiesChanged" {
		return
	}
	iface, changed, _, err := dbus.PropertiesChanged(m)
	if err == nil && iface == ifaceDevice && props(changed).bool("Paired") {
		s.endDisplays(m.Path)
	}
}

func (s *Service) agentDone(id string) {
	if s.o.OnAgentDone != nil {
		s.o.OnAgentDone(id)
	}
}

// AgentReply answers agent request id: accept or decline, with value the
// PIN or passkey typed. A display's reply only hides it (the shell ends
// its pairing with CancelPair).
func (s *Service) AgentReply(id string, accept bool, value string) error {
	s.agentMu.Lock()
	p := s.agents[id]
	if p == nil {
		s.agentMu.Unlock()
		return axerr.New(axerr.NotFound, "no agent request %s waits", id)
	}
	var out []any
	if accept && p.reply != nil {
		switch p.req.Kind {
		case KindPin:
			// BlueZ takes 1–16 characters
			if value == "" || len(value) > 16 {
				s.agentMu.Unlock()
				return axerr.New(axerr.BadRequest, "a PIN is 1 to 16 characters")
			}
			out = []any{value}
		case KindPasskey:
			n, err := strconv.ParseUint(value, 10, 32)
			if err != nil || n > 999999 {
				s.agentMu.Unlock()
				return axerr.New(axerr.BadRequest, "a passkey is 0 to 999999")
			}
			out = []any{uint32(n)}
		}
	}
	delete(s.agents, id)
	s.agentMu.Unlock()
	defer s.agentDone(id)
	if p.reply == nil {
		return nil
	}
	if !accept {
		p.reply(nil, dbus.NewError(errRejected, "the user declined"))
		return nil
	}
	p.reply(out, nil)
	return nil
}

package nmvpn

import (
	"context"
	"slices"
	"strconv"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
)

// Secret flags (NMSettingSecretFlags): agent-owned and not saved are the
// secrets an agent is asked for; not required ones are never asked
const (
	flagAgentOwned  = 0x1
	flagNotSaved    = 0x2
	flagNotRequired = 0x4
)

// The prefix of a hint that is a message to show, not a secret's key
const messageHint = "x-vpn-message:"

// agentMethods answer NetworkManager as a secret agent: only VPN and
// WireGuard secrets; anything else has none here, so NetworkManager asks
// its other agents.
func (s *Service) agentMethods() map[string]dbus.Method {
	none := func(context.Context, *dbus.Message) ([]any, error) { return nil, nil }
	return map[string]dbus.Method{
		"GetSecrets":       {In: "a{sa{sv}}osasu", Out: "a{sa{sv}}", Defer: s.getSecrets},
		"CancelGetSecrets": {In: "os", Fn: s.cancelGetSecrets},
		// Secrets aren't kept here: what the user types is used once
		"SaveSecrets":   {In: "a{sa{sv}}o", Fn: none},
		"DeleteSecrets": {In: "a{sa{sv}}o", Fn: none},
	}
}

func (s *Service) getSecrets(_ context.Context, call *dbus.Message, reply func([]any, error)) {
	var settings any
	var path dbus.ObjectPath
	var setting string
	var hints []string
	var flags uint32
	if err := call.Store(&settings, &path, &setting, &hints, &flags); err != nil {
		reply(nil, dbus.NewError(dbus.ErrInvalidArgs, "%v", err))
		return
	}
	req, ok := secretRequest(settings, setting, hints)
	if !ok || flags&allowInteraction == 0 {
		reply(nil, dbus.NewError(errNoSecrets, "no secrets to ask for here"))
		return
	}
	s.mu.Lock()
	// NetworkManager asks once per connection and setting at a time: an
	// older request for the same is over
	var replaced []string
	for id, p := range s.pending {
		if p.path == path && p.setting == setting {
			p.reply(nil, dbus.NewError(errAgentCanceled, "asked again"))
			delete(s.pending, id)
			replaced = append(replaced, id)
		}
	}
	s.next++
	req.ID = strconv.Itoa(s.next)
	s.pending[req.ID] = &pendingSecret{path: path, setting: setting, fields: req.Fields, reply: reply}
	s.mu.Unlock()
	for _, id := range replaced {
		s.secretDone(id)
	}
	if s.o.OnSecret == nil || !s.o.OnSecret(req) {
		s.take(req.ID)
		reply(nil, dbus.NewError(errNoSecrets, "nobody to ask"))
	}
}

func (s *Service) cancelGetSecrets(_ context.Context, call *dbus.Message) ([]any, error) {
	var path dbus.ObjectPath
	var setting string
	if err := call.Store(&path, &setting); err != nil {
		return nil, dbus.NewError(dbus.ErrInvalidArgs, "%v", err)
	}
	s.mu.Lock()
	var ids []string
	for id, p := range s.pending {
		if p.path == path && p.setting == setting {
			ids = append(ids, id)
		}
	}
	s.mu.Unlock()
	for _, id := range ids {
		if p := s.take(id); p != nil {
			p.reply(nil, dbus.NewError(errAgentCanceled, "NetworkManager canceled the request"))
			s.secretDone(id)
		}
	}
	return nil, nil
}

func (s *Service) take(id string) *pendingSecret {
	s.mu.Lock()
	defer s.mu.Unlock()
	p := s.pending[id]
	delete(s.pending, id)
	return p
}

// Answer answers secret request id with values (by field key), or, with
// cancel, says the user declined.
func (s *Service) Answer(id string, values map[string]string, cancel bool) error {
	p := s.take(id)
	if p == nil {
		return axerr.New(axerr.NotFound, "no secret request %s waits", id)
	}
	defer s.secretDone(id)
	if cancel {
		p.reply(nil, dbus.NewError(errUserCanceled, "the user canceled"))
		return nil
	}
	answer := map[string]string{}
	for _, f := range p.fields {
		answer[f] = values[f]
	}
	var out map[string]map[string]dbus.Variant
	if p.setting == "vpn" {
		out = map[string]map[string]dbus.Variant{"vpn": {"secrets": dbus.MakeVariant(answer)}}
	} else {
		section := map[string]dbus.Variant{}
		for k, v := range answer {
			section[k] = dbus.MakeVariant(v)
		}
		out = map[string]map[string]dbus.Variant{p.setting: section}
	}
	p.reply([]any{out}, nil)
	return nil
}

// secretRequest is what to ask the user for a connection's setting; ok is
// false when there's nothing this agent asks.
func secretRequest(settings any, setting string, hints []string) (SecretRequest, bool) {
	pr := readProfile(settings)
	req := SecretRequest{UUID: pr.uuid, Name: pr.name, Kind: pr.kind, User: pr.user, Fields: []string{}}
	for _, h := range hints {
		if msg, ok := strings.CutPrefix(h, messageHint); ok {
			req.Message = msg
		} else if h != "" {
			req.Fields = append(req.Fields, h)
		}
	}
	switch setting {
	case "vpn":
		if !pr.vpn {
			return req, false
		}
		if len(req.Fields) == 0 {
			data := vpnData(settings)
			for k, v := range data {
				key, ok := strings.CutSuffix(k, "-flags")
				if !ok {
					continue
				}
				flags, err := strconv.ParseUint(v, 10, 32)
				if err == nil && flags&(flagAgentOwned|flagNotSaved) != 0 && flags&flagNotRequired == 0 {
					req.Fields = append(req.Fields, key)
				}
			}
		}
	case "wireguard":
		if pr.kind != "wireguard" {
			return req, false
		}
		if len(req.Fields) == 0 {
			flags, _ := section(settings, "wireguard")["private-key-flags"].Value.(uint32)
			if flags&(flagAgentOwned|flagNotSaved) != 0 {
				req.Fields = append(req.Fields, "private-key")
			}
		}
	default:
		return req, false
	}
	slices.Sort(req.Fields)
	req.Fields = slices.Compact(req.Fields)
	return req, len(req.Fields) > 0
}

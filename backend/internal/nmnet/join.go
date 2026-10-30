package nmnet

import (
	"context"
	"path/filepath"
	"slices"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
)

// JoinRequest is a Wi-Fi network to join with what the shell's form
// asked for: a hidden one, or one whose security needs more than a
// password (WEP, enterprise). Secrets come over the socket, never argv.
type JoinRequest struct {
	// Device is the Wi-Fi interface ("": the first)
	Device string `json:"device"`
	SSID   string `json:"ssid"`
	Hidden bool   `json:"hidden"`
	// Security is "open", "psk", "wep", "eap", "dynamic-wep" (EAP over
	// WEP) or "leap"
	Security string `json:"security"`
	// Password is the PSK, the WEP key or passphrase, or the EAP or LEAP
	// password
	Password string `json:"password"`
	// Identity is the EAP or LEAP user name; AnonymousIdentity, EAP's
	// outer one ("" for none)
	Identity          string `json:"identity"`
	AnonymousIdentity string `json:"anonymousIdentity"`
	// EAP is "peap" or "ttls"; Phase2 "mschapv2" (the default), "pap",
	// "mschap" or "gtc"
	EAP    string `json:"eap"`
	Phase2 string `json:"phase2"`
	// CACert is the CA certificate's path; empty, SystemCA checks the
	// server against the system's CAs, else the server isn't checked
	CACert   string `json:"caCert"`
	SystemCA bool   `json:"systemCa"`
}

var phase2Methods = []string{"mschapv2", "pap", "mschap", "gtc"}

// wifiSettings is the profile a JoinRequest makes (a{sa{sv}}).
func wifiSettings(r JoinRequest) (map[string]map[string]dbus.Variant, error) {
	if r.SSID == "" || len(r.SSID) > 32 {
		return nil, axerr.New(axerr.BadRequest, "a network name is 1 to 32 bytes")
	}
	wifi := map[string]dbus.Variant{"ssid": dbus.MakeVariant([]byte(r.SSID)), "mode": dbus.MakeVariant("infrastructure")}
	if r.Hidden {
		wifi["hidden"] = dbus.MakeVariant(true)
	}
	out := map[string]map[string]dbus.Variant{
		"connection": {"id": dbus.MakeVariant(r.SSID), "type": dbus.MakeVariant(wifiType)},
		wifiType:     wifi,
	}
	sec := map[string]dbus.Variant{}
	switch r.Security {
	case "open", "":
		return out, nil
	case "psk":
		if !validPSK(r.Password) {
			return nil, axerr.New(axerr.BadRequest, "a WPA password is 8 to 63 characters, or 64 hex digits")
		}
		sec["key-mgmt"] = dbus.MakeVariant("wpa-psk")
		sec["psk"] = dbus.MakeVariant(r.Password)
	case "wep":
		if r.Password == "" {
			return nil, axerr.New(axerr.BadRequest, "no WEP key")
		}
		// 1: a key (5 or 13 characters, 10 or 26 hex digits); 2: a
		// passphrase NetworkManager hashes into one
		keyType := uint32(2)
		if wepKey(r.Password) {
			keyType = 1
		}
		sec["key-mgmt"] = dbus.MakeVariant("none")
		sec["wep-key0"] = dbus.MakeVariant(r.Password)
		sec["wep-key-type"] = dbus.MakeVariant(keyType)
		sec["wep-tx-keyidx"] = dbus.MakeVariant(uint32(0))
	case "leap":
		if r.Identity == "" || r.Password == "" {
			return nil, axerr.New(axerr.BadRequest, "LEAP needs a user name and a password")
		}
		sec["key-mgmt"] = dbus.MakeVariant("ieee8021x")
		sec["auth-alg"] = dbus.MakeVariant("leap")
		sec["leap-username"] = dbus.MakeVariant(r.Identity)
		sec["leap-password"] = dbus.MakeVariant(r.Password)
	case "eap", "dynamic-wep":
		eap, err := eapSettings(r)
		if err != nil {
			return nil, err
		}
		sec["key-mgmt"] = dbus.MakeVariant("wpa-eap")
		if r.Security == "dynamic-wep" {
			sec["key-mgmt"] = dbus.MakeVariant("ieee8021x")
		}
		out[eapSetting] = eap
	default:
		return nil, axerr.New(axerr.BadRequest, "unknown security %q", r.Security)
	}
	out[wifiSecurity] = sec
	wifi["security"] = dbus.MakeVariant(wifiSecurity)
	return out, nil
}

func eapSettings(r JoinRequest) (map[string]dbus.Variant, error) {
	if r.EAP != "peap" && r.EAP != "ttls" {
		return nil, axerr.New(axerr.BadRequest, "unknown EAP method %q (PEAP or TTLS)", r.EAP)
	}
	phase2 := r.Phase2
	if phase2 == "" {
		phase2 = "mschapv2"
	}
	if !slices.Contains(phase2Methods, phase2) {
		return nil, axerr.New(axerr.BadRequest, "unknown inner method %q", phase2)
	}
	if r.Identity == "" {
		return nil, axerr.New(axerr.BadRequest, "no user name")
	}
	eap := map[string]dbus.Variant{
		"eap":         dbus.MakeVariant([]string{r.EAP}),
		"identity":    dbus.MakeVariant(r.Identity),
		"password":    dbus.MakeVariant(r.Password),
		"phase2-auth": dbus.MakeVariant(phase2),
	}
	if r.AnonymousIdentity != "" {
		eap["anonymous-identity"] = dbus.MakeVariant(r.AnonymousIdentity)
	}
	switch {
	case r.CACert != "":
		if !filepath.IsAbs(r.CACert) {
			return nil, axerr.New(axerr.BadRequest, "the CA certificate's path isn't absolute")
		}
		// A path is NetworkManager's file:// scheme, NUL-ended
		eap["ca-cert"] = dbus.MakeVariant(append([]byte("file://"+r.CACert), 0))
	case r.SystemCA:
		eap["system-ca-certs"] = dbus.MakeVariant(true)
	}
	return eap, nil
}

func validPSK(p string) bool {
	if len(p) == 64 {
		return isHex(p)
	}
	return len(p) >= 8 && len(p) <= 63
}

func wepKey(k string) bool {
	switch len(k) {
	case 5, 13:
		return true
	case 10, 26:
		return isHex(k)
	}
	return false
}

func isHex(s string) bool {
	for _, c := range s {
		if !(c >= '0' && c <= '9' || c >= 'a' && c <= 'f' || c >= 'A' && c <= 'F') {
			return false
		}
	}
	return true
}

// Join connects to the network r names. A profile already saved for its
// name is updated with r's settings and activated (a second try with a
// corrected password replaces the first, rather than adding another);
// else a new one is added and activated.
func (s *Service) Join(ctx context.Context, r JoinRequest) error {
	settings, err := wifiSettings(r)
	if err != nil {
		return err
	}
	conn, err := s.dial(ctx)
	if err != nil {
		return err
	}
	defer conn.Close()
	var dev dbus.ObjectPath
	if r.Device != "" {
		dev, err = deviceByIface(ctx, conn, r.Device)
	} else {
		dev, err = firstWifi(ctx, conn)
	}
	if err != nil {
		return err
	}
	for _, p := range wifiProfiles(ctx, conn) {
		if p.SSID != r.SSID {
			continue
		}
		// Its own id and uuid stay
		for k, v := range p.settings["connection"] {
			if k != "type" {
				settings["connection"][k] = v
			}
		}
		if _, err := conn.Call(ctx, busName, p.path, ifaceConn, "Update", "a{sa{sv}}", settings); err != nil {
			return axerr.Wrap(axerr.Refused, err, "NetworkManager refused the settings")
		}
		if _, err := conn.Call(ctx, busName, managerPath, ifaceManager, "ActivateConnection", "ooo", p.path, dev, noObject); err != nil {
			return axerr.Wrap(axerr.Refused, err, "couldn't connect to %s", r.SSID)
		}
		return nil
	}
	if _, err := conn.Call(ctx, busName, managerPath, ifaceManager, "AddAndActivateConnection", "a{sa{sv}}oo", settings, dev, noObject); err != nil {
		return axerr.Wrap(axerr.Refused, err, "couldn't connect to %s", r.SSID)
	}
	return nil
}

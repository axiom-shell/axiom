package dbus

import (
	"fmt"
	"net/url"
	"strings"
)

// The system bus, when $DBUS_SYSTEM_BUS_ADDRESS doesn't name another
const defaultSystemBus = "unix:path=/run/dbus/system_bus_socket"

// SessionAddress is the session bus's address: $DBUS_SESSION_BUS_ADDRESS,
// else the bus systemd's user instance runs ($XDG_RUNTIME_DIR/bus).
func SessionAddress(getenv func(string) string) (string, error) {
	if a := getenv("DBUS_SESSION_BUS_ADDRESS"); a != "" {
		return a, nil
	}
	if rt := getenv("XDG_RUNTIME_DIR"); rt != "" {
		return "unix:path=" + rt + "/bus", nil
	}
	return "", fmt.Errorf("dbus: no session bus: neither $DBUS_SESSION_BUS_ADDRESS nor $XDG_RUNTIME_DIR is set")
}

// SystemAddress is the system bus's address.
func SystemAddress(getenv func(string) string) string {
	if a := getenv("DBUS_SYSTEM_BUS_ADDRESS"); a != "" {
		return a
	}
	return defaultSystemBus
}

// socketPaths are the unix sockets an address names, in its order
// (`;`-separated entries; unix:path= and unix:abstract=, the transports
// a local bus uses). An abstract socket's path starts with "@", as Go's
// net package names them.
func socketPaths(address string) ([]string, error) {
	var out []string
	for _, entry := range strings.Split(address, ";") {
		transport, params, ok := strings.Cut(entry, ":")
		if !ok || transport != "unix" {
			continue
		}
		for _, kv := range strings.Split(params, ",") {
			k, v, _ := strings.Cut(kv, "=")
			v, err := url.PathUnescape(v)
			if err != nil {
				return nil, fmt.Errorf("dbus: address %q: %w", address, err)
			}
			switch k {
			case "path":
				out = append(out, v)
			case "abstract":
				out = append(out, "@"+v)
			}
		}
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("dbus: address %q names no unix socket", address)
	}
	return out, nil
}

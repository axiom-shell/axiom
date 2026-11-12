package session

import (
	"path/filepath"

	"github.com/axiom-shell/axiom/backend/internal/xdg"
)

// ScopeFrom is the session the environment names.
func ScopeFrom(getenv func(string) string) Scope {
	rt := getenv("XDG_RUNTIME_DIR")
	return Scope{WaylandDisplay: xdg.DisplayName(getenv("WAYLAND_DISPLAY")), RuntimeDir: rt,
		Bus: busOrDefault(getenv("DBUS_SESSION_BUS_ADDRESS"), rt), ProcRoot: "/proc"}
}

// busOrDefault: an unset session bus address means the bus in the runtime
// folder (dbus.SessionAddress's fallback).
func busOrDefault(bus, runtimeDir string) string {
	if bus == "" && runtimeDir != "" {
		return "unix:path=" + runtimeDir + "/bus"
	}
	return bus
}

// PortalEnvFrom is the portal config the environment names.
func PortalEnvFrom(getenv func(string) string) PortalEnv {
	rt := getenv("XDG_RUNTIME_DIR")
	return PortalEnv{Config: xdg.ResolveBases(getenv).Config, DataDirs: append(xdg.SearchDirs(getenv), "/usr/share"),
		Alive: func(display string) bool { return DisplayAlive(rt, display) }}
}

// StoreFrom is the state record of the environment's XDG_STATE_HOME.
func StoreFrom(getenv func(string) string, log Logf) Store {
	return Store{Path: filepath.Join(xdg.Resolve(getenv).State, "session.json"), Log: log}
}

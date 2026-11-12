package session

import (
	"path/filepath"

	"github.com/axiom-shell/axiom/backend/internal/xdg"
)

// ScopeFrom is the session the environment names.
func ScopeFrom(getenv func(string) string) Scope {
	return Scope{WaylandDisplay: xdg.DisplayName(getenv("WAYLAND_DISPLAY")), RuntimeDir: getenv("XDG_RUNTIME_DIR"),
		Bus: getenv("DBUS_SESSION_BUS_ADDRESS"), ProcRoot: "/proc"}
}

// PortalEnvFrom is the portal config the environment names.
func PortalEnvFrom(getenv func(string) string) PortalEnv {
	return PortalEnv{Config: xdg.ResolveBases(getenv).Config, DataDirs: append(xdg.SearchDirs(getenv), "/usr/share")}
}

// StoreFrom is the state record of the environment's XDG_STATE_HOME.
func StoreFrom(getenv func(string) string, log Logf) Store {
	return Store{Path: filepath.Join(xdg.Resolve(getenv).State, "session.json"), Log: log}
}

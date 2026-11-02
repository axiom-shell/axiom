package ipc

import (
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
)

// compositorVar names each compositor's instance; Detect trusts them in
// this order
type compositorVar struct{ kind, name string }

var compositorVars = []compositorVar{
	{"hyprland", "HYPRLAND_INSTANCE_SIGNATURE"},
	{"sway", "SWAYSOCK"},
	{"niri", "NIRI_SOCKET"},
}

// procDir is where a pid's comm is read (tests point it elsewhere)
var procDir = "/proc"

// socketPID: the pid in sway's and niri's socket names
// (sway-ipc.<uid>.<pid>.sock, niri.<display>.<pid>.sock)
var socketPID = map[string]*regexp.Regexp{
	"sway": regexp.MustCompile(`sway-ipc\.\d+\.(\d+)\.sock$`),
	"niri": regexp.MustCompile(`\.(\d+)\.sock$`),
}

// Detect is the compositor axiom runs under ("hyprland", "sway", "niri"
// or ""). A variable can outlive its compositor (one exported into the
// systemd user environment reaches the next session's compositor): with
// more than one set, the first whose process still runs wins, else the
// first.
func Detect(getenv func(string) string) string {
	var set []compositorVar
	for _, v := range compositorVars {
		if getenv(v.name) != "" {
			set = append(set, v)
		}
	}
	if len(set) == 0 {
		return ""
	}
	if len(set) > 1 {
		for _, v := range set {
			if running(getenv, v) {
				return v.kind
			}
		}
	}
	return set[0].kind
}

// running: the process v names is that compositor
func running(getenv func(string) string, v compositorVar) bool {
	pid := ""
	if v.kind == "hyprland" {
		// Hyprland's pid is its lock file's first line
		lock, _ := os.ReadFile(filepath.Join(getenv("XDG_RUNTIME_DIR"), "hypr", getenv(v.name), "hyprland.lock"))
		pid, _, _ = strings.Cut(string(lock), "\n")
	} else if m := socketPID[v.kind].FindStringSubmatch(getenv(v.name)); m != nil {
		pid = m[1]
	}
	pid = strings.TrimSpace(pid)
	if pid == "" || strings.Trim(pid, "0123456789") != "" {
		return false
	}
	comm, err := os.ReadFile(filepath.Join(procDir, pid, "comm"))
	return err == nil && strings.ToLower(strings.TrimSpace(string(comm))) == v.kind
}

// StaleVars are the variables set for a compositor other than the one
// Detect picks.
func StaleVars(getenv func(string) string) []string {
	kind := Detect(getenv)
	var stale []string
	for _, v := range compositorVars {
		if v.kind != kind && getenv(v.name) != "" {
			stale = append(stale, v.name)
		}
	}
	return stale
}

// LiveEnv is getenv without StaleVars, so whatever reads it reaches only
// the compositor running.
func LiveEnv(getenv func(string) string) func(string) string {
	stale := StaleVars(getenv)
	return func(name string) string {
		if slices.Contains(stale, name) {
			return ""
		}
		return getenv(name)
	}
}

// WithoutVars is environ (NAME=value entries) without the variables names.
func WithoutVars(environ, names []string) []string {
	return slices.DeleteFunc(slices.Clone(environ), func(kv string) bool {
		name, _, _ := strings.Cut(kv, "=")
		return slices.Contains(names, name)
	})
}

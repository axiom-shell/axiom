package ipc

import (
	"os"
	"path/filepath"
	"slices"
	"testing"
)

// TestDetectPicksTheCompositorRunning: with more than one compositor's
// variable set, the one whose process runs wins (CompositorKind's rule)
func TestDetectPicksTheCompositorRunning(t *testing.T) {
	dir := t.TempDir()
	procDir = filepath.Join(dir, "proc")
	t.Cleanup(func() { procDir = "/proc" })
	comm := func(pid, name string) {
		os.MkdirAll(filepath.Join(procDir, pid), 0o755)
		os.WriteFile(filepath.Join(procDir, pid, "comm"), []byte(name+"\n"), 0o644)
	}
	comm("100", "niri")
	comm("200", "sway")
	comm("300", "Hyprland")
	comm("400", "bash")
	os.MkdirAll(filepath.Join(dir, "hypr", "live"), 0o755)
	os.WriteFile(filepath.Join(dir, "hypr", "live", "hyprland.lock"), []byte("300\nwayland-1\n"), 0o644)
	os.MkdirAll(filepath.Join(dir, "hypr", "gone"), 0o755)
	os.WriteFile(filepath.Join(dir, "hypr", "gone", "hyprland.lock"), []byte("400\nwayland-1\n"), 0o644)
	cases := []struct {
		name  string
		env   map[string]string
		want  string
		stale []string
	}{
		{"none", map[string]string{}, "", nil},
		{"one, unchecked", map[string]string{"NIRI_SOCKET": "/run/niri.wayland-1.999.sock"}, "niri", nil},
		{"a stale Hyprland under niri", map[string]string{"HYPRLAND_INSTANCE_SIGNATURE": "gone", "NIRI_SOCKET": "/run/niri.wayland-1.100.sock"}, "niri", []string{"HYPRLAND_INSTANCE_SIGNATURE"}},
		{"a stale niri under sway", map[string]string{"SWAYSOCK": "/run/sway-ipc.1000.200.sock", "NIRI_SOCKET": "/run/niri.wayland-1.400.sock"}, "sway", []string{"NIRI_SOCKET"}},
		{"Hyprland running", map[string]string{"HYPRLAND_INSTANCE_SIGNATURE": "live", "SWAYSOCK": "/run/sway-ipc.1000.401.sock"}, "hyprland", []string{"SWAYSOCK"}},
		{"none running: the first", map[string]string{"SWAYSOCK": "/run/sway-ipc.1000.400.sock", "NIRI_SOCKET": "/run/niri.wayland-1.401.sock"}, "sway", []string{"NIRI_SOCKET"}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			c.env["XDG_RUNTIME_DIR"] = dir
			getenv := func(name string) string { return c.env[name] }
			if got := Detect(getenv); got != c.want {
				t.Errorf("Detect = %q, want %q", got, c.want)
			}
			if got := StaleVars(getenv); !slices.Equal(got, c.stale) {
				t.Errorf("StaleVars = %v, want %v", got, c.stale)
			}
			live := LiveEnv(getenv)
			for _, name := range c.stale {
				if live(name) != "" {
					t.Errorf("LiveEnv(%s) = %q, want it hidden", name, live(name))
				}
			}
			if live("XDG_RUNTIME_DIR") != dir {
				t.Error("LiveEnv hides other variables")
			}
		})
	}
	if got := WithoutVars([]string{"A=1", "NIRI_SOCKET=x", "B=NIRI_SOCKET"}, []string{"NIRI_SOCKET"}); !slices.Equal(got, []string{"A=1", "B=NIRI_SOCKET"}) {
		t.Errorf("WithoutVars = %v", got)
	}
}

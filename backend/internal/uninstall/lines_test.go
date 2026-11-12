package uninstall

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/compositor/manager"
)

func TestCanonicalLines(t *testing.T) {
	t.Parallel()
	const bin = "/home/u/.local/bin/axiom"
	yes := map[string][]string{
		kindHyprland: {
			`hl.on("hyprland.start", function() hl.exec_cmd("'` + bin + `' run") end) -- axiom`,
			`hl.on("hyprland.start", function() hl.exec_cmd("axiom run") end) -- axiom`,
			`hl.on("hyprland.start", function() hl.exec_cmd("/usr/bin/axiom run") end) -- axiom`,
			`  hl.on("hyprland.start", function() hl.exec_cmd("'/usr/bin/axiom' run") end) -- axiom  `,
			`hl.on("hyprland.start", function() hl.exec_cmd("'/usr/bin/axiom' run") end)`,
			`local ok, axiom = pcall(dofile, "/home/u/.local/state/axiom/hyprland.lua")`,
			`if ok then axiom.setup() end`,
			"if ok then axiom.setup() end\r",
		},
		kindSway: {
			"exec '" + bin + "' run", "exec " + bin + " run", "exec axiom run", "  exec axiom run\r",
			"include /home/u/.local/state/axiom/sway.conf", `include "/home/u/.local/state/axiom/sway.conf"`,
			"include '/home/u/.local/state/axiom/sway.conf'",
		},
		kindNiri: {
			`spawn-sh-at-startup "'` + bin + `' run"`, `spawn-sh-at-startup "axiom run"`, `spawn-sh-at-startup "/usr/bin/axiom run"` + "\r",
			`include "/home/u/.local/state/axiom/niri.kdl"`,
		},
		kindXDPH: {"screencopy:custom_picker_binary = " + bin, "screencopy:custom_picker_binary = '" + bin + "'", "  screencopy:custom_picker_binary = axiom\r"},
		kindXDPW: {"chooser_type = dmenu", "chooser_cmd = '" + bin + "' screenshare-pick --for xdpw", "chooser_cmd = axiom screenshare-pick --for xdpw"},
	}
	for kind, lines := range yes {
		for _, line := range lines {
			if !Canonical(kind, line) {
				t.Errorf("%s: %q isn't canonical", kind, line)
			}
		}
	}
	no := map[string][]string{
		kindHyprland: {
			`hl.on("hyprland.start", function() hl.exec_cmd("'` + bin + `' run --debug") end) -- axiom`,
			`-- hl.on("hyprland.start", function() hl.exec_cmd("'` + bin + `' run") end) -- axiom`,
			`hl.on("hyprland.start", function() hl.exec_cmd("axiom-foo run") end) -- axiom`,
			`hl.on("hyprland.start", function() hl.exec_cmd("'` + bin + `' run") end) -- mine`,
			`hl.exec_cmd("axiom run")`,
			`local ok, axiom = pcall(dofile, "/home/u/other/hyprland.lua")`,
			`if ok then axiom.setup(1) end`,
		},
		kindSway: {
			"exec_always axiom run", "exec axiom run --debug", "# exec axiom run", "exec axiom-foo run", "exec foo axiom run",
			"exec axiom run && true", "exec axiom ipc x", "include /home/u/other.conf", "include /home/u/state/axiom/sway.conf.bak",
			"exec  axiom  run",
		},
		kindNiri: {
			`spawn-at-startup "axiom" "run"`, `spawn-sh-at-startup "axiom run" // mine`, `// spawn-sh-at-startup "axiom run"`,
			`spawn-sh-at-startup "axiom-foo run"`, `include "/home/u/axiom/niri-detached.kdl"`,
		},
		kindXDPH:  {"screencopy:custom_picker_binary = /usr/bin/other", "screencopy:custom_picker_binary = /usr/bin/axiom-foo", "# screencopy:custom_picker_binary = axiom"},
		kindXDPW:  {"chooser_type = simple", "chooser_cmd = wofi", "chooser_cmd = axiom screenshare-pick", "chooser_cmd = axiom screenshare-pick --for xdpw --x"},
		"unknown": {"exec axiom run"},
	}
	for kind, lines := range no {
		for _, line := range lines {
			if Canonical(kind, line) {
				t.Errorf("%s: %q is canonical", kind, line)
			}
		}
	}
}

func TestScanPairsAndCRLF(t *testing.T) {
	t.Parallel()
	text := "a\r\nlocal ok, axiom = pcall(dofile, \"/s/axiom/hyprland.lua\")\r\nif ok then axiom.setup() end\r\nb\r\nif ok then axiom.setup() end\r\n"
	s := scanFile(kindHyprland, "f", []byte(text))
	if len(s.Remove) != 2 || s.Remove[0] != 1 || s.Remove[1] != 2 {
		t.Fatalf("remove %v", s.Remove)
	}
	if string(without([]byte(text), s.Remove)) != "a\r\nb\r\nif ok then axiom.setup() end\r\n" {
		t.Errorf("%q", without([]byte(text), s.Remove))
	}
	if len(s.Manual) != 1 || s.Manual[0].Line != 5 {
		t.Errorf("a lone second line is listed: %+v", s.Manual)
	}
	// xdpw: the pair only
	both := scanFile(kindXDPW, "f", []byte("[screencast]\nchooser_type = dmenu\nchooser_cmd = '/x/axiom' screenshare-pick --for xdpw\n"))
	if len(both.Remove) != 2 {
		t.Errorf("the pair: %v", both.Remove)
	}
	alone := scanFile(kindXDPW, "f", []byte("[screencast]\nchooser_type = dmenu\nmax_fps = 30\nchooser_cmd = '/x/axiom' screenshare-pick --for xdpw\n"))
	if len(alone.Remove) != 0 || len(alone.Manual) != 1 || alone.Manual[0].Line != 4 {
		t.Errorf("separated: %v %+v", alone.Remove, alone.Manual)
	}
	// a file without a final newline keeps that
	if got := string(without([]byte("a\nexec axiom run"), []int{1})); got != "a\n" {
		t.Errorf("%q", got)
	}
	// nothing to remove: the file isn't written
	dir := t.TempDir()
	path := filepath.Join(dir, "config")
	os.WriteFile(path, []byte("set $mod Mod4\n"), 0o640)
	info, _ := os.Stat(path)
	removed, _, err := removeLines(kindSway, path)
	after, _ := os.Stat(path)
	if err != nil || len(removed) != 0 || !after.ModTime().Equal(info.ModTime()) {
		t.Errorf("%v %v", removed, err)
	}
}

var releaseGolden = map[string]string{kindHyprland: "release-hyprland.lua", kindSway: "release-sway.conf", kindNiri: "release-niri.kdl"}

// The text release writes when nothing was set aside has no line that
// starts axiom (golden per compositor, `go test -update` rewrites it)
func TestReleaseFallbackHasNoStartLine(t *testing.T) {
	t.Parallel()
	env := map[string]string{"HOME": "/nonexistent/home", "XDG_CONFIG_HOME": "/nonexistent/home/.config", "XDG_STATE_HOME": "/nonexistent/home/.local/state"}
	getenv := func(k string) string { return env[k] }
	for kind, name := range releaseGolden {
		w, ok := manager.NewOffline(getenv, kind, "/home/u/.local/bin/axiom")
		if !ok {
			t.Fatal(kind)
		}
		text := w.Takeover().Fallback
		for i, line := range strings.Split(text, "\n") {
			if startsAxiom.MatchString(line) || namesModule.MatchString(line) {
				t.Errorf("%s line %d starts axiom: %q", kind, i+1, line)
			}
		}
		// The pieces the released config has otherwise stay
		if !strings.Contains(text, "user") {
			t.Errorf("%s: no user/ in the fallback", kind)
		}
		path := filepath.Join("testdata", name+".golden")
		if *update {
			os.MkdirAll("testdata", 0o755)
			if err := os.WriteFile(path, []byte(text), 0o644); err != nil {
				t.Fatal(err)
			}
			continue
		}
		want, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("%v (go test -run Release -update writes it)", err)
		}
		if text != string(want) {
			t.Errorf("%s differs from %s:\n%s", kind, path, text)
		}
	}
}

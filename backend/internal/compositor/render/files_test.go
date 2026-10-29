package render

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

// The files the port writes, read by the tools that will read them: every
// Hyprland file parses (luac), the managed file with everything on is a
// config Hyprland itself takes (Hyprland --verify-config), and the niri
// files are configs niri takes (niri validate), each where it's installed
// (not in CI). An option a compositor refuses fails here, not in a user's
// session.
func TestCompositorsReadTheFiles(t *testing.T) {
	t.Parallel()
	tab := repoTables(t)
	dir := t.TempDir()
	check := func(t *testing.T, tool string, args ...string) {
		t.Helper()
		if _, err := exec.LookPath(tool); err != nil {
			t.Skipf("no %s", tool)
		}
		cmd := exec.Command(tool, args...)
		cmd.Dir = dir
		done := make(chan struct{})
		var out []byte
		var err error
		go func() { out, err = cmd.CombinedOutput(); close(done) }()
		select {
		case <-done:
		case <-time.After(testkit.Bound(30 * time.Second)):
			cmd.Process.Kill()
			t.Fatalf("%s took too long", tool)
		}
		text := string(out)
		if err != nil || (tool == "Hyprland" && !strings.Contains(text, "config ok")) {
			var kept []string
			for _, l := range strings.Split(text, "\n") {
				if !strings.Contains(l, "DEBUG") {
					kept = append(kept, l)
				}
			}
			t.Errorf("%s %s: %v\n%s", tool, strings.Join(args, " "), err, strings.Join(kept, "\n"))
		}
	}
	files := map[string]string{
		"HyprConfigLua.moduleLua": ".lua", "HyprConfigLua.managedLua": ".lua", "HyprConfigLua.releasedLua": ".lua",
		"HyprConfigLua.emptyModuleLua": ".lua", "NiriConf.moduleText": ".kdl", "NiriConf.managedText": ".kdl",
		"NiriConf.releasedText": ".kdl", "NiriConf.emptyModuleText": ".kdl",
	}
	n := 0
	for _, c := range frozenCases(t) {
		ext, ok := files[c.Op]
		if !ok {
			continue
		}
		n++
		path := filepath.Join(dir, strings.NewReplacer("/", "_", ".", "_").Replace(c.Name)+ext)
		text := ops[c.Op](tab, c.Args).(string)
		if ext == ".kdl" {
			// Includes name the user's files, checked when niri loads them
			// (as the writer validates)
			var own []string
			for _, l := range strings.Split(text, "\n") {
				if !strings.HasPrefix(strings.TrimSpace(l), "include ") {
					own = append(own, l)
				}
			}
			text = strings.Join(own, "\n")
		}
		if err := os.WriteFile(path, []byte(text), 0o644); err != nil {
			t.Fatal(err)
		}
		t.Run(c.Name, func(t *testing.T) {
			switch {
			case ext == ".kdl":
				check(t, "niri", "validate", "-c", path)
			case strings.Contains(c.Name, "everything"):
				check(t, "luac", "-p", path)
				check(t, "Hyprland", "--verify-config", "-c", path)
			default:
				check(t, "luac", "-p", path)
			}
		})
	}
	if n == 0 {
		t.Fatal("no files among the frozen cases")
	}
}

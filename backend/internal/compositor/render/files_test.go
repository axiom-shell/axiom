package render

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/testkit"
	"github.com/axiom-shell/axiom/backend/internal/windowrules"
)

// The files the port writes, read by the tools that will read them: every
// Hyprland file parses (luac), the managed file with everything on is a
// config Hyprland itself takes (Hyprland --verify-config), and the niri and
// sway files are configs those take (niri validate, sway --validate), each
// where it's installed (not in CI). An option a compositor refuses fails here, not in a user's
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
		if tool == "sway" {
			// validate still starts a headless backend and opens a Wayland
			// socket: give it a scratch runtime dir (a socket path stays
			// under 108 bytes) and nothing of the host's session
			run, err := os.MkdirTemp("", "sv")
			if err != nil || len(run) > 80 {
				t.Skipf("no short runtime dir (%v)", err)
			}
			defer os.RemoveAll(run)
			cmd.Env = []string{"PATH=" + os.Getenv("PATH"), "HOME=" + dir, "XDG_RUNTIME_DIR=" + run,
				"WLR_BACKENDS=headless", "WLR_RENDERER=pixman", "WLR_LIBINPUT_NO_DEVICES=1"}
		}
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
		"SwayConf.moduleText": ".conf", "SwayConf.managedText": ".conf", "SwayConf.releasedText": ".conf",
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
		if ext == ".kdl" || ext == ".conf" {
			// Includes name the user's files, checked when the compositor
			// loads them (as the writer validates)
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
			case ext == ".conf":
				check(t, "sway", "--validate", "-c", path)
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
	t.Run("rules", func(t *testing.T) {
		rules := validatorRules(t)
		write := func(name, text string) string {
			path := filepath.Join(dir, name)
			if err := os.WriteFile(path, []byte(text), 0o644); err != nil {
				t.Fatal(err)
			}
			return path
		}
		hyprLines, _ := HyprRuleLines(RuleSet{Rules: rules, Supports: hyprSupports})
		hypr := write("rules.lua", strings.Join(hyprLines, "\n")+"\n")
		check(t, "luac", "-p", hypr)
		check(t, "Hyprland", "--verify-config", "-c", hypr)
		nodes, _ := NiriRuleNodes(RuleSet{Rules: rules, Supports: niriSupports})
		check(t, "niri", "validate", "-c", write("rules.kdl", KdlSerialize(nodes, 0)+"\n"))
		swayLines, _ := SwayRuleLines(RuleSet{Rules: rules, Supports: swayFXSupport}, false)
		check(t, "sway", "--validate", "-c", write("rules.conf", strings.Join(swayLines, "\n")+"\n"))
	})
}

// validatorRules are one rule per fixture pattern and negation, plus one
// with every effect and the kinds that matter
func validatorRules(t *testing.T) []windowrules.Rule {
	t.Helper()
	var fixture struct {
		Patterns []struct {
			Op, Value, Regex string
		}
		Negations []struct{ Values []string }
	}
	data, err := os.ReadFile(filepath.Join(testkit.RepoRoot(), "tests/fixtures/windowrules/regex.json"))
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(data, &fixture); err != nil {
		t.Fatal(err)
	}
	var rules []windowrules.Rule
	for i, p := range fixture.Patterns {
		if p.Regex != "" {
			rules = append(rules, rule("p"+strconv.Itoa(i), windowrules.WindowEffects{Float: true}, conds{cond(title, windowrules.Op(p.Op), p.Value)}))
		}
	}
	for i, n := range fixture.Negations {
		var k conds
		for _, v := range n.Values {
			k = append(k, cond(title, isNot, v))
		}
		rules = append(rules, rule("n"+strconv.Itoa(i), windowrules.WindowEffects{Float: true}, k))
	}
	all := windowrules.WindowEffects{Monitor: "DP-1", Workspace: "w", Float: true, Width: 800, Height: 600, Center: true,
		Fullscreen: true, Maximize: true, Pin: true, Opacity: 80, NoBlur: true, NoFocus: true, NoScreenShare: true, Tearing: true}
	return append(rules, rule("all", all,
		conds{cond(appID, is, "a"), cond(title, contains, "t")},
		conds{cond(appID, is, "a"), cond(appID, isNot, "b")},
		conds{cond(appID, isNot, "b"), cond(title, isNot, "c")},
		conds{cond(xway, is, "")},
		conds{cond(xway, isNot, "")}))
}

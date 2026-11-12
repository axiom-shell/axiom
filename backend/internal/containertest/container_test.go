//go:build container

package containertest

import (
	"encoding/json"
	"regexp"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

const swayMinimal = "set $mod Mod4\nbindsym $mod+Shift+F12 exec true\n"

// swayHandled are the command lists sway handled from its debug log, from
// byte offset on
var swayHandling = regexp.MustCompile(`(?m)Handling command '(.*)'$`)

func swayCommands(s *Session, offset int) []string {
	var out []string
	for _, m := range swayHandling.FindAllStringSubmatch(s.LogSince("sway.log", offset), -1) {
		out = append(out, strings.Split(m[1], "; ")...)
	}
	return out
}

// swayKey is the key a bindsym or unbindsym command names
func swayKey(command, verb string) string {
	rest, ok := strings.CutPrefix(command, verb+" ")
	if !ok {
		return ""
	}
	for _, f := range strings.Fields(rest) {
		if !strings.HasPrefix(f, "--") {
			return f
		}
	}
	return ""
}

func swayHandled(s *Session, offset int) bool {
	return s.WaitLog("sway.log", regexp.MustCompile(`Handling command 'bindsym `), offset)
}

func TestContainerHarnessSway(t *testing.T) {
	s := NewSession(t)
	s.StartSway(swayMinimal)
	s.StartAxiom("sway")
	if !swayHandled(s, 0) {
		t.Fatalf("sway never handled axiom's binds; sway log tail:\n%s\naxiom log tail:\n%s", s.Tail("sway.log", 20), s.Tail(daemonLog, 30))
	}
}

// A daemon started on a sway an earlier daemon bound keys on must not
// unbind a key the user's config binds now (its saved unbind list is from
// before): the user's bind would be gone.
func TestContainerSwayFreshDaemonKeepsAUsersNewBind(t *testing.T) {
	s := NewSession(t)
	s.StartSway(swayMinimal)
	first := s.StartAxiom("sway")
	if !swayHandled(s, 0) {
		t.Fatalf("sway never handled axiom's binds; sway log tail:\n%s\naxiom log tail:\n%s", s.Tail("sway.log", 20), s.Tail(daemonLog, 30))
	}
	var keys []string
	for _, c := range swayCommands(s, 0) {
		if k := swayKey(c, "bindsym"); k != "" && k != "Mod4+Shift+F12" {
			keys = append(keys, k)
		}
	}
	if len(keys) < 2 {
		t.Fatalf("axiom bound %v: want at least two keys", keys)
	}
	taken, control := keys[0], keys[len(keys)-1]
	t.Logf("the user will bind %s; control %s", taken, control)

	// No teardown yet: the binds stay in sway when axiom stops
	first.Signal(sigterm)
	if !first.Wait() {
		t.Fatal("axiom didn't stop")
	}
	s.WriteFile(".config/sway/config", swayMinimal+"bindsym "+taken+" exec true\n")
	s.Swaymsg("reload")
	offset := len(s.LogSince("sway.log", 0))
	s.StartAxiom("sway")
	if !swayHandled(s, offset) {
		t.Fatalf("the second daemon's binds never reached sway; log tail:\n%s", s.Tail("sway.log", 20))
	}
	// Its unbinds go before its binds: wait for the control's
	var unbound []string
	if !testkit.Eventually(func() bool {
		unbound = nil
		for _, c := range swayCommands(s, offset) {
			if k := swayKey(c, "unbindsym"); k != "" {
				unbound = append(unbound, k)
			}
		}
		return len(unbound) > 0
	}) {
		t.Log("the second daemon unbound nothing")
	}
	if slices.Contains(unbound, taken) {
		t.Errorf("the second daemon unbound %s, which the user's config binds now (%d keys unbound)", taken, len(unbound))
	}
	if !slices.Contains(unbound, control) {
		t.Errorf("control: the saved unbind of %s was never sent (%d keys unbound)", control, len(unbound))
	}
}

func TestContainerNiriLoadConfigProbe(t *testing.T) {
	s := NewSession(t)
	s.StartSway("")
	const output = "winit"
	conf := func(workspace, extra string) string {
		return "workspace \"" + workspace + "\"\noutput \"" + output + "\" {\n    scale " + extra + "\n}\n"
	}
	a := conf("probe-a", "1")
	s.StartNiriNested(a)
	pathB := s.WriteFile("b.kdl", conf("probe-b", "2"))
	pathC := s.WriteFile("c.kdl", "this is not { valid kdl\n")

	scale := func() string {
		out := s.NiriMsg("-j", "outputs")
		var outputs map[string]struct {
			Logical *struct {
				Scale float64 `json:"scale"`
			} `json:"logical"`
		}
		if err := json.Unmarshal([]byte(out), &outputs); err != nil {
			t.Fatalf("outputs: %v: %s", err, out)
		}
		o := outputs[output]
		if o.Logical == nil {
			return "no logical output: " + out
		}
		return strings.TrimRight(strings.TrimRight(strings.TrimSpace(formatFloat(o.Logical.Scale)), "0"), ".")
	}
	settle := func() { time.Sleep(testkit.Bound(time.Second)) }
	workspaces := func() string {
		var names []string
		var list []struct {
			Name *string `json:"name"`
		}
		json.Unmarshal([]byte(s.NiriMsg("-j", "workspaces")), &list)
		for _, w := range list {
			if w.Name != nil {
				names = append(names, *w.Name)
			}
		}
		return strings.Join(names, ",")
	}
	load := func(args ...string) string {
		out, err := s.NiriMsgTry(append([]string{"action", "load-config-file"}, args...)...)
		settle()
		if err != nil {
			return "error: " + strings.TrimSpace(out)
		}
		return "ok"
	}
	t.Logf("start: scale %s, named workspaces [%s]", scale(), workspaces())

	// E1: does a load with no path go to niri's default path, or reload the
	// config it loaded last?
	t.Logf("E1: load B: %s; scale %s, workspaces [%s]", load("--path", pathB), scale(), workspaces())
	t.Logf("E1: load no path: %s; scale %s (1 = A, the default path; 2 = B, the current one), workspaces [%s]", load(), scale(), workspaces())

	// E3: an IPC output change, then a load
	t.Logf("E3: output scale 1.5: %s", firstLine(s.NiriMsg("output", output, "scale", "1.5")))
	settle()
	t.Logf("E3: after it, scale %s", scale())
	t.Logf("E3: load B: %s; scale %s (1.5 = the IPC change stayed, 2 = reverted to B's)", load("--path", pathB), scale())
	t.Logf("E3: output scale 1.5 again, then load B again (same file): %s", firstLine(s.NiriMsg("output", output, "scale", "1.5")))
	settle()
	t.Logf("E3: load B: %s; scale %s", load("--path", pathB), scale())

	// E2: a failed load
	t.Logf("E2: running B: scale %s", scale())
	t.Logf("E2: load invalid C: %s; scale %s, workspaces [%s]", load("--path", pathC), scale(), workspaces())
	s.WriteFile("b.kdl", conf("probe-b", "3"))
	settle()
	t.Logf("E2: B edited to scale 3 after the failed load: scale %s (3 = niri still watches B, 2 = it doesn't)", scale())
	s.WriteFile("c.kdl", conf("probe-c", "1.25"))
	settle()
	t.Logf("E2: C fixed to scale 1.25: scale %s (1.25 = niri watches C now)", scale())
	s.WriteFile("b.kdl", conf("probe-b", "4"))
	settle()
	t.Logf("E2: B edited to scale 4: scale %s", scale())
	t.Logf("E2: load no path: %s; scale %s", load(), scale())
	t.Logf("niri log tail:\n%s", s.Tail("niri.log", 40))
}

func firstLine(s string) string {
	l, _, _ := strings.Cut(strings.TrimSpace(s), "\n")
	return l
}

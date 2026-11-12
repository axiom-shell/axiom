//go:build container

package containertest

import (
	"encoding/json"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"syscall"
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
	// The binds go in more than one command list: wait until the count
	// holds still
	var keys []string
	last := -1
	if !testkit.Eventually(func() bool {
		keys = nil
		for _, c := range swayCommands(s, 0) {
			if k := swayKey(c, "bindsym"); k != "" && k != "Mod4+Shift+F12" {
				keys = append(keys, k)
			}
		}
		stable := len(keys) >= 2 && len(keys) == last
		last = len(keys)
		return stable
	}) {
		t.Fatalf("axiom bound %v: want at least two keys, settled", keys)
	}
	taken, control := keys[0], keys[len(keys)-1]
	t.Logf("the user will bind %s; control %s", taken, control)

	// No teardown yet: the binds stay in sway when axiom stops
	first.Signal(syscall.SIGTERM)
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

// What niri does with load-config-file (docs/dev/compositor/niri-backend.md
// records it; the writer's choices rest on it). The output's scale tells
// which config niri runs.
func TestContainerNiriLoadConfigProbe(t *testing.T) {
	s := NewSession(t)
	s.StartSway("")
	const output = "winit"
	conf := func(workspace, scale string) string {
		return "workspace \"" + workspace + "\"\noutput \"" + output + "\" {\n    scale " + scale + "\n}\n"
	}
	s.StartNiriNested(conf("probe-a", "1"))
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
		return strconv.FormatFloat(o.Logical.Scale, 'f', -1, 64)
	}
	becomes := func(what, want string) {
		t.Helper()
		if !testkit.Eventually(func() bool { return scale() == want }) {
			t.Fatalf("%s: scale is %s, want %s; niri log tail:\n%s", what, scale(), want, s.Tail("niri.log", 20))
		}
		t.Logf("%s: scale %s", what, want)
	}
	// stays: a wait that nothing happens, short and unstretched
	stays := func(what, want string) {
		t.Helper()
		time.Sleep(time.Second)
		if got := scale(); got != want {
			t.Fatalf("%s: scale is %s, want it to stay %s", what, got, want)
		}
		t.Logf("%s: scale stays %s", what, want)
	}
	load := func(args ...string) {
		t.Helper()
		if out, err := s.NiriMsgTry(append([]string{"action", "load-config-file"}, args...)...); err != nil {
			t.Fatalf("load-config-file %v: %v\n%s", args, err, out)
		}
	}
	becomes("started on A", "1")

	// E1: a load with no path reloads the config loaded last, not the
	// default path (A)
	load("--path", pathB)
	becomes("E1: loaded B", "2")
	load()
	stays("E1: load with no path", "2")

	// E3: an IPC output change survives a load of a config whose output is
	// unchanged
	s.NiriMsg("output", output, "scale", "1.5")
	becomes("E3: IPC scale change", "1.5")
	load("--path", pathB)
	stays("E3: load of B again", "1.5")

	// E2: a refused config leaves niri running the old one (the load is
	// still answered Ok), and its watcher moves to the refused file
	load("--path", pathC)
	stays("E2: load of invalid C", "1.5")
	s.WriteFile("b.kdl", conf("probe-b", "3"))
	stays("E2: B edited after the failed load", "1.5")
	s.WriteFile("c.kdl", conf("probe-c", "1.25"))
	becomes("E2: C fixed", "1.25")
	s.WriteFile("b.kdl", conf("probe-b", "4"))
	stays("E2: B edited again", "1.25")
}

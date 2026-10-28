package manager

import (
	"context"
	"sync"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/compositor/ipc"
	"github.com/axiom-shell/axiom/backend/internal/compositor/render"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// fakeOutputs is a compositor's outputs: what's connected, and the rules
// applied
type fakeOutputs struct {
	mu        sync.Mutex
	connected []render.Output
	reads     int
	applied   []string
}

func (f *fakeOutputs) Read(context.Context) ([]render.Output, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.reads++
	return append([]render.Output(nil), f.connected...), nil
}

func (f *fakeOutputs) Apply(_ context.Context, rules, details any) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.applied = append(f.applied, string(jsonx.MarshalCompact(rules)))
	return nil
}

func (f *fakeOutputs) connect(outputs ...render.Output) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.connected = outputs
}

func (f *fakeOutputs) counts() (int, []string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.reads, append([]string(nil), f.applied...)
}

var (
	deskRule     = `{"output":"desc:Main","x":0}`
	tvRule       = `{"output":"HDMI-A-1","x":2560}`
	testProfiles = `[{"name":"Desk","outputs":[` + deskRule + `]},{"name":"Both","outputs":[` + deskRule + `,` + tvRule + `]}]`
	mainOut      = render.Output{Name: "DP-1", Description: "Main"}
	tvOut        = render.Output{Name: "HDMI-A-1", Description: "TV"}
)

// On sway and niri the saved profile follows hotplugs: a burst of changes
// is read once, settled; the profile for what's connected is applied once
// per set of outputs, and again after a reload (detached: the reload set
// the outputs as the user's config says)
func TestHotplugsApplyTheSavedProfile(t *testing.T) {
	t.Parallel()
	h := newHarness(t, "detached")
	items, _ := jsonx.Unmarshal([]byte(testProfiles))
	h.modeMu.Lock()
	h.config = jsonx.Obj("Monitors", jsonx.Obj("items", items))
	h.modeMu.Unlock()
	f := &fakeOutputs{}
	f.connect(mainOut, tvOut)
	h.m.profiles = &profileSwitch{io: f}
	h.m.hotplugDelay = 100 * time.Millisecond

	applied := func(n int) func() bool {
		return func() bool { _, a := f.counts(); return len(a) == n }
	}
	for range 3 {
		h.m.OutputsChanged()
	}
	h.eventually("the profile for both", applied(1))
	if reads, a := f.counts(); reads != 1 || a[0] != "["+deskRule+","+tvRule+"]" {
		t.Fatalf("reads %d, applied %v", reads, a)
	}

	// The same outputs again (an output the profile turned off): nothing
	h.m.OutputsChanged()
	h.eventually("read again", func() bool { r, _ := f.counts(); return r == 2 })
	h.m.do(context.Background(), func(context.Context) {})
	if _, a := f.counts(); len(a) != 1 {
		t.Fatalf("applied again for the same outputs: %v", a)
	}

	h.w.reloadCh <- ipc.Reload{}
	h.eventually("again after a reload", applied(2))

	f.connect(mainOut)
	h.m.OutputsChanged()
	h.eventually("the desk's profile", applied(3))
	if _, a := f.counts(); a[2] != "["+deskRule+"]" {
		t.Fatalf("unplugged: applied %s", a[2])
	}
}

// buildInputs gives sway's and niri's writers the saved profile's rules
// for the outputs read: nil until they're read (the files keep what they
// say), [] when no profile matches
func TestBuildInputsOutputRules(t *testing.T) {
	t.Parallel()
	items, _ := jsonx.Unmarshal([]byte(testProfiles))
	cfg := jsonx.Obj("Monitors", jsonx.Obj("items", items))
	for _, c := range []struct {
		name    string
		outputs []render.Output
		want    string
	}{
		{"unread", nil, "null"},
		{"both", []render.Output{mainOut, tvOut}, "[" + deskRule + "," + tvRule + "]"},
		{"desk", []render.Output{mainOut}, "[" + deskRule + "]"},
		{"no profile", []render.Output{{Name: "DP-9"}}, `[]`},
	} {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			in := buildInputs(cfg, &Facts{Kind: "sway"}, c.outputs)
			if got := string(jsonx.MarshalCompact(in.get("outputRules"))); got != c.want {
				t.Errorf("got %s, want %s", got, c.want)
			}
		})
	}
}

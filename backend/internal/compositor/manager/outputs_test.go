package manager

import (
	"context"
	"errors"
	"log/slog"
	"sync"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/compositor/ipc"
	"github.com/axiom-shell/axiom/backend/internal/compositor/render"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

// fakeOutputs is a compositor's outputs: what's connected, and the rules
// applied
type fakeOutputs struct {
	mu        sync.Mutex
	connected []render.Output
	reads     int
	applied   []string
	// fail: Apply's error (nil: it succeeds); it's still counted
	fail error
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
	return f.fail
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

// A failed apply doesn't count as applied: the next call for the same
// outputs and rules tries again, and once it succeeds the call after is
// skipped
func TestAFailedProfileApplyIsTriedAgain(t *testing.T) {
	t.Parallel()
	f := &fakeOutputs{fail: errors.New("no reply")}
	f.connect(mainOut)
	p := &profileSwitch{io: f}
	ctx := context.Background()
	if err := p.read(ctx); err != nil {
		t.Fatal(err)
	}
	items, _ := jsonx.Unmarshal([]byte(testProfiles))
	if err := p.apply(ctx, items); err == nil {
		t.Fatal("the failure isn't returned")
	}
	f.mu.Lock()
	f.fail = nil
	f.mu.Unlock()
	for range 2 {
		if err := p.apply(ctx, items); err != nil {
			t.Fatal(err)
		}
	}
	if _, a := f.counts(); len(a) != 2 {
		t.Fatalf("applied %d times, want 2 (the failure, then once): %v", len(a), a)
	}
}

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
	// compositor.state names the profile matched on the last read
	profile := func(want string) {
		t.Helper()
		if got := h.state("monitorProfile"); got != want {
			t.Fatalf("monitorProfile %v, want %q", got, want)
		}
	}
	profile("")
	for range 3 {
		h.m.OutputsChanged()
	}
	h.eventually("the profile for both", applied(1))
	if reads, a := f.counts(); reads != 1 || a[0] != "["+deskRule+","+tvRule+"]" {
		t.Fatalf("reads %d, applied %v", reads, a)
	}
	profile("Both")

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
	profile("Desk")

	// None matches
	f.connect(render.Output{Name: "DP-9"})
	h.m.OutputsChanged()
	h.eventually("read with none matching", func() bool { r, _ := f.counts(); return r == 4 })
	h.m.do(context.Background(), func(context.Context) {})
	profile("")
}

// A file mode whose file stops loading (included, its include line taken
// out): the reload set the outputs from the user's config, so the saved
// profile goes back on
func TestAFileThatStopsLoadingAppliesTheSavedProfile(t *testing.T) {
	t.Parallel()
	h := newHarness(t, "included")
	items, _ := jsonx.Unmarshal([]byte(testProfiles))
	h.modeMu.Lock()
	h.config = jsonx.Obj("Monitors", jsonx.Obj("items", items))
	h.modeMu.Unlock()
	f := &fakeOutputs{}
	f.connect(mainOut, tvOut)
	h.m.profiles = &profileSwitch{io: f}
	h.m.hotplugDelay = 0
	applied := func(n int) func() bool {
		return func() bool { _, a := f.counts(); return len(a) == n }
	}
	reload := func(loaded bool) {
		h.w.mu.Lock()
		h.w.loaded = loaded
		n := h.w.reloaded + 1
		h.w.mu.Unlock()
		h.w.reloadCh <- ipc.Reload{}
		h.eventually("the reload taken", func() bool {
			h.w.mu.Lock()
			defer h.w.mu.Unlock()
			return h.w.reloaded == n
		})
		h.m.do(context.Background(), func(context.Context) {})
	}
	h.m.OutputsChanged()
	h.eventually("the profile", applied(1))
	h.inputs("f1", "l1", "k1")
	h.eventually("live", func() bool { return h.state("live") == true })
	reload(true)
	reload(true)
	if _, a := f.counts(); len(a) != 1 || h.status() != "loaded" {
		t.Fatalf("applied with the module loaded (%s): %v", h.status(), a)
	}
	// The include line taken out
	reload(false)
	reload(false)
	if _, a := f.counts(); len(a) != 3 {
		t.Fatalf("applied %d times, want once each reload", len(a))
	}
}

// buildInputs gives the writers the saved profile's rules for the outputs
// read: nil until they're read (the files keep what they
// say), [] when no profile matches; sway's name the output by its
// connector
func TestBuildInputsOutputRules(t *testing.T) {
	t.Parallel()
	items, _ := jsonx.Unmarshal([]byte(testProfiles))
	cfg := jsonx.Obj("Monitors", jsonx.Obj("items", items))
	deskOnSway := `{"output":"DP-1","x":0}`
	for _, c := range []struct {
		name    string
		kind    string
		outputs []render.Output
		want    string
	}{
		{"unread", "sway", nil, "null"},
		{"both", "sway", []render.Output{mainOut, tvOut}, "[" + deskOnSway + "," + tvRule + "]"},
		{"desk", "sway", []render.Output{mainOut}, "[" + deskOnSway + "]"},
		{"desk on niri", "niri", []render.Output{mainOut}, "[" + deskRule + "]"},
		{"no profile", "sway", []render.Output{{Name: "DP-9"}}, `[]`},
		// Hyprland's also hold the TV's rule, which every profile naming
		// it agrees on, for when it's plugged in
		{"desk on Hyprland", "hyprland", []render.Output{mainOut}, "[" + deskRule + "," + tvRule + "]"},
	} {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			in := buildInputs(cfg, &Facts{Kind: c.kind}, c.outputs)
			if got := string(jsonx.MarshalCompact(in.get("outputRules"))); got != c.want {
				t.Errorf("got %s, want %s", got, c.want)
			}
		})
	}
}

// Hyprland's writer gets the rules as hl.monitor calls, and an output only
// turned off, the calls the same, leaves layerKey (no layer re-applied)
func TestBuildInputsMonitorCalls(t *testing.T) {
	t.Parallel()
	items, _ := jsonx.Unmarshal([]byte(testProfiles))
	cfg := jsonx.Obj("Monitors", jsonx.Obj("items", items))
	on := buildInputs(cfg, &Facts{Kind: "hyprland"}, []render.Output{mainOut, {Name: "DP-9"}})
	off := buildInputs(cfg, &Facts{Kind: "hyprland"}, []render.Output{mainOut, {Name: "DP-9", Disabled: true}})
	want := `["hl.monitor({ output = \"desc:Main\", mode = \"preferred\", position = \"0x0\", scale = 1 })","hl.monitor({ output = \"HDMI-A-1\", mode = \"preferred\", position = \"2560x0\", scale = 1 })"]`
	if got := string(jsonx.MarshalCompact(on.get("monitorCalls"))); got != want {
		t.Errorf("got %s, want %s", got, want)
	}
	if on.str("layerKey") != off.str("layerKey") {
		t.Error("an output turned off changed layerKey")
	}
	if got := buildInputs(cfg, &Facts{Kind: "sway"}, []render.Output{mainOut}).get("monitorCalls"); got != nil {
		t.Errorf("sway: %v", got)
	}
}

// The greeter's watch (ProfileWatch): the profiles set are applied for
// what's connected, a burst of hotplugs read once, settled; nothing once
// its context ends
func TestProfileWatch(t *testing.T) {
	t.Parallel()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	f := &fakeOutputs{}
	f.connect(mainOut, tvOut)
	w := newProfileWatch(ctx, f, slog.New(slog.DiscardHandler))
	w.delay = 50 * time.Millisecond
	eventually := func(what string, cond func() bool) {
		t.Helper()
		if !testkit.Eventually(cond) {
			t.Fatalf("never: %s", what)
		}
	}
	items, _ := jsonx.Unmarshal([]byte(testProfiles))
	w.SetProfiles(items)
	eventually("the profile for both", func() bool { _, a := f.counts(); return len(a) == 1 })

	f.connect(mainOut)
	for range 3 {
		w.Changed()
	}
	eventually("the desk's profile", func() bool { _, a := f.counts(); return len(a) == 2 })
	if reads, a := f.counts(); reads != 2 || a[1] != "["+deskRule+"]" {
		t.Fatalf("reads %d, applied %v", reads, a)
	}

	cancel()
	f.connect(mainOut, tvOut)
	w.Changed()
	time.Sleep(150 * time.Millisecond)
	if reads, _ := f.counts(); reads != 2 {
		t.Fatalf("read after its context ended: %d", reads)
	}
}

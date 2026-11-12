package manager

import (
	"context"
	"fmt"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/compositor/ipc"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/session"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

// fakeWriter is a writer whose compositor is a list of what was asked of
// it
type fakeWriter struct {
	mu      sync.Mutex
	dir     string
	calls   []string
	loaded  bool
	invalid string
	unread  string
	// elsewhere: the user's config the compositor runs instead (sway's)
	elsewhere string
	reloadCh  chan ipc.Reload
	// reloaded: the reloads the manager has taken (configReloaded)
	reloaded int
}

func (f *fakeWriter) note(c string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls = append(f.calls, c)
}

func (f *fakeWriter) seen() []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]string(nil), f.calls...)
}

func (f *fakeWriter) files(in Inputs) files {
	return files{ConfigDir: f.dir + "/conf/", IncludePath: f.dir + "/state/module", ManagedPath: f.dir + "/conf/hyprland.lua",
		UserDir: f.dir + "/conf/user", UserFiles: f.dir + "/conf/user/*.lua", IncludeLines: "load it", RunsElsewhere: f.elsewhere}
}
func (f *fakeWriter) moduleText(in Inputs, spec any) string {
	return "-- module " + jsonx.ToString(getAny(spec, "tag")) + "\n"
}
func (f *fakeWriter) managedText(in Inputs, spec any) string {
	return hyprHeader + " managed " + jsonx.ToString(getAny(spec, "tag")) + "\n"
}
func (f *fakeWriter) emptyModuleText() string                    { return "-- empty\n" }
func (f *fakeWriter) releasedText(in Inputs, mode string) string { return "-- given back" }
func (f *fakeWriter) liveLines(in Inputs, spec any) []string {
	return []string{"live " + jsonx.ToString(getAny(spec, "tag"))}
}
func (f *fakeWriter) blurLines(in Inputs, spec any) []string {
	return []string{"blur " + jsonx.ToString(getAny(spec, "tag"))}
}
func (f *fakeWriter) liveByFile() bool                        { return false }
func (f *fakeWriter) takesBack(part string) bool              { return part == "opacity" }
func (f *fakeWriter) validate(context.Context, string) string { return f.invalid }
func (f *fakeWriter) runLive(_ context.Context, lines []string) bool {
	f.note("live:" + strings.Join(lines, ";"))
	return true
}
func (f *fakeWriter) setCursor(context.Context, any) { f.note("cursor") }
func (f *fakeWriter) runtimeApply(_ context.Context, in Inputs, live func() []string) {
	f.note("runtime:" + strings.Join(live(), ";"))
}
func (f *fakeWriter) runtimeClear(context.Context) { f.note("clear") }
func (f *fakeWriter) teardownSteps(Inputs, bool) []session.Step {
	return []session.Step{{Op: "reload"}}
}
func (f *fakeWriter) reloadStartsAxiom(Inputs) (bool, string) { return false, "" }
func (f *fakeWriter) seenReload()                             {}
func (f *fakeWriter) skippedKeys() []string                   { return nil }
func (f *fakeWriter) checkLoaded(context.Context, Inputs, string) (bool, bool) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.loaded, false
}
func (f *fakeWriter) reload(context.Context) { f.note("reload") }
func (f *fakeWriter) screenPower(_ context.Context, on bool) error {
	f.note(fmt.Sprintf("screenPower %v", on))
	return nil
}
func (f *fakeWriter) reloads(ctx context.Context, out chan<- ipc.Reload) error {
	for {
		select {
		case <-ctx.Done():
			return nil
		case r := <-f.reloadCh:
			out <- r
		}
	}
}
func (f *fakeWriter) configReloaded(context.Context, Inputs) bool {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.reloaded++
	return false
}
func (f *fakeWriter) ownKey(Inputs) string                         { return "" }
func (f *fakeWriter) complete(Inputs, any) bool                    { return true }
func (f *fakeWriter) entries(context.Context, Inputs) *jsonx.Array { return nil }
func (f *fakeWriter) takeoverKind() string                         { return "hyprland" }
func (f *fakeWriter) header() string                               { return hyprHeader }
func (f *fakeWriter) monitorPattern() (*regexp.Regexp, string) {
	return regexp.MustCompile(`hl\.monitor`), "*.lua"
}
func (f *fakeWriter) runningConfig(Inputs) string { return "" }
func (f *fakeWriter) problems(Inputs) problems {
	f.mu.Lock()
	defer f.mu.Unlock()
	return problems{NotIncluded: "not included", NotManaged: "not managed", Failed: "failed",
		Invalid: func(e string) string { return "invalid: " + e }, Runtime: f.unread}
}

type harness struct {
	t      *testing.T
	m      *Manager
	w      *fakeWriter
	mode   string
	config *jsonx.Object // under modeMu
	modeMu sync.Mutex
	pushes chan string
	steps  chan []session.Step
	stop   func()
}

func newHarness(t *testing.T, mode string) *harness {
	t.Helper()
	dir := t.TempDir()
	h := &harness{t: t, mode: mode, config: jsonx.NewObject(), pushes: make(chan string, 64), steps: make(chan []session.Step, 16)}
	env := map[string]string{"HYPRLAND_INSTANCE_SIGNATURE": "test", "XDG_RUNTIME_DIR": dir}
	h.m = New(Options{
		Getenv:      func(k string) string { return env[k] },
		StateDir:    filepath.Join(dir, "state"),
		RuntimeFile: filepath.Join(dir, "run", "compositor.json"),
		Schema:      func() any { return jsonx.NewObject() },
		Mode: func() string {
			h.modeMu.Lock()
			defer h.modeMu.Unlock()
			return h.mode
		},
		Config: func() *jsonx.Object {
			h.modeMu.Lock()
			defer h.modeMu.Unlock()
			return h.config
		},
		Binds:       func() any { return jsonx.Arr() },
		CommitBinds: func(*jsonx.Array) error { return nil },
		OnSteps: func(steps []session.Step) {
			select {
			case h.steps <- steps:
			default:
			}
		},
		Push: func(method string, params any) {
			if method != "compositor.state" {
				select {
				case h.pushes <- method + ":" + string(jsonx.MarshalCompact(params)):
				default:
				}
			}
		},
		Log: slog.New(slog.NewTextHandler(io.Discard, nil)),
	})
	h.w = &fakeWriter{dir: dir, reloadCh: make(chan ipc.Reload, 4)}
	h.m.w = h.w
	ctx, cancel := context.WithCancel(context.Background())
	ran := make(chan struct{})
	go func() {
		defer close(ran)
		h.m.Run(ctx)
	}()
	// Ended before t.TempDir's cleanup: a write still running would race
	// the folder's removal
	var once sync.Once
	h.stop = func() {
		once.Do(func() {
			cancel()
			<-ran
		})
	}
	t.Cleanup(h.stop)
	return h
}

// inputs sets what the layer is made of, the specs tagged (what the fake
// writes)
func (h *harness) inputs(fileTag, liveTag, layerKey string, parts ...string) {
	look := jsonx.Obj("parts", strs(parts))
	in := Inputs{jsonx.Obj("kind", "hyprland", "layerKey", layerKey, "liveKey", liveTag,
		"supports", jsonx.Obj("windowBorders", true, "windowGaps", true, "windowOpacity", true),
		"specFile", jsonx.Obj("tag", fileTag, "look", look), "specLive", jsonx.Obj("tag", liveTag, "look", look))}
	h.m.enqueue(func(context.Context) { h.m.setInputs(in) })
}

// setMode changes the mode as the shell's save does
func (h *harness) setMode(mode string) { h.changeMode(mode, false) }

// changeMode changes the mode, read from the file (an edit made outside)
// or saved by the shell
func (h *harness) changeMode(mode string, fromFile bool) {
	h.modeMu.Lock()
	h.mode = mode
	h.modeMu.Unlock()
	h.m.ConfigChanged(fromFile)
}

// eventually waits for cond
func (h *harness) eventually(what string, cond func() bool) {
	h.t.Helper()
	if testkit.Eventually(cond) {
		return
	}
	h.t.Fatalf("never: %s (calls %v, state %s)", what, h.w.seen(), jsonx.MarshalCompact(h.m.State(context.Background())))
}

func (h *harness) called(c string) func() bool {
	return func() bool { return slices.Contains(h.w.seen(), c) }
}

func (h *harness) status() string {
	return jsonx.ToString(h.m.State(context.Background()).Value("status"))
}

func TestNothingWithoutTheShellsInputs(t *testing.T) {
	t.Parallel()
	h := newHarness(t, "detached")
	time.Sleep(500 * time.Millisecond)
	if calls := h.w.seen(); len(calls) != 0 {
		t.Fatalf("acted without inputs: %v", calls)
	}
}

func TestDetachedAppliesTheRuntimeLayer(t *testing.T) {
	t.Parallel()
	h := newHarness(t, "detached")
	h.inputs("f1", "l1", "k1")
	h.eventually("the runtime layer", h.called("runtime:live l1"))
	if h.status() != "runtime" {
		t.Fatalf("status %s", h.status())
	}
	// A reload drops it: applied again
	h.w.reloadCh <- ipc.Reload{}
	h.eventually("again after a reload", func() bool {
		n := 0
		for _, c := range h.w.seen() {
			if c == "runtime:live l1" {
				n++
			}
		}
		return n >= 2
	})
}

func TestUnreadUserBindsShowAProblem(t *testing.T) {
	t.Parallel()
	h := newHarness(t, "detached")
	h.w.unread = "unread"
	h.inputs("f1", "l1", "k1")
	h.eventually("the problem", func() bool { return jsonx.ToString(h.state("problem")) == "unread" })
	// Another one after a reload (niri's next refusal): it replaces the first
	h.w.mu.Lock()
	h.w.unread = "unread again"
	h.w.mu.Unlock()
	h.w.reloadCh <- ipc.Reload{}
	h.eventually("the new problem", func() bool { return jsonx.ToString(h.state("problem")) == "unread again" })
	// Read again after a reload: gone
	h.w.mu.Lock()
	h.w.unread = ""
	h.w.mu.Unlock()
	h.w.reloadCh <- ipc.Reload{}
	h.eventually("the problem gone", func() bool { return jsonx.ToString(h.state("problem")) == "" })
}

func TestIncludedWritesTheModule(t *testing.T) {
	t.Parallel()
	h := newHarness(t, "included")
	h.inputs("f1", "l1", "k1")
	path := h.w.files(Inputs{}).IncludePath
	h.eventually("the module written and the compositor reloaded", func() bool {
		return readFile(path) == "-- module f1\n" && slices.Contains(h.w.seen(), "reload")
	})
	// Not loaded after the reload: the runtime layer stands in, and the
	// shell is told
	h.w.reloadCh <- ipc.Reload{}
	h.eventually("the fallback", func() bool { return h.status() == "fallback" })
	h.eventually("the notification", func() bool {
		for len(h.pushes) > 0 {
			if strings.Contains(<-h.pushes, `"included"`) {
				return true
			}
		}
		return false
	})
	// Loaded: the runtime layer goes
	h.w.mu.Lock()
	h.w.loaded = true
	h.w.mu.Unlock()
	h.w.reloadCh <- ipc.Reload{}
	h.eventually("loaded", func() bool { return h.status() == "loaded" })
	h.eventually("cleared", h.called("clear"))
	// A layer change rewrites it
	h.inputs("f2", "l1", "k2")
	h.eventually("rewritten", func() bool { return readFile(path) == "-- module f2\n" })
}

// The layer follows the config: a save the shell sent no facts for (a
// bind's) still reaches what the layer is made of
func TestTheLayerFollowsTheConfig(t *testing.T) {
	t.Parallel()
	h := newHarness(t, "detached")
	setBinds := func(ids ...string) {
		binds := jsonx.Arr()
		for _, id := range ids {
			binds.Append(jsonx.Obj("id", id))
		}
		h.modeMu.Lock()
		h.config = jsonx.Obj("Keybinds", jsonx.Obj("binds", binds))
		h.modeMu.Unlock()
	}
	complete := func(want string) func() bool {
		return func() bool {
			return string(jsonx.MarshalCompact(h.m.State(context.Background()).Value("complete"))) == want
		}
	}
	setBinds("a")
	h.m.SetFacts(Facts{Kind: "hyprland"})
	h.eventually("the config's binds", complete(`[{"id":"a"}]`))
	setBinds("a", "b")
	h.m.ConfigChanged(false)
	h.eventually("the saved binds", complete(`[{"id":"a"},{"id":"b"}]`))
}

func TestARefusedTextIsntWritten(t *testing.T) {
	t.Parallel()
	h := newHarness(t, "included")
	h.w.invalid = "bad bind"
	h.inputs("f1", "l1", "k1")
	h.eventually("the problem", func() bool {
		return jsonx.ToString(h.m.State(context.Background()).Value("problem")) == "invalid: bad bind"
	})
	if _, err := os.Stat(h.w.files(Inputs{}).IncludePath); err == nil {
		t.Fatal("a refused module was written")
	}
}

func TestManagedWaitsForApproval(t *testing.T) {
	t.Parallel()
	h := newHarness(t, "managed")
	f := h.w.files(Inputs{})
	os.MkdirAll(f.ConfigDir, 0o755)
	os.WriteFile(f.ManagedPath, []byte("-- mine\n"), 0o644)
	h.inputs("f1", "l1", "k1")
	h.eventually("the takeover pending", func() bool {
		return h.m.State(context.Background()).Value("takeoverPending") == true
	})
	if readFile(f.ManagedPath) != "-- mine\n" {
		t.Fatal("taken over without approval")
	}
	h.eventually("the runtime layer meanwhile", h.called("runtime:live l1"))
	h.m.AllowTakeover()
	h.eventually("taken over", func() bool { return readFile(f.ManagedPath) == hyprHeader+" managed f1\n" })
	if readFile(filepath.Join(f.UserDir, "00-previous.lua")) != "-- mine\n" {
		t.Fatal("the user's config wasn't adopted")
	}
	if !approvals(approvals{path: filepath.Join(h.m.o.StateDir, "ui", "takeover.json")}).has("hyprland") {
		t.Fatal("the approval wasn't saved")
	}
	// Leaving managed gives it back
	h.setMode("detached")
	h.eventually("given back", func() bool { return readFile(f.ManagedPath) == "-- mine\n" })
}

func TestANewConfigNeedsNoApproval(t *testing.T) {
	t.Parallel()
	h := newHarness(t, "managed")
	h.inputs("f1", "l1", "k1")
	f := h.w.files(Inputs{})
	h.eventually("taken over", func() bool { return readFile(f.ManagedPath) == hyprHeader+" managed f1\n" })
}

// A compositor running another config of the user's is never taken over:
// the managed file would never load
func TestManagedIsBlockedWhenTheCompositorRunsAnotherConfig(t *testing.T) {
	t.Parallel()
	h := newHarness(t, "managed")
	h.w.elsewhere = "/home/me/.config/i3/config"
	h.inputs("f1", "l1", "k1")
	h.eventually("the runtime layer instead", h.called("runtime:live l1"))
	h.eventually("blocked", func() bool {
		return h.state("managedCheck") == "blocked" && h.state("managedBlockedBy") == "elsewhere"
	})
	f := h.w.files(Inputs{})
	if _, err := os.Stat(f.ManagedPath); err == nil {
		t.Fatal("the managed config was written")
	}
}

func TestLivePartsAreEvaluatedAndTakenBack(t *testing.T) {
	t.Parallel()
	h := newHarness(t, "detached")
	h.inputs("f1", "l1", "k1", "borders", "gaps")
	h.eventually("the runtime layer", h.called("runtime:live l1"))
	// A live change is only evaluated
	h.inputs("f1", "l2", "k1", "borders", "gaps")
	h.eventually("evaluated", h.called("live:live l2"))
	// A part turned off can't be taken back by an eval: the compositor
	// reloads
	h.inputs("f1", "l3", "k1", "borders")
	h.eventually("reloaded", h.called("reload"))
}

func TestABlurChangeSendsOnlyTheBlur(t *testing.T) {
	t.Parallel()
	h := newHarness(t, "detached")
	set := func(rest, liveTag string) {
		look := jsonx.Obj("parts", strs([]string{"borders"}))
		in := Inputs{jsonx.Obj("kind", "hyprland", "layerKey", "k1", "liveKey", liveTag, "liveRestKey", rest,
			"supports", jsonx.Obj("windowBorders", true),
			"specFile", jsonx.Obj("tag", "f1", "look", look), "specLive", jsonx.Obj("tag", liveTag, "look", look))}
		h.m.enqueue(func(context.Context) { h.m.setInputs(in) })
	}
	set("r1", "l1")
	h.eventually("the runtime layer", h.called("runtime:live l1"))
	// Only the blur now changed (a fullscreen window paused it)
	set("r1", "l2")
	h.eventually("the blur alone", h.called("live:blur l2"))
	// Anything else sends the whole live layer
	set("r2", "l3")
	h.eventually("the whole live layer", h.called("live:live l3"))
}

func TestAPartTheShellTakesBackReloadsNothing(t *testing.T) {
	t.Parallel()
	h := newHarness(t, "detached")
	h.inputs("f1", "l1", "k1", "borders", "opacity")
	h.eventually("the runtime layer", h.called("runtime:live l1"))
	h.inputs("f1", "l2", "k1", "borders")
	h.eventually("evaluated", h.called("live:live l2"))
	if slices.Contains(h.w.seen(), "reload") {
		t.Fatal("turning opacity off reloaded the compositor")
	}
}

func TestMergedBindsGetIDs(t *testing.T) {
	t.Parallel()
	list := jsonx.Arr(jsonx.Obj("id", "super-y", "key", "SUPER + Y"), jsonx.Obj("key", "SUPER + Y", "action", "exec"),
		jsonx.Obj("key", "SUPER + U"), jsonx.Obj("key", ""), jsonx.Obj("id", "", "key", "Print"), jsonx.Obj("id", "-bad", "key", "Print"))
	got := string(jsonx.MarshalCompact(withIDs(list)))
	want := `[{"id":"super-y","key":"SUPER + Y"},{"id":"super-y-2","key":"SUPER + Y","action":"exec"},{"id":"super-u","key":"SUPER + U"},{"id":"bind","key":""},{"id":"print","key":"Print"},{"id":"print-2","key":"Print"}]`
	if got != want {
		t.Fatalf("got %s", got)
	}
}

// BindKeys.withIds' shared cases (the Keybinds page's copy of the rule)
// replayed through withIDs, so the two can't drift
func TestWithIDsSharedCases(t *testing.T) {
	t.Parallel()
	for _, c := range testkit.Cases(t, "BindKeys.withIds") {
		list, ok := jsonx.AsArray(c.Args[0])
		if !ok {
			t.Fatalf("%s: not a list", c.Name)
		}
		c.Compare(t, withIDs(list))
	}
}

// Under a compositor without config modes nothing runs the queue: config
// changes (the store's delivery) and calls must never wait on it
func TestInertManagerNeverBlocks(t *testing.T) {
	t.Parallel()
	m := New(Options{Getenv: func(string) string { return "" }, Log: slog.New(slog.NewTextHandler(io.Discard, nil))})
	ctx, cancel := context.WithCancel(context.Background())
	ran := make(chan struct{})
	go func() {
		defer close(ran)
		m.Run(ctx)
	}()
	done := make(chan struct{})
	go func() {
		for range 1000 {
			m.ConfigChanged(false)
		}
		m.State(context.Background())
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(testkit.Bound(3 * time.Second)):
		t.Fatal("blocked")
	}
	cancel()
	<-ran
}

// Once Run has ended, nothing waits on it
func TestStoppedManagerNeverBlocks(t *testing.T) {
	t.Parallel()
	h := newHarness(t, "detached")
	h.inputs("f1", "l1", "k1")
	h.eventually("the runtime layer", h.called("runtime:live l1"))
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	m2 := h.m
	m2.stop.Do(func() { close(m2.stopped) })
	done := make(chan struct{})
	go func() {
		m2.ConfigChanged(false)
		m2.State(context.Background())
		m2.Entries(ctx)
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(testkit.Bound(3 * time.Second)):
		t.Fatal("blocked")
	}
}

func (h *harness) approved() bool {
	return approvals{path: filepath.Join(h.m.o.StateDir, "ui", "takeover.json")}.has("hyprland")
}

func (h *harness) state(key string) any { return h.m.State(context.Background()).Value(key) }

// Saving managed (a mode change while axiom runs) is never the approval:
// the card asks, as for a config loaded with the mode, without a
// notification on top
func TestSavingManagedAsksForApproval(t *testing.T) {
	t.Parallel()
	h := newHarness(t, "detached")
	f := h.w.files(Inputs{})
	os.MkdirAll(f.ConfigDir, 0o755)
	os.WriteFile(f.ManagedPath, []byte("-- mine\n"), 0o644)
	h.inputs("f1", "l1", "k1")
	h.eventually("the runtime layer", h.called("runtime:live l1"))
	h.setMode("managed")
	h.eventually("the takeover pending", func() bool { return h.state("takeoverPending") == true })
	if readFile(f.ManagedPath) != "-- mine\n" || h.approved() {
		t.Fatal("saving managed took the config over")
	}
	for len(h.pushes) > 0 {
		if p := <-h.pushes; strings.Contains(p, `"approval"`) {
			t.Fatalf("notified on top of the card: %s", p)
		}
	}
	h.m.AllowTakeover()
	h.eventually("taken over", func() bool { return readFile(f.ManagedPath) == hyprHeader+" managed f1\n" })
	// Giving it back uses the approval up: the next takeover asks again
	h.setMode("detached")
	h.eventually("given back", func() bool { return readFile(f.ManagedPath) == "-- mine\n" })
	h.eventually("the approval used up", func() bool { return !h.approved() })
	h.setMode("managed")
	h.eventually("asked again", func() bool { return h.state("takeoverPending") == true })
	if readFile(f.ManagedPath) != "-- mine\n" {
		t.Fatal("taken over again without asking")
	}
}

// A config still axiom's outside managed mode (a mode changed while axiom
// wasn't running) is given back at the first apply
func TestAConfigLeftOursIsGivenBack(t *testing.T) {
	t.Parallel()
	h := newHarness(t, "detached")
	f := h.w.files(Inputs{})
	os.MkdirAll(f.UserDir, 0o755)
	os.WriteFile(f.ManagedPath, []byte(hyprHeader+" managed f0\n"), 0o644)
	h.inputs("f1", "l1", "k1")
	h.eventually("given back", func() bool { return readFile(f.ManagedPath) == "-- given back\n" })
}

// A release that fails is tried again, the shell told why meanwhile
func TestAFailedReleaseIsRetried(t *testing.T) {
	t.Parallel()
	if os.Geteuid() == 0 {
		t.Skip("root writes anywhere")
	}
	h := newHarness(t, "detached")
	h.m.releaseFirst = 100 * time.Millisecond
	f := h.w.files(Inputs{})
	os.MkdirAll(f.UserDir, 0o755)
	os.WriteFile(f.ManagedPath, []byte(hyprHeader+" managed f0\n"), 0o644)
	// Nothing can be written in the config dir
	os.Chmod(f.ConfigDir, 0o555)
	t.Cleanup(func() { os.Chmod(f.ConfigDir, 0o755) })
	h.inputs("f1", "l1", "k1")
	h.eventually("the problem", func() bool { return jsonx.ToString(h.state("releaseProblem")) != "" })
	os.Chmod(f.ConfigDir, 0o755)
	h.eventually("given back on a retry", func() bool { return readFile(f.ManagedPath) == "-- given back\n" })
	h.eventually("the problem gone", func() bool { return jsonx.ToString(h.state("releaseProblem")) == "" })
}

// The managed config given back behind the manager's back (a command
// line's release) is never written over: taking it over again asks first
func TestAConfigGivenBackMeanwhileIsntWrittenOver(t *testing.T) {
	t.Parallel()
	h := newHarness(t, "managed")
	h.w.mu.Lock()
	h.w.loaded = true
	h.w.mu.Unlock()
	f := h.w.files(Inputs{})
	h.inputs("f1", "l1", "k1", "borders")
	h.eventually("taken over", func() bool { return readFile(f.ManagedPath) == hyprHeader+" managed f1\n" })
	h.w.reloadCh <- ipc.Reload{}
	h.eventually("loaded", func() bool { return h.status() == "loaded" })
	h.m.AllowTakeover()
	h.eventually("approved", h.approved)
	// The approval is saved before Allow's apply runs: given back only
	// once that's done, or the approved claim adopts it
	h.m.do(context.Background(), func(context.Context) {})
	os.WriteFile(f.ManagedPath, []byte("-- mine again\n"), 0o644)
	// A live change: evaluated, then the file synced after 2 s (inside
	// testkit.Eventually's 10, which CI stretches)
	h.inputs("f1", "l2", "k1", "borders")
	h.eventually("asked again", func() bool { return h.state("takeoverPending") == true })
	if readFile(f.ManagedPath) != "-- mine again\n" || h.approved() {
		t.Fatal("written over, or the approval kept")
	}
}

// While the mode isn't known (config.json didn't load at the start) a
// managed config or an include of axiom's is never touched: a managed
// config in place is never given back, whether the runtime file remembers
// managed or not (gone after a reboot), and the mode applied stays; once
// the file is fixed, its mode applies
func TestAnUnknownModeKeepsWhatsAxioms(t *testing.T) {
	t.Parallel()
	for _, c := range []struct {
		name, applied string
		managedFile   bool
		included      bool
		// managedLoaded: the managed config is in effect (its module
		// emptied, as managed mode leaves it)
		managedLoaded bool
	}{
		{"applied managed", "managed", true, false, false},
		{"applied managed, loaded", "managed", true, false, true},
		{"managed config, nothing applied", "", true, false, false},
		{"include loaded", "included", false, true, false},
		{"include loaded, nothing applied", "", false, true, false},
	} {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			h := newHarness(t, "")
			h.m.st.AppliedMode = c.applied
			h.w.loaded = c.included || c.managedLoaded
			f := h.w.files(Inputs{})
			os.MkdirAll(f.UserDir, 0o755)
			if c.included {
				os.MkdirAll(filepath.Dir(f.IncludePath), 0o755)
				os.WriteFile(f.IncludePath, []byte("-- module f0\n"), 0o644)
			}
			managed := ""
			if c.managedFile {
				managed = hyprHeader + " managed f0\n"
				os.WriteFile(f.ManagedPath, []byte(managed), 0o644)
			}
			h.inputs("f1", "l1", "k1", "borders")
			h.w.reloadCh <- ipc.Reload{}
			time.Sleep(600 * time.Millisecond)
			// A live change applies nothing either
			h.inputs("f1", "l2", "k1", "borders")
			time.Sleep(600 * time.Millisecond)
			// Only a runtime layer comes off while axiom's file is loaded
			for _, call := range h.w.seen() {
				if call != "clear" || !(c.included || c.managedLoaded) {
					t.Fatalf("changed the compositor's config: %v", h.w.seen())
				}
			}
			if (c.included || c.managedLoaded) && !slices.Contains(h.w.seen(), "clear") {
				t.Fatalf("the runtime layer stayed over axiom's loaded file: %v", h.w.seen())
			}
			if readFile(f.ManagedPath) != managed {
				t.Fatalf("changed the managed config: %q", readFile(f.ManagedPath))
			}
			if h.status() != "pending" || h.m.st.AppliedMode != c.applied {
				t.Fatalf("status %s, applied %q", h.status(), h.m.st.AppliedMode)
			}
			if c.managedFile {
				h.setMode("managed")
				h.eventually("the managed config rewritten", func() bool { return readFile(f.ManagedPath) == hyprHeader+" managed f1\n" })
			}
		})
	}
}

// Leaving the hold (config.json, not JSON at the start with no takeovers
// kept, fixed by hand), the mode read applies: managed applied and in
// place stays, detached gives it back
func TestLeavingTheHoldTakesTheModeRead(t *testing.T) {
	t.Parallel()
	for _, mode := range []string{"managed", "detached"} {
		t.Run(mode, func(t *testing.T) {
			t.Parallel()
			h := newHarness(t, "")
			h.m.st.AppliedMode = "managed"
			f := h.w.files(Inputs{})
			os.MkdirAll(f.UserDir, 0o755)
			os.WriteFile(f.ManagedPath, []byte(hyprHeader+" managed f1\n"), 0o644)
			h.m.approve()
			h.inputs("f1", "l1", "k1")
			h.eventually("live", func() bool { return h.state("live") == true })
			h.changeMode(mode, true)
			h.eventually("the mode taken", func() bool { return h.state("mode") == mode })
			if mode == "detached" {
				h.eventually("given back", func() bool { return readFile(f.ManagedPath) == "-- given back\n" })
				return
			}
			time.Sleep(600 * time.Millisecond)
			if readFile(f.ManagedPath) != hyprHeader+" managed f1\n" {
				t.Fatalf("changed the managed config: %q", readFile(f.ManagedPath))
			}
		})
	}
}

// While the mode isn't known and nothing of axiom's is in the compositor's
// config, the defaults' runtime layer applies, again after a reload drops
// it, and the mode applied stays. Managed applied with no managed config in
// place (the takeover awaiting approval, blocked or failed) gets it too, as
// outside the hold, and nothing is claimed
func TestAnUnknownModeAppliesTheDefaultsLayer(t *testing.T) {
	t.Parallel()
	for _, applied := range []string{"", "detached", "managed"} {
		t.Run("applied "+applied, func(t *testing.T) {
			t.Parallel()
			h := newHarness(t, "")
			h.m.st.AppliedMode = applied
			h.inputs("f1", "l1", "k1")
			h.eventually("the runtime layer", h.called("runtime:live l1"))
			h.w.reloadCh <- ipc.Reload{}
			h.eventually("again after a reload", func() bool {
				n := 0
				for _, c := range h.w.seen() {
					if c == "runtime:live l1" {
						n++
					}
				}
				return n >= 2
			})
			h.inputs("f1", "l2", "k1")
			h.eventually("a live change", h.called("live:live l2"))
			f := h.w.files(Inputs{})
			if readFile(f.ManagedPath) != "" || readFile(f.IncludePath) != "" || h.m.st.AppliedMode != applied {
				t.Fatalf("set up a mode: applied %q", h.m.st.AppliedMode)
			}
			if h.status() != "pending" {
				t.Fatalf("status %s", h.status())
			}
		})
	}
}

// managed read from the file (one that didn't load at the start, fixed from
// outside) has no card open: the notification asks for the approval, which
// it never is itself; the shell's save doesn't notify (the card asks)
func TestManagedFromTheFileNotifies(t *testing.T) {
	t.Parallel()
	for _, fromFile := range []bool{true, false} {
		t.Run(fmt.Sprintf("from file %v", fromFile), func(t *testing.T) {
			t.Parallel()
			h := newHarness(t, "")
			f := h.w.files(Inputs{})
			os.MkdirAll(f.ConfigDir, 0o755)
			os.WriteFile(f.ManagedPath, []byte("-- mine\n"), 0o644)
			h.inputs("f1", "l1", "k1")
			h.eventually("live", func() bool { return h.state("live") == true })
			h.changeMode("managed", fromFile)
			h.eventually("the takeover pending", func() bool { return h.state("takeoverPending") == true })
			notified := false
			for len(h.pushes) > 0 {
				if strings.Contains(<-h.pushes, `"approval"`) {
					notified = true
				}
			}
			if notified != fromFile {
				t.Fatalf("notified %v", notified)
			}
			if readFile(f.ManagedPath) != "-- mine\n" || h.approved() {
				t.Fatal("taken over without the approval")
			}
		})
	}
}

// Leaving included between sessions (the mode applied last is known only
// within one compositor run): the module left loading is emptied anyway
func TestAModuleLeftFromAnEarlierSessionIsEmptied(t *testing.T) {
	t.Parallel()
	h := newHarness(t, "detached")
	path := h.w.files(Inputs{}).IncludePath
	os.MkdirAll(filepath.Dir(path), 0o755)
	os.WriteFile(path, []byte("-- module f0\n"), 0o644)
	h.inputs("f1", "l1", "k1")
	h.eventually("emptied", func() bool { return readFile(path) == "-- empty\n" })
}

// A takeover that fails (the config dir can't be locked): the runtime
// layer stands in, and the card says why
func TestAFailedTakeoverAppliesTheRuntimeLayer(t *testing.T) {
	t.Parallel()
	h := newHarness(t, "managed")
	if err := h.m.approvals().add("hyprland"); err != nil {
		t.Fatal(err)
	}
	f := h.w.files(Inputs{})
	os.WriteFile(strings.TrimSuffix(f.ConfigDir, "/"), []byte("not a dir"), 0o644)
	h.inputs("f1", "l1", "k1")
	h.eventually("the runtime layer", h.called("runtime:live l1"))
	if p := jsonx.ToString(h.state("problem")); !strings.HasPrefix(p, "Couldn't take over") {
		t.Fatalf("problem %q", p)
	}
}

// A takeover check that fails leaves no answer behind: a stale one could
// let a claim adopt the user's config without their Allow
func TestAFailedTakeoverCheckForgetsTheLastAnswer(t *testing.T) {
	t.Parallel()
	h := newHarness(t, "managed")
	f := h.w.files(Inputs{})
	os.WriteFile(strings.TrimSuffix(f.ConfigDir, "/"), []byte("not a dir"), 0o644)
	h.m.do(context.Background(), func(ctx context.Context) {
		h.m.managedCheck = "new"
		h.m.check(ctx)
	})
	if got := h.state("managedCheck"); got != "" {
		t.Fatalf("managedCheck %v after a failed check", got)
	}
}

// niri's state as its event stream starts can come after the first apply
// (the stream connects on its own): a config niri couldn't load at its
// start is said then, and the module the apply found reads as not loaded
func TestNiriFailedAtItsStartIsSaidAfterTheFirstApply(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	env := map[string]string{"NIRI_SOCKET": filepath.Join(dir, "niri.sock"), "XDG_RUNTIME_DIR": dir}
	m := New(Options{
		Getenv:      func(k string) string { return env[k] },
		StateDir:    filepath.Join(dir, "state"),
		RuntimeFile: filepath.Join(dir, "run", "compositor.json"),
		Log:         slog.New(slog.NewTextHandler(io.Discard, nil)),
	})
	m.in = Inputs{jsonx.Obj("kind", "niri")}
	m.mode, m.loaded = "included", true
	// A later stream's state that didn't fail changes nothing
	m.configReloaded(context.Background(), ipc.Reload{Initial: true})
	if !m.loaded || m.problem != "" {
		t.Fatalf("loaded %v, problem %q after a state that didn't fail", m.loaded, m.problem)
	}
	m.configReloaded(context.Background(), ipc.Reload{Initial: true, Failed: true})
	if want := m.w.problems(m.in).Failed; m.loaded || m.problem != want {
		t.Fatalf("loaded %v, problem %q; want the failure said", m.loaded, m.problem)
	}
}

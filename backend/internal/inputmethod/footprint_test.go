package inputmethod

import (
	"context"
	"encoding/json"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/dbus/dbustest"
	"github.com/axiom-shell/axiom/backend/internal/footprint"
	"github.com/axiom-shell/axiom/backend/internal/xdg"
)

// ledgerFor is a ledger in a scratch state folder, reading and setting the
// harness's fake gsettings; fcitx5's undo goes over the session bus
func ledgerFor(t *testing.T, h *harness, session *dbustest.Bus) *footprint.Ledger {
	t.Helper()
	root := t.TempDir()
	l := footprint.New(footprint.Options{
		Dirs: xdg.Resolve(func(k string) string {
			return map[string]string{"HOME": root, "XDG_STATE_HOME": filepath.Join(root, "s"), "XDG_CONFIG_HOME": filepath.Join(root, "c"), "XDG_CACHE_HOME": filepath.Join(root, "ca")}[k]
		}),
		GSettings: func(_ context.Context, args ...string) (string, error) {
			h.mu.Lock()
			defer h.mu.Unlock()
			switch args[0] {
			case "get":
				return h.stored[args[1]+" "+args[2]] + "\n", nil
			case "set":
				h.stored[args[1]+" "+args[2]] = args[3]
			}
			return "", nil
		},
	})
	RegisterUndo(l, func(ctx context.Context) (*dbus.Conn, error) { return dbus.Dial(ctx, session.Address, dbus.Options{}) })
	return l
}

func TestIbusSettingRecordsPrior(t *testing.T) {
	t.Parallel()
	session, private := dbustest.New(t), dbustest.New(t)
	newFakeIBus(t, private)
	var l *footprint.Ledger
	h := startWith(t, session, func() string { return private.Address }, func(o *Options) {
		l = ledgerFor(t, &harness{stored: map[string]string{ibusGeneral + " preload-engines": "['xkb:us::eng']"}}, session)
		o.Ledger = l
	})
	h.await(t, "ibus is followed", func(st State) bool { return st.Running })
	if err := h.s.Push(t.Context(), "us", []Item{{"xkb:us::eng", ""}, {"mozc-jp", ""}}, "Input.keyboard.method.enabled"); err != nil {
		t.Fatal(err)
	}
	font := "Sans 12"
	if err := h.s.Configure(t.Context(), Settings{CandidateFont: &font, Owner: "Input.keyboard.method.enabled"}); err != nil {
		t.Fatal(err)
	}
	rows := map[string]footprint.Row{}
	for _, r := range l.Rows() {
		rows[r.Target] = r
	}
	preload := rows[ibusGeneral+" preload-engines"]
	if preload.Kind != footprint.KindGSetting || !preload.System || preload.Owner != "Input.keyboard.method.enabled" ||
		!strings.Contains(string(preload.Prior), "['xkb:us::eng']") || string(preload.Wrote) != `"['xkb:us::eng', 'mozc-jp']"` {
		t.Errorf("preload-engines: %+v", preload)
	}
	if r := rows[ibusPanel+" custom-font"]; r.System || r.Kind != footprint.KindGSetting {
		t.Errorf("custom-font: %+v", r)
	}
}

func TestFcitxSetConfigRecordsPriorOptions(t *testing.T) {
	t.Parallel()
	bus := dbustest.New(t)
	f := newFakeFcitx(t, bus)
	f.mu.Lock()
	f.initial = map[string]map[string]dbus.Variant{
		fcitxGlobalConfig: {
			"Behavior": dbus.MakeVariant(map[string]dbus.Variant{"ShareInputState": dbus.MakeVariant("No"), "Other": dbus.MakeVariant("x")}),
			"Hotkey":   dbus.MakeVariant(map[string]dbus.Variant{"TriggerKeys": dbus.MakeVariant(map[string]dbus.Variant{"0": dbus.MakeVariant("Control+space")})}),
		},
	}
	f.mu.Unlock()
	var l *footprint.Ledger
	h := startWith(t, bus, nil, func(o *Options) {
		l = ledgerFor(t, &harness{stored: map[string]string{}}, bus)
		o.Ledger = l
	})
	h.await(t, "fcitx5 is followed", func(st State) bool { return st.Running })
	share, keys := "All", []string{}
	if err := h.s.Configure(t.Context(), Settings{ShareState: &share, TriggerKeys: &keys, Owner: "Input.keyboard.method.enabled"}); err != nil {
		t.Fatal(err)
	}
	if err := h.s.Push(t.Context(), "de", []Item{{"keyboard-de", ""}}, "Input.keyboard.method.enabled"); err != nil {
		t.Fatal(err)
	}
	rows := map[string]footprint.Row{}
	for _, r := range l.Rows() {
		rows[r.Kind+" "+r.Target] = r
	}
	cfg := rows["fcitx-config "+fcitxGlobalConfig]
	var prior map[string]any
	_ = json.Unmarshal(cfg.Prior, &prior)
	want := map[string]any{
		"Behavior": map[string]any{"ShareInputState": "No"},
		"Hotkey":   map[string]any{"TriggerKeys": map[string]any{"0": "Control+space"}},
	}
	if !reflect.DeepEqual(prior, want) {
		t.Errorf("prior %v, want %v", prior, want)
	}
	if g := rows["fcitx-group fcitx://group/Default"]; !g.System || g.Owner != "Input.keyboard.method.enabled" {
		t.Errorf("group row %+v", g)
	}
	// Undo puts fcitx5's options and group back
	res := l.Undo(t.Context(), l.Select(footprint.UndoOptions{IncludeSystem: true}), footprint.UndoOptions{})
	for _, r := range res {
		if r.Outcome != footprint.OutcomeDone {
			t.Errorf("%+v", r)
		}
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	if got := plain(f.configs[fcitxGlobalConfig]); !reflect.DeepEqual(got, want) {
		t.Errorf("fcitx5 holds %v after undo, want %v", got, want)
	}
	if len(f.group) != 2 || f.group[0].Name != "keyboard-us" || f.defaultLayout != "us" {
		t.Errorf("group %+v %s", f.group, f.defaultLayout)
	}
}

func TestFcitxUndoNeedsRunning(t *testing.T) {
	t.Parallel()
	session := dbustest.New(t)
	l := ledgerFor(t, &harness{stored: map[string]string{}}, session)
	id, err := l.Begin(footprint.Row{Kind: footprint.KindFcitxConfig, Target: fcitxGlobalConfig, Owner: "x"}, footprint.PriorAbsent)
	if err != nil {
		t.Fatal(err)
	}
	l.Done(id, footprint.Raw(map[string]any{"Behavior": map[string]any{"ShareInputState": "All"}}))
	res := l.Undo(t.Context(), []string{id}, footprint.UndoOptions{})
	if res[0].Outcome != footprint.OutcomeNeedsRunning || len(l.Rows()) != 1 {
		t.Errorf("%+v %+v", res, l.Rows())
	}
}

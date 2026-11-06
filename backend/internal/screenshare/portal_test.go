package screenshare

import (
	"context"
	"sync"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/dbus/dbustest"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

// fakeNiri is niri's org.gnome.Mutter.ScreenCast: what was recorded,
// started and stopped.
type fakeNiri struct {
	mu       sync.Mutex
	recorded []string // "monitor DP-1", "window 7"
	cursor   []uint32
	stopped  int
}

func (f *fakeNiri) serve(t *testing.T, bus *dbustest.Bus) {
	t.Helper()
	conn := dial(t, bus)
	stream := dbus.ObjectPath("/org/gnome/Mutter/ScreenCast/Stream/u1")
	session := dbus.ObjectPath("/org/gnome/Mutter/ScreenCast/Session/u1")
	record := func(what string, props map[string]dbus.Variant) {
		f.mu.Lock()
		defer f.mu.Unlock()
		f.recorded = append(f.recorded, what)
		c, _ := props["cursor-mode"].Value.(uint32)
		f.cursor = append(f.cursor, c)
	}
	export(t, conn, mutterPath, dbus.Interface{Name: ifaceMutter, Methods: map[string]dbus.Method{
		"CreateSession": {In: "a{sv}", Out: "o", Fn: func(context.Context, *dbus.Message) ([]any, error) { return []any{session}, nil }},
	}})
	export(t, conn, session, dbus.Interface{Name: ifaceMSession, Methods: map[string]dbus.Method{
		"RecordMonitor": {In: "sa{sv}", Out: "o", Fn: func(_ context.Context, m *dbus.Message) ([]any, error) {
			var name string
			var props map[string]dbus.Variant
			m.Store(&name, &props)
			record("monitor "+name, props)
			return []any{stream}, nil
		}},
		"RecordWindow": {In: "a{sv}", Out: "o", Fn: func(_ context.Context, m *dbus.Message) ([]any, error) {
			var props map[string]dbus.Variant
			m.Store(&props)
			id, _ := props["window-id"].Value.(uint64)
			record("window "+itoa(id), props)
			return []any{stream}, nil
		}},
		"Start": {Fn: func(context.Context, *dbus.Message) ([]any, error) {
			go conn.Emit(stream, ifaceMStream, "PipeWireStreamAdded", "u", uint32(42))
			return nil, nil
		}},
		"Stop": {Fn: func(context.Context, *dbus.Message) ([]any, error) {
			f.mu.Lock()
			f.stopped++
			f.mu.Unlock()
			return nil, nil
		}},
	}})
	export(t, conn, stream, dbus.Interface{Name: ifaceProps, Methods: map[string]dbus.Method{
		"Get": {In: "ss", Out: "v", Fn: func(context.Context, *dbus.Message) ([]any, error) {
			return []any{dbus.MakeVariant(map[string]dbus.Variant{"size": {Sig: "(ii)", Value: []any{int32(2560), int32(1440)}}})}, nil
		}},
	}})
	if _, err := conn.RequestName(context.Background(), mutterBusName, dbus.NameDoNotQueue); err != nil {
		t.Fatal(err)
	}
}

func itoa(n uint64) string {
	if n == 0 {
		return "0"
	}
	var b []byte
	for ; n > 0; n /= 10 {
		b = append([]byte{byte('0' + n%10)}, b...)
	}
	return string(b)
}

func dial(t *testing.T, bus *dbustest.Bus) *dbus.Conn {
	t.Helper()
	conn, err := dbus.Dial(context.Background(), bus.Address, dbus.Options{})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { conn.Close() })
	return conn
}

func export(t *testing.T, conn *dbus.Conn, path dbus.ObjectPath, iface dbus.Interface) {
	t.Helper()
	if _, err := conn.Export(path, iface); err != nil {
		t.Fatal(err)
	}
}

type portalSetup struct {
	bus      *dbustest.Bus
	frontend *dbus.Conn
	niri     *fakeNiri
	asked    chan Request
	answer   chan *Choice
	settings Settings
}

func startPortal(t *testing.T, settings Settings) *portalSetup {
	t.Helper()
	s := &portalSetup{bus: dbustest.New(t), niri: &fakeNiri{}, asked: make(chan Request, 4), answer: make(chan *Choice, 4), settings: settings}
	s.niri.serve(t, s.bus)
	p := NewPortal(PortalOptions{
		Ask: func(ctx context.Context, r Request) (*Choice, error) {
			s.asked <- r
			select {
			case c := <-s.answer:
				return c, nil
			case <-ctx.Done():
				return nil, ctx.Err()
			}
		},
		Settings: func() Settings { return s.settings },
		Sources: func(context.Context) ([]Output, []Window, error) {
			return []Output{{Name: "DP-1"}}, []Window{{Token: "7", ID: "7", Title: "Terminal", AppID: "kitty"}}, nil
		},
	})
	conn := dial(t, s.bus)
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() { p.Run(ctx, conn); close(done) }()
	t.Cleanup(func() { cancel(); <-done })
	if !testkit.Eventually(func() bool { return s.bus.Owner(PortalBusName) != "" }) {
		t.Fatal("the portal didn't take its name")
	}
	s.frontend = dial(t, s.bus)
	return s
}

const (
	testHandle  = dbus.ObjectPath("/org/freedesktop/portal/desktop/request/1_1/t")
	testSession = dbus.ObjectPath("/org/freedesktop/portal/desktop/session/1_1/s")
)

// call calls the portal as the frontend does: its response and results.
func (s *portalSetup) call(t *testing.T, member string, options map[string]dbus.Variant) (uint32, map[string]dbus.Variant) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), testkit.Bound(5*time.Second))
	defer cancel()
	var m *dbus.Message
	var err error
	if member == "Start" {
		m, err = s.frontend.Call(ctx, PortalBusName, portalPath, ifaceScreenCast, member, "oossa{sv}", testHandle, testSession, "com.discordapp.Discord", "", options)
	} else {
		m, err = s.frontend.Call(ctx, PortalBusName, portalPath, ifaceScreenCast, member, "oosa{sv}", testHandle, testSession, "com.discordapp.Discord", options)
	}
	if err != nil {
		t.Fatalf("%s: %v", member, err)
	}
	defer m.Close()
	var code uint32
	var results map[string]dbus.Variant
	if err := m.Store(&code, &results); err != nil {
		t.Fatal(err)
	}
	return code, results
}

// callAsync is call on a goroutine, for a pick to answer meanwhile.
func (s *portalSetup) callAsync(t *testing.T, member string, options map[string]dbus.Variant) chan uint32 {
	ch := make(chan uint32, 1)
	go func() {
		code, _ := s.call(t, member, options)
		ch <- code
	}()
	return ch
}

func (s *portalSetup) pick(t *testing.T, c *Choice) Request {
	t.Helper()
	select {
	case r := <-s.asked:
		s.answer <- c
		return r
	case <-time.After(testkit.Bound(5 * time.Second)):
		t.Fatal("the portal didn't ask")
		return Request{}
	}
}

func streamOf(t *testing.T, results map[string]dbus.Variant) (uint32, map[string]dbus.Variant) {
	t.Helper()
	streams, ok := results["streams"].Value.([]any)
	if !ok || len(streams) != 1 {
		t.Fatalf("streams: %+v", results)
	}
	stream := streams[0].([]any)
	return stream[0].(uint32), stream[1].(map[string]dbus.Variant)
}

func TestPortalProperties(t *testing.T) {
	t.Parallel()
	s := startPortal(t, Settings{Enabled: true})
	ctx := context.Background()
	all, err := s.frontend.GetAll(ctx, PortalBusName, portalPath, ifaceScreenCast)
	if err != nil {
		t.Fatal(err)
	}
	if all["AvailableSourceTypes"].Value != sourceMonitor|sourceWindow || all["AvailableCursorModes"].Value != cursorHidden|cursorEmbedded || all["version"].Value != portalVersion {
		t.Errorf("got %+v", all)
	}
}

func TestPortalMonitor(t *testing.T) {
	t.Parallel()
	s := startPortal(t, Settings{Enabled: true, Remember: true})
	if code, _ := s.call(t, "CreateSession", map[string]dbus.Variant{}); code != responseOK {
		t.Fatalf("CreateSession: %d", code)
	}
	done := s.callAsync(t, "SelectSources", map[string]dbus.Variant{
		"types": dbus.MakeVariant(sourceMonitor | sourceWindow), "cursor_mode": dbus.MakeVariant(cursorEmbedded), "persist_mode": dbus.MakeVariant(uint32(2)),
	})
	r := s.pick(t, &Choice{Kind: KindScreen, Output: "DP-1"})
	if r.Backend != BackendNiri || r.AppID != "com.discordapp.Discord" || len(r.Outputs) != 1 || len(r.Windows) != 1 {
		t.Errorf("asked %+v", r)
	}
	if code := <-done; code != responseOK {
		t.Fatalf("SelectSources: %d", code)
	}
	code, results := s.call(t, "Start", map[string]dbus.Variant{})
	if code != responseOK {
		t.Fatalf("Start: %d", code)
	}
	node, props := streamOf(t, results)
	if node != 42 || props["source_type"].Value != sourceMonitor {
		t.Errorf("stream %d %+v", node, props)
	}
	if size, _ := props["size"].Value.([]any); len(size) != 2 || size[0] != int32(2560) {
		t.Errorf("size %+v", props["size"])
	}
	if results["persist_mode"].Value != uint32(2) || results["restore_data"].Sig != "(suv)" {
		t.Errorf("not kept: %+v", results)
	}
	s.niri.mu.Lock()
	if len(s.niri.recorded) != 1 || s.niri.recorded[0] != "monitor DP-1" || s.niri.cursor[0] != 1 {
		t.Errorf("niri recorded %v (cursor %v)", s.niri.recorded, s.niri.cursor)
	}
	s.niri.mu.Unlock()

	// The frontend closes the session: niri stops casting
	ctx := context.Background()
	if _, err := s.frontend.Call(ctx, PortalBusName, testSession, ifaceSession, "Close", ""); err != nil {
		t.Fatal(err)
	}
	if !testkit.Eventually(func() bool { s.niri.mu.Lock(); defer s.niri.mu.Unlock(); return s.niri.stopped == 1 }) {
		t.Error("niri wasn't told to stop")
	}

	// The restore data picks again without asking
	restore := results["restore_data"]
	if code, _ := s.call(t, "CreateSession", map[string]dbus.Variant{}); code != responseOK {
		t.Fatal(code)
	}
	if code, _ := s.call(t, "SelectSources", map[string]dbus.Variant{"restore_data": restore}); code != responseOK {
		t.Fatal(code)
	}
	select {
	case r := <-s.asked:
		t.Fatalf("asked again: %+v", r)
	default:
	}
}

func TestPortalWindowNotKept(t *testing.T) {
	t.Parallel()
	s := startPortal(t, Settings{Enabled: true, Remember: false})
	s.call(t, "CreateSession", map[string]dbus.Variant{})
	done := s.callAsync(t, "SelectSources", map[string]dbus.Variant{"types": dbus.MakeVariant(sourceWindow), "persist_mode": dbus.MakeVariant(uint32(2))})
	if r := s.pick(t, &Choice{Kind: KindWindow, Window: "7"}); len(r.Outputs) != 0 {
		t.Errorf("monitors offered for windows only: %+v", r)
	}
	<-done
	code, results := s.call(t, "Start", map[string]dbus.Variant{})
	if code != responseOK {
		t.Fatal(code)
	}
	if _, props := streamOf(t, results); props["source_type"].Value != sourceWindow {
		t.Errorf("%+v", props)
	}
	if _, ok := results["restore_data"]; ok {
		t.Error("kept with Remember off")
	}
	s.niri.mu.Lock()
	defer s.niri.mu.Unlock()
	if len(s.niri.recorded) != 1 || s.niri.recorded[0] != "window 7" {
		t.Errorf("niri recorded %v", s.niri.recorded)
	}
}

func TestPortalCancel(t *testing.T) {
	t.Parallel()
	s := startPortal(t, Settings{Enabled: true})
	s.call(t, "CreateSession", map[string]dbus.Variant{})
	done := s.callAsync(t, "SelectSources", map[string]dbus.Variant{})
	s.pick(t, nil)
	if code := <-done; code != responseCancelled {
		t.Fatalf("got %d", code)
	}
	if code, _ := s.call(t, "Start", map[string]dbus.Variant{}); code != responseOther {
		t.Errorf("Start with nothing picked: %d", code)
	}
}

// The frontend closing a request ends its pick
func TestPortalRequestClosed(t *testing.T) {
	t.Parallel()
	s := startPortal(t, Settings{Enabled: true})
	s.call(t, "CreateSession", map[string]dbus.Variant{})
	done := s.callAsync(t, "SelectSources", map[string]dbus.Variant{})
	select {
	case <-s.asked:
	case <-time.After(testkit.Bound(5 * time.Second)):
		t.Fatal("not asked")
	}
	if _, err := s.frontend.Call(context.Background(), PortalBusName, testHandle, ifaceRequest, "Close", ""); err != nil {
		t.Fatal(err)
	}
	select {
	case code := <-done:
		if code == responseOK {
			t.Errorf("got %d", code)
		}
	case <-time.After(testkit.Bound(5 * time.Second)):
		t.Fatal("the pick didn't end")
	}
}

// With axiom's picker off, sessions go on to xdg-desktop-portal-gnome
func TestPortalForwards(t *testing.T) {
	t.Parallel()
	s := startPortal(t, Settings{Enabled: false})
	gnome := dial(t, s.bus)
	var mu sync.Mutex
	var calls []string
	relayed := func(member string) dbus.Method {
		in := "oosa{sv}"
		if member == "Start" {
			in = "oossa{sv}"
		}
		return dbus.Method{In: in, Out: "ua{sv}", Fn: func(_ context.Context, m *dbus.Message) ([]any, error) {
			mu.Lock()
			calls = append(calls, member)
			mu.Unlock()
			return []any{uint32(0), map[string]dbus.Variant{"from": dbus.MakeVariant("gnome")}}, nil
		}}
	}
	export(t, gnome, portalPath, dbus.Interface{Name: ifaceScreenCast, Methods: map[string]dbus.Method{
		"CreateSession": relayed("CreateSession"), "SelectSources": relayed("SelectSources"), "Start": relayed("Start"),
	}})
	export(t, gnome, testSession, dbus.Interface{Name: ifaceSession, Methods: map[string]dbus.Method{
		"Close": {Fn: func(context.Context, *dbus.Message) ([]any, error) {
			mu.Lock()
			calls = append(calls, "Close")
			mu.Unlock()
			return nil, nil
		}},
	}})
	if _, err := gnome.RequestName(context.Background(), gnomeBusName, dbus.NameDoNotQueue); err != nil {
		t.Fatal(err)
	}
	for _, member := range []string{"CreateSession", "SelectSources", "Start"} {
		code, results := s.call(t, member, map[string]dbus.Variant{})
		if code != responseOK || results["from"].Value != "gnome" {
			t.Fatalf("%s: %d %+v", member, code, results)
		}
	}
	if _, err := s.frontend.Call(context.Background(), PortalBusName, testSession, ifaceSession, "Close", ""); err != nil {
		t.Fatal(err)
	}
	if !testkit.Eventually(func() bool { mu.Lock(); defer mu.Unlock(); return len(calls) == 4 }) {
		t.Fatalf("relayed %v", calls)
	}
	select {
	case r := <-s.asked:
		t.Errorf("axiom's picker asked: %+v", r)
	default:
	}
}

func TestRestored(t *testing.T) {
	t.Parallel()
	r := Request{Outputs: []Output{{Name: "DP-1"}}, Windows: []Window{{Token: "7", AppID: "kitty", Title: "a"}, {Token: "8", AppID: "kitty", Title: "b"}, {Token: "9", AppID: "foot", Title: "c"}}}
	data := func(fields map[string]dbus.Variant) dbus.Variant {
		return dbus.Variant{Sig: "(suv)", Value: []any{restoreVendor, restoreVersion, dbus.MakeVariant(fields)}}
	}
	str := func(s string) dbus.Variant { return dbus.MakeVariant(s) }
	cases := []struct {
		name string
		v    dbus.Variant
		want *Choice
	}{
		{"an output", data(map[string]dbus.Variant{"output": str("DP-1")}), &Choice{Kind: KindScreen, Output: "DP-1"}},
		{"an output gone", data(map[string]dbus.Variant{"output": str("HDMI-A-1")}), nil},
		{"a window by title", data(map[string]dbus.Variant{"appId": str("kitty"), "title": str("b")}), &Choice{Kind: KindWindow, Window: "8"}},
		{"the app's only window", data(map[string]dbus.Variant{"appId": str("foot"), "title": str("renamed")}), &Choice{Kind: KindWindow, Window: "9"}},
		{"one of several", data(map[string]dbus.Variant{"appId": str("kitty"), "title": str("renamed")}), nil},
		{"another vendor", dbus.Variant{Sig: "(suv)", Value: []any{"GNOME", uint32(1), dbus.MakeVariant(map[string]dbus.Variant{"output": str("DP-1")})}}, nil},
		{"none", dbus.Variant{}, nil},
	}
	for _, tc := range cases {
		got := restored(tc.v, r)
		if (got == nil) != (tc.want == nil) || got != nil && *got != *tc.want {
			t.Errorf("%s: got %+v, want %+v", tc.name, got, tc.want)
		}
	}
}

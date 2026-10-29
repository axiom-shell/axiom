package filepicker

import (
	"context"
	"errors"
	"os/exec"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/dbus/dbustest"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

func testCtx(t *testing.T) context.Context {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	t.Cleanup(cancel)
	return ctx
}

func dial(t *testing.T, bus *dbustest.Bus) *dbus.Conn {
	t.Helper()
	conn, err := dbus.Dial(testCtx(t), bus.Address, dbus.Options{})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { conn.Close() })
	return conn
}

// fakePortal is a FileChooser on the bus: it answers each OpenFile at
// once with code and uris (or not at all, when wait), on the request path
// handle_token names, or on a path of its own when oldPaths.
type fakePortal struct {
	version  uint32
	code     uint32
	uris     []string
	wait     bool
	oldPaths bool

	mu      sync.Mutex
	options map[string]dbus.Variant
	closed  chan dbus.ObjectPath
}

func (f *fakePortal) serve(t *testing.T, bus *dbustest.Bus) {
	t.Helper()
	f.closed = make(chan dbus.ObjectPath, 1)
	conn := dial(t, bus)
	if _, err := conn.RequestName(testCtx(t), portalName, dbus.NameDoNotQueue); err != nil {
		t.Fatal(err)
	}
	export := func(path dbus.ObjectPath, iface string, methods map[string]dbus.Method) {
		if _, err := conn.Export(path, dbus.Interface{Name: iface, Methods: methods}); err != nil {
			t.Fatal(err)
		}
	}
	export(portalPath, "org.freedesktop.DBus.Properties", map[string]dbus.Method{
		"Get": {In: "ss", Out: "v", Fn: func(context.Context, *dbus.Message) ([]any, error) {
			return []any{dbus.MakeVariant(f.version)}, nil
		}},
	})
	export(portalPath, chooserIface, map[string]dbus.Method{
		"OpenFile": {In: "ssa{sv}", Out: "o", Fn: func(_ context.Context, m *dbus.Message) ([]any, error) {
			options := m.Body[2].(map[string]dbus.Variant)
			f.mu.Lock()
			f.options = options
			f.mu.Unlock()
			handle := dbus.ObjectPath(requestPrefix + strings.ReplaceAll(m.Sender[1:], ".", "_") + "/" + options["handle_token"].Value.(string))
			if f.oldPaths {
				handle = requestPrefix + "old/1"
			}
			export(handle, requestIface, map[string]dbus.Method{
				"Close": {Fn: func(context.Context, *dbus.Message) ([]any, error) {
					f.closed <- handle
					return nil, nil
				}},
			})
			if !f.wait {
				// Before the reply, as a quick portal may: the client
				// subscribed first
				results := map[string]dbus.Variant{"uris": dbus.MakeVariant(f.uris)}
				if err := conn.Emit(handle, requestIface, "Response", "ua{sv}", f.code, results); err != nil {
					t.Error(err)
				}
			}
			return []any{handle}, nil
		}},
	})
}

func (f *fakePortal) sent() map[string]dbus.Variant {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.options
}

// fallbacks is a fake zenity or kdialog (whichever is installed) that
// records its argv and exits with code, printing out.
type fallbacks struct {
	installed []string
	code      int
	out       string
	ran       [][]string
}

func (fb *fallbacks) options(bus *dbustest.Bus, home string) Options {
	o := Options{
		LookPath: func(file string) (string, error) {
			if slices.Contains(fb.installed, file) {
				return "/usr/bin/" + file, nil
			}
			return "", exec.ErrNotFound
		},
		Run: func(_ context.Context, argv []string) (int, string, error) {
			fb.ran = append(fb.ran, argv)
			return fb.code, fb.out, nil
		},
		Home: home,
	}
	if bus != nil {
		o.SessionBus = func(ctx context.Context) (*dbus.Conn, error) { return dbus.Dial(ctx, bus.Address, dbus.Options{}) }
	}
	return o
}

func TestPortal(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name   string
		portal *fakePortal
		req    Request
		want   string
	}{
		{"a file", &fakePortal{version: 4, uris: []string{"file:///home/u/My%20Config.json"}}, Request{Title: "Import", Filter: "JSON:*.json"}, "/home/u/My Config.json"},
		{"a folder", &fakePortal{version: 3, uris: []string{"file:///home/u/Pictures"}}, Request{Title: "Pick", Folder: true, Filter: "JSON:*.json"}, "/home/u/Pictures"},
		{"cancelled", &fakePortal{version: 4, code: 1}, Request{Title: "Pick"}, ""},
		{"nothing chosen", &fakePortal{version: 4}, Request{Title: "Pick"}, ""},
		{"a portal older than handle_token", &fakePortal{version: 1, uris: []string{"file:///tmp/x"}, oldPaths: true}, Request{Title: "Pick"}, "/tmp/x"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			bus := dbustest.New(t)
			tc.portal.serve(t, bus)
			start := t.TempDir()
			tc.req.Start = start
			fb := &fallbacks{installed: []string{"zenity"}}
			got, err := Pick(testCtx(t), fb.options(bus, "/home/u"), tc.req)
			if err != nil || got != tc.want {
				t.Fatalf("Pick = %q, %v; want %q", got, err, tc.want)
			}
			if len(fb.ran) != 0 {
				t.Errorf("a fallback ran: %q", fb.ran)
			}
			sent := tc.portal.sent()
			if folder := sent["current_folder"].Value.([]byte); string(folder) != start+"\x00" {
				t.Errorf("current_folder = %q", folder)
			}
			_, directory := sent["directory"]
			_, filters := sent["filters"]
			if directory != tc.req.Folder || filters != (tc.req.Filter != "" && !tc.req.Folder) {
				t.Errorf("options = %v", sent)
			}
			if filters {
				want := []any{[]any{"JSON", []any{[]any{uint32(0), "*.json"}}}}
				if got := sent["filters"].Value; !equalAny(got, want) {
					t.Errorf("filters = %#v", got)
				}
			}
		})
	}
}

func equalAny(a, b any) bool {
	as, aok := a.([]any)
	bs, bok := b.([]any)
	if aok != bok {
		return false
	}
	if !aok {
		return a == b
	}
	return slices.EqualFunc(as, bs, equalAny)
}

// A pick nobody waits for any more closes the portal's picker.
func TestPortalClosedWhenAbandoned(t *testing.T) {
	t.Parallel()
	bus := dbustest.New(t)
	portal := &fakePortal{version: 4, wait: true}
	portal.serve(t, bus)
	ctx, cancel := context.WithCancel(testCtx(t))
	done := make(chan error, 1)
	go func() {
		_, err := Pick(ctx, (&fallbacks{}).options(bus, "/"), Request{Title: "Pick", Start: "/"})
		done <- err
	}()
	if !testkit.Eventually(func() bool { return portal.sent() != nil }) {
		t.Fatal("nothing sent to the portal")
	}
	cancel()
	if err := <-done; axerr.KindOf(err) != axerr.Unavailable {
		t.Fatalf("Pick = %v, want unavailable", err)
	}
	select {
	case <-portal.closed:
	case <-time.After(testkit.Bound(3 * time.Second)):
		t.Fatal("the request wasn't closed")
	}
}

// Without a portal that can show the picker, zenity, then kdialog.
func TestFallbacks(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name      string
		portal    *fakePortal // nil: none on the bus
		installed []string
		req       Request
		gone      bool // Start doesn't exist
		want      []string
	}{
		{"zenity, a folder", nil, []string{"zenity", "kdialog"}, Request{Title: "Pick", Folder: true}, false,
			[]string{"zenity", "--file-selection", "--title", "Pick", "--filename", "START/", "--directory"}},
		{"zenity, a filtered file", nil, []string{"zenity"}, Request{Title: "Pick", Filter: "JSON:*.json"}, false,
			[]string{"zenity", "--file-selection", "--title", "Pick", "--filename", "START/", "--file-filter", "JSON | *.json"}},
		{"kdialog, a folder", nil, []string{"kdialog"}, Request{Title: "Pick", Folder: true}, false,
			[]string{"kdialog", "--title", "Pick", "--getexistingdirectory", "START"}},
		{"kdialog, a bare glob", nil, []string{"kdialog"}, Request{Title: "Pick", Filter: "*.png"}, false,
			[]string{"kdialog", "--title", "Pick", "--getopenfilename", "START", "*.png"}},
		{"a start that's gone opens home", nil, []string{"kdialog"}, Request{Title: "Pick", Folder: true}, true,
			[]string{"kdialog", "--title", "Pick", "--getexistingdirectory", "HOME"}},
		{"a portal too old for folders", &fakePortal{version: 2}, []string{"zenity"}, Request{Title: "Pick", Folder: true}, false,
			[]string{"zenity", "--file-selection", "--title", "Pick", "--filename", "START/", "--directory"}},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			bus := dbustest.New(t)
			if tc.portal != nil {
				tc.portal.serve(t, bus)
			}
			start, home := t.TempDir(), t.TempDir()
			tc.req.Start = start
			if tc.gone {
				tc.req.Start = start + "/gone"
			}
			fb := &fallbacks{installed: tc.installed, out: "/picked/path\n"}
			got, err := Pick(testCtx(t), fb.options(bus, home), tc.req)
			if err != nil || got != "/picked/path" {
				t.Fatalf("Pick = %q, %v", got, err)
			}
			want := slices.Clone(tc.want)
			for i, a := range want {
				a = strings.ReplaceAll(a, "START", start)
				want[i] = strings.ReplaceAll(a, "HOME", home)
			}
			if len(fb.ran) != 1 || !slices.Equal(fb.ran[0], want) {
				t.Errorf("ran %q, want %q", fb.ran, want)
			}
		})
	}
}

func TestFallbackCancelledAndMissing(t *testing.T) {
	t.Parallel()
	cancelled := &fallbacks{installed: []string{"zenity"}, code: 1}
	if got, err := Pick(testCtx(t), cancelled.options(nil, "/"), Request{Title: "Pick", Start: "/"}); got != "" || err != nil {
		t.Errorf("cancelled: %q, %v", got, err)
	}
	_, err := Pick(testCtx(t), (&fallbacks{}).options(nil, "/"), Request{Title: "Pick", Start: "/"})
	if axerr.KindOf(err) != axerr.Unavailable {
		t.Errorf("no picker: %v, want unavailable", err)
	}
	failing := (&fallbacks{installed: []string{"zenity"}}).options(nil, "/")
	failing.Run = func(context.Context, []string) (int, string, error) { return 0, "", errors.New("boom") }
	if _, err := Pick(testCtx(t), failing, Request{Title: "Pick", Start: "/"}); err == nil {
		t.Error("a failed run isn't an error")
	}
}

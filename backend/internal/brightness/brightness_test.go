package brightness

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/dbus/dbustest"
	"github.com/axiom-shell/axiom/backend/internal/logind/logindtest"
)

func ctx(t *testing.T) context.Context {
	t.Helper()
	c, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	t.Cleanup(cancel)
	return c
}

// backlights writes each "name type brightness max" into a sysfs-like dir.
func backlights(t *testing.T, rows ...string) string {
	t.Helper()
	dir := t.TempDir()
	for _, r := range rows {
		f := strings.Fields(r)
		for i, file := range []string{"type", "brightness", "max_brightness"} {
			if err := os.MkdirAll(filepath.Join(dir, f[0]), 0o755); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(filepath.Join(dir, f[0], file), []byte(f[i+1]+"\n"), 0o644); err != nil {
				t.Fatal(err)
			}
		}
	}
	return dir
}

// fakeDDC answers ddcutil's commands from a table and records them.
type fakeDDC struct {
	mu      sync.Mutex
	answers map[string]string // args joined → stdout; missing: an error
	calls   []string
}

func (f *fakeDDC) run(_ context.Context, args ...string) ([]byte, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	key := strings.Join(args, " ")
	f.calls = append(f.calls, key)
	if out, ok := f.answers[key]; ok {
		return []byte(out), nil
	}
	return nil, errors.New("ddcutil failed")
}

const detectOutput = `Display 1
   I2C bus:          /dev/i2c-9
   DRM connector:    card1-DP-1
   Monitor:          DEL:DELL U2720Q:ABC

Invalid display
   I2C bus:          /dev/i2c-4
   DRM connector:    card1-eDP-1
   Monitor:          BOE::

Display 2
   I2C bus:          /dev/i2c-11
   DRM connector:    card0-HDMI-A-1
   Monitor:          GSM:LG:XYZ
`

func TestParseDetect(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name, text string
		want       []DDC
	}{
		{"none", "", []DDC{}},
		{"two, an invalid one between", detectOutput, []DDC{{9, "DP-1"}, {11, "HDMI-A-1"}}},
		{"no connector", "Display 1\n   I2C bus: /dev/i2c-3\n", []DDC{}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			if got := parseDetect(tc.text); !reflect.DeepEqual(got, tc.want) {
				t.Errorf("got %v, want %v", got, tc.want)
			}
		})
	}
}

func TestDetectPicksTheBacklight(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name string
		rows []string
		want *Backlight
	}{
		{"none", nil, nil},
		{"firmware over raw", []string{"intel_backlight raw 120 960", "acpi_video0 firmware 7 15"}, &Backlight{"acpi_video0", Level{7, 15}}},
		{"platform over raw", []string{"amdgpu_bl1 raw 40 255", "dell platform 3 9"}, &Backlight{"dell", Level{3, 9}}},
		{"an unreadable one left out", []string{"intel_backlight raw 120 960", "broken firmware x 15"}, &Backlight{"intel_backlight", Level{120, 960}}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			ddc := &fakeDDC{answers: map[string]string{"detect --terse": detectOutput}}
			s := New(Options{Dir: backlights(t, tc.rows...), Run: ddc.run})
			got := s.Detect(ctx(t))
			if !reflect.DeepEqual(got.Backlight, tc.want) {
				t.Errorf("backlight %+v, want %+v", got.Backlight, tc.want)
			}
			if len(got.DDC) != 2 {
				t.Errorf("ddc %v", got.DDC)
			}
		})
	}
}

func TestDetectWithoutDDC(t *testing.T) {
	t.Parallel()
	s := New(Options{Dir: t.TempDir(), Run: (&fakeDDC{}).run})
	got := s.Detect(ctx(t))
	if got.Backlight != nil || got.DDC == nil || len(got.DDC) != 0 {
		t.Errorf("got %+v", got)
	}
}

func TestGet(t *testing.T) {
	t.Parallel()
	ddc := &fakeDDC{answers: map[string]string{"--bus 9 getvcp 10 --terse": "VCP 10 C 35 100\n"}}
	s := New(Options{Dir: backlights(t, "intel_backlight raw 480 960"), Run: ddc.run})
	cases := []struct {
		name    string
		target  Target
		want    Level
		wantErr bool
	}{
		{"backlight", Target{Kind: KindBacklight, Device: "intel_backlight"}, Level{480, 960}, false},
		{"ddc", Target{Kind: KindDDC, Bus: 9}, Level{35, 100}, false},
		{"ddc failing", Target{Kind: KindDDC, Bus: 3}, Level{}, true},
		{"a missing backlight", Target{Kind: KindBacklight, Device: "gone"}, Level{}, true},
		{"a path for a device", Target{Kind: KindBacklight, Device: "../../etc"}, Level{}, true},
		{"an unknown kind", Target{Kind: "led"}, Level{}, true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			got, err := s.Get(ctx(t), tc.target)
			if (err != nil) != tc.wantErr || got != tc.want {
				t.Errorf("got %+v, %v", got, err)
			}
		})
	}
}

func TestSetDDC(t *testing.T) {
	t.Parallel()
	ddc := &fakeDDC{answers: map[string]string{"--bus 9 --noverify setvcp 10 60": ""}}
	s := New(Options{Run: ddc.run})
	if err := s.Set(ctx(t), Target{Kind: KindDDC, Bus: 9}, 60); err != nil {
		t.Fatal(err)
	}
	if err := s.Set(ctx(t), Target{Kind: KindDDC, Bus: 9}, -1); err == nil {
		t.Error("a negative value was set")
	}
	if !reflect.DeepEqual(ddc.calls, []string{"--bus 9 --noverify setvcp 10 60"}) {
		t.Errorf("calls %v", ddc.calls)
	}
}

func TestSetBacklightThroughLogind(t *testing.T) {
	t.Parallel()
	bus := dbustest.New(t)
	f := logindtest.New(t, bus)
	s := New(Options{
		SystemBus: func(ctx context.Context) (*dbus.Conn, error) {
			return dbus.Dial(ctx, bus.Address, dbus.Options{})
		},
		Getenv: logindtest.Getenv,
	})
	for _, v := range []int{300, 1} {
		if err := s.Set(ctx(t), Target{Kind: KindBacklight, Device: "intel_backlight"}, v); err != nil {
			t.Fatal(err)
		}
	}
	if err := s.Set(ctx(t), Target{Kind: KindBacklight, Device: "a/b"}, 5); err == nil {
		t.Error("set a path")
	}
	want := []string{"backlight intel_backlight 300", "backlight intel_backlight 1"}
	if got := f.Brightness(); !reflect.DeepEqual(got, want) {
		t.Errorf("logind got %v, want %v", got, want)
	}
}

func TestSetBacklightWithoutLogind(t *testing.T) {
	t.Parallel()
	s := New(Options{SystemBus: func(context.Context) (*dbus.Conn, error) { return nil, errors.New("no bus") }})
	if err := s.Set(ctx(t), Target{Kind: KindBacklight, Device: "intel_backlight"}, 5); err == nil {
		t.Error("set without a bus")
	}
}

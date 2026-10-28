package ipc

import (
	"bufio"
	"context"
	"io"
	"net"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/compositor/render"
)

// Each compositor's output list as the neutral outputs, from replies
// recorded from a running compositor (testdata: swaymsg -t get_outputs -r
// on a nested sway with WL-2 disabled in its config, niri msg -j outputs,
// hyprctl -j monitors all on a nested Hyprland) and inline ones for what
// those don't hold
func TestOutputs(t *testing.T) {
	t.Parallel()
	fixture := func(name string) string {
		data, err := os.ReadFile(filepath.Join("testdata", name))
		if err != nil {
			t.Fatal(err)
		}
		return strings.TrimSpace(string(data))
	}
	type read func(ctx context.Context, dir string) ([]render.Output, error)
	sway := func(reply string) read {
		return func(ctx context.Context, dir string) ([]render.Output, error) {
			path := filepath.Join(dir, "sway.sock")
			listen(t, path, func(c net.Conn) {
				if kind, _, err := swayRead(c); err == nil && kind == swayGetOutputs {
					swayReply(c, kind, reply)
				}
			})
			return (&Sway{Path: path}).Outputs(ctx)
		}
	}
	niri := func(reply string) read {
		return func(ctx context.Context, dir string) ([]render.Output, error) {
			path := filepath.Join(dir, "niri.sock")
			listen(t, path, func(c net.Conn) {
				if line, _ := bufio.NewReader(c).ReadString('\n'); line == "\"Outputs\"\n" {
					io.WriteString(c, `{"Ok":{"Outputs":`+reply+"}}\n")
				}
			})
			return (&Niri{Path: path}).Outputs(ctx)
		}
	}
	hypr := func(reply string) read {
		return func(ctx context.Context, dir string) ([]render.Output, error) {
			listen(t, filepath.Join(dir, ".socket.sock"), func(c net.Conn) {
				buf := make([]byte, 64)
				if n, _ := c.Read(buf); string(buf[:n]) == "j/monitors all" {
					io.WriteString(c, reply)
				}
			})
			return (&Hypr{Dir: dir}).Outputs(ctx)
		}
	}
	tests := []struct {
		name string
		read read
		want []render.Output
	}{
		{"sway, recorded", sway(fixture("sway-get-outputs.json")), []render.Output{{Name: "WL-1"}, {Name: "WL-2", Disabled: true}}},
		{"sway drops Unknown parts", sway(`[{"name": "DP-1", "make": "AOC", "model": "CU34G4Z", "serial": "Unknown", "active": true}]`),
			[]render.Output{{Name: "DP-1", Description: "AOC CU34G4Z"}}},
		{"niri, recorded", niri(fixture("niri-outputs.json")), []render.Output{{Name: "DP-1", Description: "PNP(AOC) CU34G4Z XJ9R7HA000231"}}},
		{"niri: no logical output is disabled, by name", niri(`{"HDMI-A-1": {"make": "LG", "model": "TV", "serial": null, "logical": null}, "DP-1": {"make": "AOC", "model": "Unknown", "serial": "X1", "logical": {"x": 0}}}`),
			[]render.Output{{Name: "DP-1", Description: "AOC X1"}, {Name: "HDMI-A-1", Description: "LG TV", Disabled: true}}},
		{"hyprland, recorded", hypr(fixture("hypr-monitors-all.json")), []render.Output{{Name: "WAYLAND-1"}}},
		{"hyprland keeps its description", hypr(`[{"name": "DP-1", "description": "AOC CU34G4Z XJ9", "disabled": false}, {"name": "HDMI-A-1", "description": "LG TV", "disabled": true}]`),
			[]render.Output{{Name: "DP-1", Description: "AOC CU34G4Z XJ9"}, {Name: "HDMI-A-1", Description: "LG TV", Disabled: true}}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			got, err := tt.read(ctx(t), short(t))
			if err != nil {
				t.Fatal(err)
			}
			if !reflect.DeepEqual(got, tt.want) {
				t.Errorf("got %+v, want %+v", got, tt.want)
			}
		})
	}
}

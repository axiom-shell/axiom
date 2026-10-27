package palette

import (
	"bytes"
	"encoding/json"
	"flag"
	"image"
	"image/color"
	"math"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

var update = flag.Bool("update", false, "rewrite testdata/*.golden from what Themes makes now")

// Test images, drawn by a function of the pixel position
var images = map[string]struct {
	w, h int
	at   func(x, y int) color.Color
}{
	// Bands of color, so every accent slot has something to pick from
	"bands": {120, 80, func(x, y int) color.Color {
		cols := []color.RGBA{{30, 40, 90, 255}, {200, 80, 60, 255}, {60, 160, 90, 255}, {220, 200, 80, 255}, {140, 60, 160, 255}}
		return cols[(x/24)%len(cols)]
	}},
	// A wide gradient through hue and lightness, downscaled
	"gradient": {640, 360, func(x, y int) color.Color {
		return color.RGBA{uint8(x * 255 / 639), uint8(y * 255 / 359), uint8(255 - x*200/639), 255}
	}},
	// Mostly one dark blue with a small vivid orange area
	"accent": {200, 200, func(x, y int) color.Color {
		if x > 170 && y > 170 {
			return color.RGBA{240, 130, 20, 255}
		}
		return color.RGBA{20, 30, uint8(60 + (x+y)%20), 255}
	}},
	"grey":  {64, 64, func(x, y int) color.Color { g := uint8(x * 4); return color.RGBA{g, g, g, 255} }},
	"pixel": {1, 1, func(x, y int) color.Color { return color.RGBA{10, 200, 30, 255} }},
}

func draw(name string) image.Image {
	spec := images[name]
	img := image.NewRGBA(image.Rect(0, 0, spec.w, spec.h))
	for y := range spec.h {
		for x := range spec.w {
			img.Set(x, y, spec.at(x, y))
		}
	}
	return img
}

func semantic(t *testing.T) *jsonx.Object {
	raw, err := os.ReadFile("../../../../config/json/theme-defaults.json")
	if err != nil {
		t.Fatal(err)
	}
	v, err := jsonx.Unmarshal(raw)
	if err != nil {
		t.Fatal(err)
	}
	return v.(*jsonx.Object).Value("semantic").(*jsonx.Object).Value("dark").(*jsonx.Object)
}

type themeFile struct {
	Name      string            `json:"name"`
	Variant   string            `json:"variant"`
	Paired    string            `json:"paired"`
	Generated map[string]any    `json:"generated"`
	Colors    map[string]string `json:"colors"`
	Semantic  map[string]string `json:"semantic"`
}

func themes(t *testing.T, name string) map[string]themeFile {
	t.Helper()
	at := time.Date(2026, 10, 27, 12, 0, 0, 0, time.UTC)
	out := map[string]themeFile{}
	for _, f := range Themes(Analyze(draw(name)), semantic(t), "/walls/"+name+".png", at) {
		var theme themeFile
		if err := json.Unmarshal(f.Data, &theme); err != nil {
			t.Fatalf("%s: %v", f.Name, err)
		}
		out[strings.TrimSuffix(f.Name, ".json")] = theme
	}
	return out
}

// The colors each image makes, one line per theme: a change to the
// algorithm shows here as a diff to review (go test -update rewrites them)
func TestGolden(t *testing.T) {
	t.Parallel()
	for name := range images {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			var b bytes.Buffer
			for _, f := range Themes(Analyze(draw(name)), semantic(t), "/w.png", time.Time{}) {
				var theme themeFile
				if err := json.Unmarshal(f.Data, &theme); err != nil {
					t.Fatal(err)
				}
				line, _ := json.Marshal(map[string]any{"colors": theme.Colors, "accentAlt": theme.Semantic["accentAlt"], "seed": theme.Generated["seed"]})
				b.WriteString(f.Name + " " + string(line) + "\n")
			}
			path := filepath.Join("testdata", name+".golden")
			if *update {
				if err := os.WriteFile(path, b.Bytes(), 0o644); err != nil {
					t.Fatal(err)
				}
				return
			}
			want, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			if got := b.String(); got != string(want) {
				t.Errorf("colors changed (go test -update to accept):\n got %s\nwant %s", got, want)
			}
		})
	}
}

func TestFiles(t *testing.T) {
	t.Parallel()
	got := themes(t, "bands")
	if len(got) != 2*len(Styles) {
		t.Fatalf("%d files, want %d", len(got), 2*len(Styles))
	}
	for _, s := range Styles {
		dark, light := got["wallpaper-"+s.Name+"-dark"], got["wallpaper-"+s.Name+"-light"]
		if dark.Variant != "dark" || light.Variant != "light" || dark.Paired != "wallpaper-"+s.Name+"-light" || light.Paired != "wallpaper-"+s.Name+"-dark" {
			t.Errorf("%s: variants or pairs wrong: %+v %+v", s.Name, dark, light)
		}
		if want := "Wallpaper " + strings.ToUpper(s.Name[:1]) + s.Name[1:] + " Dark"; dark.Name != want {
			t.Errorf("name %q, want %q", dark.Name, want)
		}
		if dark.Generated["style"] != s.Name || dark.Generated["wallpaper"] != "/walls/bands.png" || dark.Generated["timestamp"] != "2026-10-27T12:00:00.000000Z" {
			t.Errorf("%s: generated = %v", s.Name, dark.Generated)
		}
		if len(dark.Colors) != 16 || dark.Semantic["accent"] != "base0F" || dark.Semantic["borderFocus"] != "base0F" || dark.Semantic["background"] != "base00" {
			t.Errorf("%s: colors or semantic wrong: %v %v", s.Name, dark.Colors, dark.Semantic)
		}
	}
}

func hexColor(t *testing.T, s string) rgb8 {
	t.Helper()
	v, err := strconv.ParseUint(strings.TrimPrefix(s, "#"), 16, 32)
	if err != nil || len(s) != 7 {
		t.Fatalf("%q isn't a hex color", s)
	}
	return rgb8{uint8(v >> 16), uint8(v >> 8), uint8(v)}
}

// Every accent reads against the background (3:1), and the ramp runs the
// variant's way
func TestReadable(t *testing.T) {
	t.Parallel()
	for name := range images {
		for file, theme := range themes(t, name) {
			bg := hexColor(t, theme.Colors["base00"])
			for _, slot := range []string{"base08", "base09", "base0A", "base0B", "base0C", "base0D", "base0E", "base0F"} {
				if c := contrast(hexColor(t, theme.Colors[slot]), bg); c < 2.9 {
					t.Errorf("%s %s: %s %s contrast %.2f", name, file, slot, theme.Colors[slot], c)
				}
			}
			l0, l7 := hexColor(t, theme.Colors["base00"]).lab().L, hexColor(t, theme.Colors["base07"]).lab().L
			if (theme.Variant == "dark") != (l0 < l7) {
				t.Errorf("%s %s: base00 L %.2f, base07 L %.2f", name, file, l0, l7)
			}
		}
	}
}

func meanAccentChroma(t *testing.T, theme themeFile) float64 {
	sum := 0.0
	for _, slot := range []string{"base08", "base09", "base0A", "base0B", "base0C", "base0D", "base0E"} {
		_, c, _ := hexColor(t, theme.Colors[slot]).lab().lch()
		sum += c
	}
	return sum / 7
}

// Each style keeps its character: muted is calmer than tonal, vibrant
// stronger, and every style's pair differs from the others
func TestStyles(t *testing.T) {
	t.Parallel()
	for _, name := range []string{"bands", "gradient", "accent"} {
		got := themes(t, name)
		muted, tonal, vibrant := meanAccentChroma(t, got["wallpaper-muted-dark"]), meanAccentChroma(t, got["wallpaper-tonal-dark"]), meanAccentChroma(t, got["wallpaper-vibrant-dark"])
		if !(muted < tonal && tonal < vibrant) {
			t.Errorf("%s: accent chroma muted %.3f, tonal %.3f, vibrant %.3f", name, muted, tonal, vibrant)
		}
		seen := map[string]string{}
		for _, s := range Styles {
			if s.Name == "alternate" && name != "bands" {
				continue // with one distinct hue, alternate's seed is tonal's rotated: it may match faithful's
			}
			key, _ := json.Marshal(got["wallpaper-"+s.Name+"-dark"].Colors)
			if other, ok := seen[string(key)]; ok {
				t.Errorf("%s: %s and %s are the same", name, s.Name, other)
			}
			seen[string(key)] = s.Name
		}
	}
}

// The small vivid area gets a candidate of its own, which the orange
// slot takes its hue from
func TestSmallVividAreaHasACandidate(t *testing.T) {
	t.Parallel()
	a := Analyze(draw("accent"))
	orange := rgb8{240, 130, 20}.lab()
	found := false
	for _, c := range a.candidates {
		found = found || c.color.lab().dist2(orange) < 0.0004
	}
	if !found {
		t.Errorf("no candidate near the orange: %v", a.candidates)
	}
}

// A grey image has no seed: base0F takes the cast's hue at barely any color
func TestGreyHasNoSeed(t *testing.T) {
	t.Parallel()
	theme := themes(t, "grey")["wallpaper-tonal-dark"]
	if theme.Generated["seed"] != nil {
		t.Errorf("seed = %v, want null", theme.Generated["seed"])
	}
	if _, c, _ := hexColor(t, theme.Colors["base00"]).lab().lch(); c > 0.02 {
		t.Errorf("base00 chroma %.3f on a grey image", c)
	}
}

func TestDownscale(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct{ w, h, n int }{{1920, 1080, 128 * 72}, {1080, 1920, 72 * 128}, {100, 50, 100 * 50}, {3000, 10, 128}} {
		img := image.NewRGBA(image.Rect(0, 0, tc.w, tc.h))
		if got := len(downscale(img)); got != tc.n {
			t.Errorf("%dx%d: %d pixels, want %d", tc.w, tc.h, got, tc.n)
		}
	}
}

func TestLCHColorFitsTheGamut(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		l, c, h float64
		want    string
	}{
		{0.5, 0, 0, "#636363"},
		{1, 0, 0, "#ffffff"},
		{0.7, 0.4, 30, ""}, // far out of gamut: chroma reduced, still that hue
	} {
		got := lchColor(tc.l, tc.c, tc.h)
		if tc.want != "" && got.hex() != tc.want {
			t.Errorf("lch(%v %v %v) = %s, want %s", tc.l, tc.c, tc.h, got.hex(), tc.want)
		}
		if l, _, h := got.lab().lch(); math.Abs(l-tc.l) > 0.01 || (tc.c > 0 && math.Abs(hueDiff(h, tc.h)) > 2) {
			t.Errorf("lch(%v %v %v) = %s: L %.3f H %.1f", tc.l, tc.c, tc.h, got.hex(), l, h)
		}
	}
}

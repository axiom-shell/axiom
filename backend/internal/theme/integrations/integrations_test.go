package integrations

import (
	"encoding/json"
	"encoding/xml"
	"flag"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"testing"
)

var update = flag.Bool("update", false, "rewrite the golden files")

const repo = "../../../.."

var dirs = Dirs{Home: "/home/u", Config: "/home/u/.config", State: "/home/u/.local/state", Data: "/home/u/.local/share", Each: "/each"}

func load(t *testing.T, path string) *Theme {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	defaults, err := os.ReadFile(repo + "/config/json/theme-defaults.json")
	if err != nil {
		t.Fatal(err)
	}
	th, err := Parse(data, defaults, strings.TrimSuffix(filepath.Base(path), ".json"))
	if err != nil {
		t.Fatal(err)
	}
	return th
}

func shipped(t *testing.T) []string {
	t.Helper()
	files, _ := filepath.Glob(repo + "/config/themes/*.json")
	files = slices.DeleteFunc(files, func(f string) bool { return strings.HasSuffix(f, "theme.schema.json") })
	if len(files) < 10 {
		t.Fatalf("only %d themes", len(files))
	}
	return files
}

// golden is where a file's golden copy lives: testdata/<theme>/<key>/<path>
func golden(theme, key, path string) string {
	return filepath.Join("testdata", theme, key, strings.NewReplacer("{", "", "}", "").Replace(path))
}

// Every integration's files for a dark and a light theme, as written
// (go test -update rewrites them)
func TestGoldens(t *testing.T) {
	t.Parallel()
	for _, theme := range []string{"catppuccin-mocha", "ayu-light"} {
		th := load(t, repo+"/config/themes/"+theme+".json")
		for key, integ := range Table {
			for _, f := range integ.Files {
				t.Run(theme+"/"+key+"/"+f.Path, func(t *testing.T) {
					got, err := f.Render(th, dirs)
					if err != nil {
						t.Fatal(err)
					}
					path := golden(theme, key, f.Path)
					if *update {
						if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
							t.Fatal(err)
						}
						if err := os.WriteFile(path, got, 0o644); err != nil {
							t.Fatal(err)
						}
						return
					}
					want, err := os.ReadFile(path)
					if err != nil {
						t.Fatalf("%v (go test -update writes it)", err)
					}
					if string(got) != string(want) {
						t.Errorf("differs from %s (go test -update after checking the change)", path)
					}
				})
			}
		}
	}
}

var color = regexp.MustCompile(`#([0-9a-fA-F]+)\b`)

// Every shipped theme renders through every integration into files that
// parse, with only well-formed colors
func TestEveryThemeRenders(t *testing.T) {
	t.Parallel()
	for _, file := range shipped(t) {
		th := load(t, file)
		for key, integ := range Table {
			for _, f := range integ.Files {
				got, err := f.Render(th, dirs)
				if err != nil {
					t.Errorf("%s %s: %v", th.Stem, f.Path, err)
					continue
				}
				for _, m := range color.FindAllStringSubmatch(string(got), -1) {
					if n := len(m[1]); n != 6 && n != 8 {
						t.Errorf("%s %s: malformed color %s", th.Stem, f.Path, m[0])
					}
				}
				switch filepath.Ext(f.Path) {
				case ".json":
					if !json.Valid(got) {
						t.Errorf("%s %s: not JSON", th.Stem, f.Path)
					}
				case ".tmTheme":
					if err := xmlWellFormed(got); err != nil {
						t.Errorf("%s %s: %v", th.Stem, f.Path, err)
					}
				case ".css":
					if strings.Count(string(got), "{") != strings.Count(string(got), "}") {
						t.Errorf("%s %s: unbalanced braces", th.Stem, key)
					}
				}
			}
		}
	}
}

func xmlWellFormed(b []byte) error {
	d := xml.NewDecoder(strings.NewReader(string(b)))
	d.Strict = true
	for {
		if _, err := d.Token(); err != nil {
			if err.Error() == "EOF" {
				return nil
			}
			return err
		}
	}
}

func luminance(c string) float64 {
	var rgb [3]float64
	for i := range rgb {
		var v uint8
		fmt.Sscanf(c[1+2*i:3+2*i], "%02x", &v)
		x := float64(v) / 255
		if x <= 0.04045 {
			rgb[i] = x / 12.92
		} else {
			rgb[i] = math.Pow((x+0.055)/1.055, 2.4)
		}
	}
	return 0.2126*rgb[0] + 0.7152*rgb[1] + 0.0722*rgb[2]
}

func contrastOf(a, b string) float64 {
	la, lb := luminance(a), luminance(b)
	return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
}

// The terminal palette and text colors are readable on every theme, and a
// light theme's black is dark
func TestTerminalPalette(t *testing.T) {
	t.Parallel()
	for _, file := range shipped(t) {
		th := load(t, file)
		v := th.vars(true)
		bg := v["BACKGROUND"]
		for i := range 16 {
			if i == 0 || i == 7 || i == 15 {
				continue
			}
			name, want := fmt.Sprintf("ANSI_%d", i), textContrast
			if i == 8 {
				want = dimContrast
			}
			if got := contrastOf(v[name], bg); got < want-0.01 {
				t.Errorf("%s %s %s: contrast %.2f", th.Stem, name, v[name], got)
			}
		}
		for _, name := range textColors {
			if got := contrastOf(v[name], bg); got < textContrast-0.01 {
				t.Errorf("%s %s %s: contrast %.2f", th.Stem, name, v[name], got)
			}
		}
		if th.Light && luminance(v["ANSI_0"]) >= luminance(bg) {
			t.Errorf("%s: black isn't dark", th.Stem)
		}
	}
}

// An integration writes only its own axiom file (some folder or file of its
// path is axiom's), but for a missing main config it creates
func TestOnlyAxiomFiles(t *testing.T) {
	t.Parallel()
	for key, integ := range Table {
		for _, f := range integ.Files {
			own := slices.ContainsFunc(strings.Split(f.Path, "/"), func(part string) bool {
				return strings.HasPrefix(strings.ToLower(part), "axiom")
			})
			if own == f.IfMissing {
				t.Errorf("%s: %s (IfMissing %v)", key, f.Path, f.IfMissing)
			}
			if (strings.HasPrefix(f.Path, "{each}")) != (integ.Each != nil || integ.Profiles) {
				t.Errorf("%s: %s and its Each", key, f.Path)
			}
		}
	}
}

func TestSpliceNcspot(t *testing.T) {
	t.Parallel()
	markers := NcspotBegin + "\n" + NcspotEnd + "\n"
	colors := "# generated\nprimary = \"#ffffff\"\nbackground = \"#000000\"\n"
	tests := []struct {
		name, config, want string
		own                []string
		ok                 bool
	}{
		{"fills the markers", "[theme]\n" + markers, "[theme]\n" + NcspotBegin + "\n" + colors + NcspotEnd + "\n", nil, true},
		{"your keys win",
			"use_nerdfont = true\n\n[theme]\nprimary = \"red\"\n" + markers + "\n[keybindings]\n\"q\" = \"quit\"\n",
			"use_nerdfont = true\n\n[theme]\nprimary = \"red\"\n" + NcspotBegin + "\n# generated\nbackground = \"#000000\"\n" + NcspotEnd + "\n\n[keybindings]\n\"q\" = \"quit\"\n",
			[]string{"primary"}, true},
		{"replaces the last colors", "[theme]\n" + NcspotBegin + "\nold = 1\n" + NcspotEnd + "\n", "[theme]\n" + NcspotBegin + "\n" + colors + NcspotEnd + "\n", nil, true},
		{"no markers", "[theme]\n", "", nil, false},
		{"markers outside [theme]", "[other]\n" + markers, "", nil, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			out, own, ok := SpliceNcspot([]byte(tt.config), []byte(colors))
			if ok != tt.ok || string(out) != tt.want || !slices.Equal(own, tt.own) {
				t.Errorf("got %v %q %v", ok, out, own)
			}
			if ok {
				again, _, _ := SpliceNcspot(out, []byte(colors))
				if string(again) != string(out) {
					t.Errorf("a second splice changed it: %q", again)
				}
			}
		})
	}
}

func TestMergeKDE(t *testing.T) {
	t.Parallel()
	scheme := "# header\n[General]\nName=Axiom\n\n[Colors:View]\nBackgroundNormal=9,9,9\nForegroundNormal=8,8,8\n\n[Colors:Selection]\nBackgroundNormal=7,7,7\n\n[WM]\nactiveBackground=6,6,6\n"
	mine := "[Colors:View]\nBackgroundNormal=1,2,3\nCustom=x\n\n[General]\nColorScheme=Axiom\n\n[WM]\nactiveFont=Sans,10\n"
	want := "[Colors:View]\nBackgroundNormal=9,9,9\nCustom=x\nForegroundNormal=8,8,8\n\n[General]\nColorScheme=Axiom\n\n[WM]\nactiveFont=Sans,10\nactiveBackground=6,6,6\n\n[Colors:Selection]\nBackgroundNormal=7,7,7\n"
	got := MergeKDE([]byte(scheme), []byte(mine))
	if string(got) != want {
		t.Errorf("got\n%s\nwant\n%s", got, want)
	}
	if again := MergeKDE([]byte(scheme), got); string(again) != string(got) {
		t.Errorf("a second merge changed it:\n%s", again)
	}
}

func TestColorSchemeIn(t *testing.T) {
	t.Parallel()
	rc := []byte("[General]\nColorScheme=Other\n\n[UiSettings]\nColorScheme = BreezeDark\n")
	for group, want := range map[string]string{"General": "Other", "UiSettings": "BreezeDark", "WM": ""} {
		if got := ColorSchemeIn(rc, group); got != want {
			t.Errorf("%s: %q", group, got)
		}
	}
}

func TestFoot(t *testing.T) {
	t.Parallel()
	in := "# head\n\n[colors]\ncursor=111111 222222\nbackground=333333\n"
	tests := map[FootStyle]string{
		FootColors:        in,
		FootDarkLight:     "# head\n\n[colors-dark]\ncursor=111111 222222\nbackground=333333\n\n[colors-light]\ncursor=111111 222222\nbackground=333333\n",
		FootCursorSection: "[cursor]\ncolor=111111 222222\n\n# head\n\n[colors]\nbackground=333333\n",
	}
	for style, want := range tests {
		if got := string(Foot([]byte(in), style)); got != want {
			t.Errorf("%d: got %q", style, got)
		}
	}
}

func TestReadableNvimText(t *testing.T) {
	t.Parallel()
	for _, name := range []string{"ayu-light", "submarine-sonar"} {
		th := load(t, repo+"/config/themes/"+name+".json")
		out, err := nvim(th)
		if err != nil {
			t.Fatal(err)
		}
		var data struct{ Semantic, Text map[string]string }
		if err := json.Unmarshal(out, &data); err != nil {
			t.Fatal(err)
		}
		for _, k := range []string{"accent", "accentAlt"} {
			if c := contrastOf(data.Text[k], data.Semantic["background"]); c < textContrast-0.01 {
				t.Errorf("%s %s: %.2f", name, k, c)
			}
		}
	}
}

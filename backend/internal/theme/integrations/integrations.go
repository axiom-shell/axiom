// Package integrations renders axiom's theme integrations: for one theme,
// the content of every file an integration writes for its app (each the
// app's own axiom.* file), from the templates beside it or built here.
// Pure: no I/O; package theme writes the files and tells the apps.
//
// A template is the app's file with ${NAME}s: THEME_NAME, THEME_AUTHOR,
// THEME_VARIANT, COLOR_SCHEME (light or dark), BASE00-BASE0F, every
// semantic color as UPPER_SNAKE (backgroundAlt: BACKGROUND_ALT) and the
// terminal palette ANSI_0-ANSI_15. A name nothing sets is an error, never
// an empty value.
package integrations

import (
	"embed"
	"encoding/json"
	"fmt"
	"maps"
	"regexp"
	"strings"
	"unicode"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/theme/palette"
)

//go:embed templates
var templates embed.FS

// Theme is a theme file with what it leaves out filled from the defaults,
// as the shell's Theme does.
type Theme struct {
	// Name, Author and Variant are "" when the file has none
	Name, Author, Variant string
	// Stem is the theme file's name without .json (Neovim maps it to a
	// colorscheme)
	Stem  string
	Light bool
	// Colors are the theme's own colors, as its file has them
	Colors map[string]string
	// Base is base00-base0F, the defaults filled in; Semantic each
	// semantic name's color, resolved through Base
	Base, Semantic map[string]string
}

type themeFile struct {
	Name     string            `json:"name"`
	Author   string            `json:"author"`
	Variant  string            `json:"variant"`
	Colors   map[string]string `json:"colors"`
	Semantic map[string]string `json:"semantic"`
}

type defaultsFile struct {
	Colors   map[string]string            `json:"colors"`
	Semantic map[string]map[string]string `json:"semantic"`
}

// Parse reads a theme file over theme-defaults.json. A file that isn't a
// theme is axerr.BadRequest.
func Parse(data, defaults []byte, stem string) (*Theme, error) {
	var f themeFile
	var d defaultsFile
	if err := json.Unmarshal(data, &f); err != nil {
		return nil, axerr.Wrap(axerr.BadRequest, err, "the theme %s isn't a theme file", stem)
	}
	if err := json.Unmarshal(defaults, &d); err != nil {
		return nil, axerr.Wrap(axerr.Internal, err, "theme defaults")
	}
	t := &Theme{Name: f.Name, Author: f.Author, Variant: f.Variant, Stem: stem, Colors: f.Colors}
	t.Light = t.Variant == "light"
	variant := "dark"
	if t.Light {
		variant = "light"
	}
	t.Base = merged(d.Colors, f.Colors)
	t.Semantic = merged(d.Semantic[variant], f.Semantic)
	for k, v := range t.Semantic {
		if c, ok := t.Base[v]; ok {
			t.Semantic[k] = c
		}
	}
	return t, nil
}

func or(s, fallback string) string {
	if s == "" {
		return fallback
	}
	return s
}

func merged(a, b map[string]string) map[string]string {
	out := maps.Clone(a)
	if out == nil {
		out = map[string]string{}
	}
	maps.Copy(out, b)
	return out
}

// Minimum contrast against the background for colors drawn as text in a
// terminal: chromatic ANSI and semantic colors, and bright black
// (comments, autosuggestions), meant to stay dim
const (
	textContrast = 4.5
	dimContrast  = 3.0
)

// The semantic colors terminal apps draw text in, made readable like the
// ANSI palette for the integrations asking for it (not GTK or Qt, where
// they're accents)
var textColors = []string{"RED", "GREEN", "YELLOW", "BLUE", "MAGENTA", "CYAN", "ORANGE", "ERROR", "WARNING", "SUCCESS", "INFO"}

// The base16 slots of ANSI 0-15. A light theme's black and white take its
// dark and light shades: a terminal's "black" is dark on any background.
var (
	ansiDark  = [16]string{"00", "08", "0B", "0A", "0D", "0E", "0C", "05", "03", "09", "0B", "0A", "0D", "0E", "0C", "07"}
	ansiLight = [16]string{"05", "08", "0B", "0A", "0D", "0E", "0C", "02", "03", "09", "0B", "0A", "0D", "0E", "0C", "01"}
)

// vars are a template's values. meta holds the names that aren't colors
// (left alone by a template's color format).
type vars map[string]string

var meta = map[string]bool{"THEME_NAME": true, "THEME_AUTHOR": true, "THEME_VARIANT": true, "COLOR_SCHEME": true}

// vars are the theme's template values, text colors readable when text.
func (t *Theme) vars(text bool) vars {
	v := vars{
		"THEME_NAME": clean(or(t.Name, "Unknown")), "THEME_AUTHOR": clean(or(t.Author, "N/A")), "THEME_VARIANT": clean(or(t.Variant, "unknown")),
		"COLOR_SCHEME": "dark",
	}
	if t.Light {
		v["COLOR_SCHEME"] = "light"
	}
	for k, c := range t.Base {
		v[strings.ToUpper(k)] = c
	}
	for k, c := range t.Semantic {
		v[snakeUpper(k)] = c
	}
	slots := ansiDark
	if t.Light {
		slots = ansiLight
	}
	for i, slot := range slots {
		v[fmt.Sprintf("ANSI_%d", i)] = t.Base["base"+slot]
	}
	bg := v["BACKGROUND"]
	if bg == "" {
		bg = v["BASE00"]
	}
	for i := range 16 {
		if min := textContrast; i != 0 && i != 7 && i != 15 {
			if i == 8 {
				min = dimContrast
			}
			name := fmt.Sprintf("ANSI_%d", i)
			v[name] = palette.Readable(v[name], bg, min)
		}
	}
	if text {
		for _, name := range textColors {
			if c, ok := v[name]; ok {
				v[name] = palette.Readable(c, bg, textContrast)
			}
		}
	}
	return v
}

// snakeUpper: backgroundAlt is BACKGROUND_ALT.
func snakeUpper(key string) string {
	var b strings.Builder
	for _, r := range key {
		if unicode.IsUpper(r) {
			b.WriteByte('_')
		}
		b.WriteRune(unicode.ToUpper(r))
	}
	return b.String()
}

// clean keeps a theme's name from breaking the line it's written in.
func clean(s string) string {
	return strings.Map(func(r rune) rune {
		if unicode.IsControl(r) {
			return ' '
		}
		return r
	}, s)
}

var placeholder = regexp.MustCompile(`\$\{([A-Za-z_][A-Za-z0-9_]*)\}`)

// expand fills a template; a .json one gets its values JSON-escaped.
func expand(name string, v vars) ([]byte, error) {
	text, err := templates.ReadFile("templates/" + name)
	if err != nil {
		return nil, axerr.Wrap(axerr.Internal, err, "template %s", name)
	}
	escape := strings.HasSuffix(name, ".json")
	var missing string
	out := placeholder.ReplaceAllFunc(text, func(m []byte) []byte {
		key := string(m[2 : len(m)-1])
		value, ok := v[key]
		if !ok {
			missing = key
		}
		if escape {
			quoted, _ := json.Marshal(value)
			return quoted[1 : len(quoted)-1]
		}
		return []byte(value)
	})
	if missing != "" {
		return nil, axerr.New(axerr.Internal, "template %s uses ${%s}, which nothing sets", name, missing)
	}
	return out, nil
}

// The color formats templates want ("#rrggbb" is the default)
func hex(c string) string { return strings.TrimPrefix(c, "#") }

func quoted(c string) string {
	if c == "" {
		return `""`
	}
	return `"#` + hex(c) + `"`
}

// kdeRGB is a color as KDE's r,g,b.
func kdeRGB(c string) string {
	var r, g, b uint8
	if _, err := fmt.Sscanf(hex(c), "%02x%02x%02x", &r, &g, &b); err != nil {
		return c
	}
	return fmt.Sprintf("%d,%d,%d", r, g, b)
}

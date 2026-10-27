package integrations

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/theme/palette"
)

// Integration is what one ThemeIntegrations switch writes.
type Integration struct {
	// Each lists folders ({home}, {config}); the files under {each} are
	// written into every one of them that exists. Profiles: into every
	// browser profile its schema entry's x-profiles list instead.
	Each     []string
	Profiles bool
	// Missing is said when Each or Profiles found nowhere to write
	Missing string
	Files   []File
}

// File is one file an integration writes.
type File struct {
	// Path starts with {config}, {state}, {data} ($XDG_*_HOME) or {each}
	// (Dirs.Expand)
	Path string
	// Requires names a command without which the file is skipped
	Requires string
	// IfMissing: written only where there's no file (a main config the
	// app needs to load the colors, the user's from then on)
	IfMissing bool
	render    renderer
}

// Render is the file's content for a theme.
func (f File) Render(t *Theme, d Dirs) ([]byte, error) { return f.render.render(t, d) }

type renderer interface {
	render(*Theme, Dirs) ([]byte, error)
}

// tmpl renders a template: text makes the text colors readable, format
// rewrites every color, extra adds values of the integration's own.
type tmpl struct {
	name   string
	text   bool
	format func(string) string
	extra  func(*Theme, vars)
}

func (r tmpl) render(t *Theme, _ Dirs) ([]byte, error) {
	v := t.vars(r.text)
	if r.format != nil {
		for k, c := range v {
			if !meta[k] {
				v[k] = r.format(c)
			}
		}
	}
	if r.extra != nil {
		r.extra(t, v)
	}
	return expand(r.name, v)
}

type renderFunc func(*Theme) ([]byte, error)

func (f renderFunc) render(t *Theme, _ Dirs) ([]byte, error) { return f(t) }

// text is a fixed file, its paths expanded
type text string

func (s text) render(_ *Theme, d Dirs) ([]byte, error) { return []byte(d.Expand(string(s))), nil }

// one is an integration writing one template.
func one(path string, r tmpl) Integration {
	return Integration{Files: []File{{Path: path, render: r}}}
}

// Table is every integration, by its ThemeIntegrations key.
var Table = map[string]Integration{
	"alacritty": one("{config}/alacritty/axiom.toml", tmpl{name: "alacritty.toml"}),
	"bat":       one("{config}/bat/themes/axiom.tmTheme", tmpl{name: "bat.tmTheme", text: true}),
	"btop":      one("{config}/btop/themes/axiom.theme", tmpl{name: "btop.theme", text: true}),
	"cava": {Files: []File{
		{Path: "{config}/cava/colors/axiom.conf", render: tmpl{name: "cava.conf", format: quoted, extra: cavaGradient}},
		{Path: "{config}/cava/config", IfMissing: true, render: text(cavaConfig)},
	}},
	"firefox": {Profiles: true,
		Missing: "no Firefox, LibreWolf, Zen, Floorp or Waterfox profile found (start the browser once)",
		Files:   []File{{Path: "{each}/chrome/axiom.css", render: tmpl{name: "firefox.css"}}}},
	"foot":    one("{config}/foot/axiom.ini", tmpl{name: "foot.ini", format: hex}),
	"fzf":     {Files: []File{{Path: "{state}/axiom/fzf-colors", render: renderFunc(fzf)}}},
	"ghostty": one("{config}/ghostty/themes/axiom", tmpl{name: "ghostty"}),
	"gtk": {Files: []File{
		{Path: "{config}/gtk-3.0/axiom.css", render: tmpl{name: "gtk.css"}},
		{Path: "{config}/gtk-3.0/gtk.css", IfMissing: true, render: text(gtkCSS)},
		{Path: "{config}/gtk-4.0/axiom.css", render: tmpl{name: "gtk.css"}},
		{Path: "{config}/gtk-4.0/gtk.css", IfMissing: true, render: text(gtkCSS)},
	}},
	"helix":   one("{config}/helix/themes/axiom.toml", tmpl{name: "helix.toml", text: true}),
	"k9s":     one("{config}/k9s/skins/axiom.yaml", tmpl{name: "k9s.yaml", text: true, format: quoted}),
	"kitty":   one("{config}/kitty/axiom.conf", tmpl{name: "kitty.conf"}),
	"lazygit": one("{config}/lazygit/axiom.yml", tmpl{name: "lazygit.yml", text: true}),
	"ncspot":  one("{state}/axiom/ncspot-theme.toml", tmpl{name: "ncspot.toml", text: true}),
	"nvim":    {Files: []File{{Path: "{state}/axiom/nvim-theme.json", render: renderFunc(nvim)}}},
	"qt": {Files: []File{
		{Path: "{config}/qt5ct/colors/axiom.conf", Requires: "qt5ct", render: renderFunc(qtPalette)},
		{Path: "{config}/qt6ct/colors/axiom.conf", Requires: "qt6ct", render: renderFunc(qtPalette)},
		{Path: "{data}/color-schemes/Axiom.colors", render: tmpl{name: "qt.colors", format: kdeRGB}},
	}},
	"vesktop": {
		// The Flathub Vesktop keeps its config in its sandbox's own
		// XDG_CONFIG_HOME
		Each:    []string{"{config}/vesktop", "{config}/Vencord", "{config}/equibop", "{config}/Equicord", "{home}/.var/app/dev.vencord.Vesktop/config/vesktop"},
		Missing: "no Vesktop (native or Flatpak), Vencord, Equibop or Equicord config found (start Vesktop once)",
		Files:   []File{{Path: "{each}/themes/axiom.theme.css", render: tmpl{name: "vesktop.css", text: true}}}},
	"vscode": {Each: []string{"{home}/.vscode", "{home}/.vscode-oss"},
		Missing: "neither ~/.vscode nor ~/.vscode-oss exists (start VS Code or VSCodium once)",
		Files: []File{
			{Path: "{each}/extensions/axiom-theme/themes/axiom-color-theme.json", render: tmpl{name: "vscode.json"}},
			// uiTheme follows the variant, so the manifest is rewritten too
			{Path: "{each}/extensions/axiom-theme/package.json", render: tmpl{name: "vscode-package.json", extra: vscodeUI}},
		}},
	"wezterm": one("{config}/wezterm/colors/axiom.toml", tmpl{name: "wezterm.toml"}),
	"yazi":    one("{config}/yazi/flavors/axiom.yazi/flavor.toml", tmpl{name: "yazi.toml", text: true}),
	"zathura": one("{config}/zathura/axiom", tmpl{name: "zathura"}),
	"zed":     one("{config}/zed/themes/axiom.json", tmpl{name: "zed.json", text: true}),
}

// cava's gradient: two more colors on a dark theme
func cavaGradient(t *Theme, v vars) {
	v["GRADIENT_COUNT"], v["GRADIENT_7"], v["GRADIENT_8"] = "6", `""`, `""`
	if !t.Light {
		v["GRADIENT_COUNT"], v["GRADIENT_7"], v["GRADIENT_8"] = "8", v["BASE08"], v["ACCENT_ALT"]
	}
}

func vscodeUI(t *Theme, v vars) {
	v["UI_THEME"] = "vs-dark"
	if t.Light {
		v["UI_THEME"] = "vs"
	}
}

const gtkCSS = "/* GTK user CSS (created by axiom; yours to edit) */\n" + GTKImport + "\n"

// GTKImport is the line a gtk.css loads the colors with.
const GTKImport = `@import url("axiom.css");`

const cavaConfig = `# Main Cava configuration (created by axiom; yours to edit)
include = {config}/cava/colors/axiom.conf

[general]
framerate = 60
autosens = 1
sensitivity = 100
bars = 0
bar_width = 2
bar_spacing = 1

[input]
method = pulse
source = auto

[output]
method = ncurses
channels = stereo
mono_option = average
`

// Dirs are where an integration's paths point.
type Dirs struct {
	Home, Config, State, Data string
	// Each is the folder of the Each or Profiles entry being written
	Each string
}

// Expand fills a path's (or a text's) {home}, {config}, {state}, {data}
// and {each}.
func (d Dirs) Expand(s string) string {
	return strings.NewReplacer("{home}", d.Home, "{config}", d.Config, "{state}", d.State, "{data}", d.Data, "{each}", d.Each).Replace(s)
}

// fzf's options file: one --color flag
func fzf(t *Theme) ([]byte, error) {
	v := t.vars(true)
	pairs := []string{
		"fg", "FOREGROUND", "bg", "BACKGROUND", "hl", "ACCENT",
		"fg+", "FOREGROUND_HIGHLIGHT", "bg+", "BACKGROUND_HIGHLIGHT", "hl+", "ACCENT",
		"info", "INFO", "marker", "SUCCESS", "prompt", "ACCENT", "spinner", "ACCENT_ALT",
		"pointer", "ACCENT", "header", "FOREGROUND_ALT", "border", "BORDER",
		"label", "FOREGROUND_ALT", "query", "FOREGROUND", "gutter", "BACKGROUND",
	}
	var colors []string
	for i := 0; i < len(pairs); i += 2 {
		colors = append(colors, pairs[i]+":"+v[pairs[i+1]])
	}
	return []byte("--color=" + strings.Join(colors, ",") + "\n"), nil
}

// nvim's palette file, read by the axiom_theme module: the file stem picks
// a native colorscheme; colors are the mini.base16 fallback, semantic is
// drawn on top, and text holds the accents readable against the
// background, for highlights that color text.
func nvim(t *Theme) ([]byte, error) {
	name := t.Name
	if name == "" {
		name = t.Stem
	}
	variant := "dark"
	if t.Light {
		variant = "light"
	}
	text := map[string]string{}
	for _, k := range []string{"accent", "accentAlt"} {
		if c, ok := t.Semantic[k]; ok {
			text[k] = palette.Readable(c, t.Semantic["background"], textContrast)
		}
	}
	colors := t.Colors
	if colors == nil {
		colors = map[string]string{}
	}
	out, err := json.MarshalIndent(map[string]any{
		"stem": t.Stem, "name": name, "variant": variant,
		"colors": colors, "semantic": t.Semantic, "text": text,
	}, "", "  ")
	return append(out, '\n'), err
}

// qtPalette is qt5ct's / qt6ct's color scheme: a QPalette per state, as
// #aarrggbb.
func qtPalette(t *Theme) ([]byte, error) {
	v := t.vars(false)
	argb := func(name string) string { return "#ff" + hex(v[name]) }
	// QPalette's roles in order: WindowText Button Light Midlight Dark Mid
	// Text BrightText ButtonText Base Window Shadow Highlight
	// HighlightedText Link LinkVisited AlternateBase NoRole ToolTipBase
	// ToolTipText PlaceholderText
	row := func(textColor string) string {
		roles := []string{
			argb(textColor), argb("BACKGROUND_ALT"), argb("BACKGROUND_HIGHLIGHT"), argb("BACKGROUND_HIGHLIGHT"),
			argb("BORDER"), argb("BORDER"), argb(textColor),
			argb("FOREGROUND_HIGHLIGHT"), argb(textColor), argb("BACKGROUND_ALT"), argb("BACKGROUND"), "#ff000000",
			argb("ACCENT"), argb("BACKGROUND"), argb("ACCENT"),
			argb("ACCENT_ALT"), argb("BACKGROUND_HIGHLIGHT"), argb(textColor), argb("BACKGROUND_ALT"), argb("FOREGROUND"), "#80" + hex(v["FOREGROUND"]),
		}
		return strings.Join(roles, ", ")
	}
	return fmt.Appendf(nil, "[ColorScheme]\nactive_colors=%s\ndisabled_colors=%s\ninactive_colors=%s\n",
		row("FOREGROUND"), row("FOREGROUND_INACTIVE"), row("FOREGROUND")), nil
}

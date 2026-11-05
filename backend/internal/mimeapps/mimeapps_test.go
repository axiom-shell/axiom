package mimeapps

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

// tree is a scratch XDG layout: config home, one config dir, data home and
// one data dir, with entries and lists written by the test
type tree struct {
	t                                *testing.T
	config, sysConfig, data, sysData string
}

func newTree(t *testing.T) *tree {
	root := t.TempDir()
	return &tree{t: t, config: filepath.Join(root, "config"), sysConfig: filepath.Join(root, "etc"), data: filepath.Join(root, "data"), sysData: filepath.Join(root, "usr")}
}

func (tr *tree) write(path, text string) {
	tr.t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		tr.t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(text), 0o644); err != nil {
		tr.t.Fatal(err)
	}
}

// app writes a system desktop entry
func (tr *tree) app(id, body string) {
	tr.write(filepath.Join(tr.sysData, "applications", id), "[Desktop Entry]\nType=Application\n"+body)
}

func (tr *tree) load(desktops ...string) *Apps {
	return Load(Options{ConfigHome: tr.config, ConfigDirs: []string{tr.sysConfig}, DataHome: tr.data, DataDirs: []string{tr.sysData}, Desktops: desktops})
}

func (tr *tree) standard() {
	tr.app("firefox.desktop", "Name=Firefox\nIcon=firefox\nExec=firefox %u\nMimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;\n")
	tr.app("chromium.desktop", "Name=Chromium\nExec=chromium %U\nMimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;application/pdf;\n")
	tr.app("org.gnome.Nautilus.desktop", "Name=Files\nExec=nautilus --new-window %U\nMimeType=inode/directory;\n")
	tr.app("thunar.desktop", "Name=Thunar\nExec=thunar %F\nMimeType=inode/directory;\n")
	tr.app("kitty.desktop", "Name=kitty\nExec=kitty\nCategories=System;TerminalEmulator;\n")
	tr.app("foot.desktop", "Name=Foot\nExec=foot\nCategories=System;TerminalEmulator;\nX-TerminalArgExec=--\n")
	tr.app("nvim.desktop", "Name=Neovim\nExec=nvim %F\nTerminal=true\nMimeType=text/plain;\n")
	tr.app("hidden.desktop", "Name=Hidden\nExec=hidden\nHidden=true\nMimeType=text/plain;\n")
	tr.app("missing.desktop", "Name=Missing\nExec=missing\nTryExec=surely-not-installed-anywhere\nMimeType=text/plain;\n")
	tr.app("eog.desktop", "Name=Image Viewer\nExec=eog %U\nMimeType=image/png;image/jpeg;\n")
	tr.app("gimp.desktop", "Name=GIMP\nExec=gimp %U\nMimeType=image/png;\n")
}

func TestDefaults(t *testing.T) {
	t.Parallel()
	tr := newTree(t)
	tr.standard()
	// The system list makes Chromium the browser; the user's makes it
	// Firefox, a desktop's own Thunar the file manager
	tr.write(filepath.Join(tr.sysData, "applications/mimeapps.list"), "[Default Applications]\nx-scheme-handler/http=chromium.desktop;\ninode/directory=org.gnome.Nautilus.desktop\n")
	tr.write(filepath.Join(tr.config, "mimeapps.list"), "[Default Applications]\nx-scheme-handler/http=gone.desktop;firefox.desktop;\n\n[Removed Associations]\napplication/pdf=chromium.desktop;\n")
	tr.write(filepath.Join(tr.config, "hyprland-mimeapps.list"), "[Default Applications]\ninode/directory=thunar.desktop;\n")
	a := tr.load("hyprland")
	for mime, want := range map[string]string{
		"x-scheme-handler/http": "firefox.desktop", // the first installed, past one that's gone
		"inode/directory":       "thunar.desktop",  // the desktop's own list first
		"application/pdf":       "",                // removed by the user's list
		"text/plain":            "nvim.desktop",    // not Hidden, not missing its TryExec
		"image/png":             "gimp.desktop",    // no default: the first associated, by name
	} {
		if got := a.Default(mime); got != want {
			t.Errorf("Default(%s) = %q, want %q", mime, got, want)
		}
	}
	// Without the desktop, its list isn't read
	if got := tr.load().Default("inode/directory"); got != "org.gnome.Nautilus.desktop" {
		t.Errorf("without hyprland: %q", got)
	}
}

func TestRoleState(t *testing.T) {
	t.Parallel()
	tr := newTree(t)
	tr.standard()
	tr.write(filepath.Join(tr.config, "mimeapps.list"), "[Default Applications]\nimage/png=gimp.desktop;\nimage/jpeg=eog.desktop;\n")
	a := tr.load()
	images, _ := RoleOf("images")
	st := a.RoleState(images)
	if st.Default != "gimp.desktop" || !st.Mixed {
		t.Errorf("images: default %q mixed %v, want gimp, mixed", st.Default, st.Mixed)
	}
	if got := ids(st.Handlers); !reflect.DeepEqual(got, []string{"eog.desktop", "gimp.desktop"}) {
		t.Errorf("images' handlers %v (most types first)", got)
	}
	term, _ := RoleOf("terminal")
	if st := a.RoleState(term); st.Default != "foot.desktop" || !reflect.DeepEqual(ids(st.Handlers), []string{"foot.desktop", "kitty.desktop"}) {
		t.Errorf("terminal: %q %v", st.Default, ids(st.Handlers))
	}
	if len(a.State()) != len(Roles) {
		t.Error("State misses a role")
	}
}

func ids(entries []Entry) []string {
	var out []string
	for _, e := range entries {
		out = append(out, e.ID)
	}
	return out
}

func TestSetDefault(t *testing.T) {
	t.Parallel()
	tr := newTree(t)
	tr.standard()
	user := filepath.Join(tr.config, "mimeapps.list")
	tr.write(user, "# mine\n[Added Associations]\ntext/plain=nvim.desktop;\n\n[Default Applications]\nx-scheme-handler/http=chromium.desktop;other.desktop;\ntext/plain=nvim.desktop;\n")
	if err := tr.load().SetDefault("browser", "firefox.desktop"); err != nil {
		t.Fatal(err)
	}
	data, _ := os.ReadFile(user)
	want := "# mine\n[Added Associations]\ntext/plain=nvim.desktop;\n\n[Default Applications]\nx-scheme-handler/http=firefox.desktop;chromium.desktop;other.desktop;\ntext/plain=nvim.desktop;\nx-scheme-handler/https=firefox.desktop;\ntext/html=firefox.desktop;\n"
	if string(data) != want {
		t.Errorf("mimeapps.list:\n%s\nwant:\n%s", data, want)
	}
	a := tr.load()
	if a.Default("x-scheme-handler/https") != "firefox.desktop" || a.Default("application/xhtml+xml") != "" {
		t.Error("the browser's types it doesn't declare were set too")
	}
	// A desktop's own list in the config home is the one written
	own := filepath.Join(tr.config, "sway-mimeapps.list")
	tr.write(own, "")
	if err := tr.load("sway").SetDefault("fileManager", "thunar.desktop"); err != nil {
		t.Fatal(err)
	}
	if data, _ := os.ReadFile(own); string(data) != "[Default Applications]\ninode/directory=thunar.desktop;\n" {
		t.Errorf("sway-mimeapps.list: %q", data)
	}
	// The terminal goes first in xdg-terminals.list
	terms := filepath.Join(tr.config, "xdg-terminals.list")
	tr.write(terms, "foot.desktop\n# a note\n")
	if err := tr.load().SetDefault("terminal", "kitty.desktop"); err != nil {
		t.Fatal(err)
	}
	if data, _ := os.ReadFile(terms); string(data) != "kitty.desktop\nfoot.desktop\n# a note\n" {
		t.Errorf("xdg-terminals.list: %q", data)
	}
	if got := tr.load().Terminal(); got != "kitty.desktop" {
		t.Errorf("Terminal = %q", got)
	}
	for _, bad := range []struct{ role, id string }{{"browser", "nope.desktop"}, {"nope", "firefox.desktop"}, {"terminal", "firefox.desktop"}} {
		if err := tr.load().SetDefault(bad.role, bad.id); err == nil {
			t.Errorf("SetDefault(%s, %s) passed", bad.role, bad.id)
		}
	}
	if err := tr.load().SetTypes([]string{"text/plain\n[x]"}, "nvim.desktop"); err == nil {
		t.Error("a type breaking the file passed")
	}
}

func TestArgv(t *testing.T) {
	t.Parallel()
	for _, c := range []struct {
		exec string
		args []string
		want []string
	}{
		{"firefox %u", []string{"https://a"}, []string{"firefox", "https://a"}},
		{"firefox %u", nil, []string{"firefox"}},
		{"thunar %F", []string{"/a", "/b"}, []string{"thunar", "/a", "/b"}},
		{`sh -c "echo \"hi there\" \$HOME"`, nil, []string{"sh", "-c", `echo "hi there" $HOME`}},
		{"app --file=%f %i %%", []string{"/x"}, []string{"app", "--file=/x", "--icon", "app-icon", "%"}},
		{"app", []string{"/x"}, []string{"app", "/x"}},
		{"app %c", nil, []string{"app", "App"}},
	} {
		e := Entry{Name: "App", Icon: "app-icon", Exec: c.exec}
		if got := e.Argv(c.args); !reflect.DeepEqual(got, c.want) {
			t.Errorf("Argv(%q, %q) = %q, want %q", c.exec, c.args, got, c.want)
		}
	}
	if got := unescapeValue(`a\sb\\c\;`); got != `a b\c\;` {
		t.Errorf("unescapeValue = %q", got)
	}
}

func TestCommand(t *testing.T) {
	t.Parallel()
	tr := newTree(t)
	tr.standard()
	tr.write(filepath.Join(tr.config, "mimeapps.list"), "[Default Applications]\nx-scheme-handler/http=firefox.desktop;\ninode/directory=thunar.desktop;\n")
	tr.write(filepath.Join(tr.config, "xdg-terminals.list"), "foot.desktop\n")
	tr.write(filepath.Join(tr.sysData, "mime/globs2"), "50:text/plain:*.txt\n50:image/png:*.png\n55:text/x-readme:README\n50:text/x-c:*.C:cs\n")
	dir := t.TempDir()
	a := tr.load()
	for _, c := range []struct {
		target string
		args   []string
		ov     Overrides
		want   string
	}{
		{"browser", nil, nil, "firefox"},
		{"https://example.com", nil, nil, "firefox https://example.com"},
		{"https://example.com", nil, Overrides{"browser": "librewolf --private"}, "librewolf --private https://example.com"},
		{dir, nil, nil, "thunar " + dir},
		{"fileManager", []string{dir}, Overrides{"fileManager": "nautilus"}, "nautilus " + dir},
		{"terminal", nil, nil, "foot"},
		{"terminal", []string{"htop"}, nil, "foot -- htop"},
		{"terminal", []string{"htop"}, Overrides{"terminal": "kitty --single-instance"}, "kitty --single-instance -e htop"},
		{"notes.TXT", nil, nil, "foot -- nvim notes.TXT"}, // nvim is Terminal=true
		{"photo.png", nil, nil, "gimp photo.png"},         // no default: the first by name
		{"file:///tmp/photo.png", nil, nil, "gimp file:///tmp/photo.png"},
	} {
		got, err := a.Command(c.target, c.args, c.ov)
		if err != nil || strings.Join(got, " ") != c.want {
			t.Errorf("Command(%q, %q, %v) = %q, %v; want %q", c.target, c.args, c.ov, got, err, c.want)
		}
	}
	if got := a.mimeOfName("README"); got != "text/x-readme" {
		t.Errorf("a literal name: %q", got)
	}
	if got := a.mimeOfName("x.c"); got != "" {
		t.Errorf("a case-sensitive glob matched another case: %q", got)
	}
}

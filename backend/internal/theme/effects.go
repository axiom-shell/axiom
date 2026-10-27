package theme

import (
	"bytes"
	"context"
	"net"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
	"github.com/axiom-shell/axiom/backend/internal/theme/integrations"
)

// effect is what an integration does beyond writing its files: adjust
// reshapes a file for the app installed, after keeps the app's own files
// in step and tells it (only with Live).
type effect struct {
	adjust func(r *run, out []byte) []byte
	after  func(r *run)
}

var effects = map[string]effect{
	// bat (and delta) only see themes from bat's cache
	"bat":     {after: live(func(r *run) { r.command("bat", "cache", "--build") })},
	"cava":    {after: live(func(r *run) { signalAll("cava", syscall.SIGUSR2) })},
	"foot":    {adjust: footStyle},
	"ghostty": {after: live(func(r *run) { r.signalFrom("ghostty", "1.2", syscall.SIGUSR2, "ghostty") })},
	"gtk":     {after: gtk},
	"helix": {after: live(func(r *run) {
		// Arch names the binary helix, most others hx
		cmd := "hx"
		if !r.has(cmd) {
			cmd = "helix"
		}
		r.signalFrom(cmd, "23.10", syscall.SIGUSR1, "hx", "helix")
	})},
	"kitty":   {after: live(reloadKitty)},
	"ncspot":  {after: ncspot},
	"nvim":    {after: live(reloadNvim)},
	"qt":      {after: kde},
	"zathura": {after: live(reloadZathura)},
}

func live(f func(*run)) func(*run) {
	return func(r *run) {
		if r.opts.Live {
			f(r)
		}
	}
}

// command runs an installed command; its failure is a warning.
func (r *run) command(name string, args ...string) {
	if r.has(name) {
		if _, err := r.output(name, args...); err != nil {
			r.warn("%s %s: %v", name, strings.Join(args, " "), err)
		}
	}
}

// footStyle asks the installed foot which shape of colors it takes.
func footStyle(r *run, out []byte) []byte {
	if !r.has("foot") {
		return out
	}
	switch {
	case r.footAccepts("[colors-dark]\nbackground=000000\n[colors-light]\nbackground=ffffff\n"):
		return integrations.Foot(out, integrations.FootDarkLight)
	case !r.footAccepts("[colors]\ncursor=000000 ffffff\n"):
		return integrations.Foot(out, integrations.FootCursorSection)
	}
	return out
}

func (r *run) footAccepts(config string) bool {
	f, err := os.CreateTemp("", "axiom-foot-*.ini")
	if err != nil {
		return false
	}
	defer os.Remove(f.Name())
	_, err = f.WriteString(config)
	f.Close()
	if err != nil {
		return false
	}
	_, err = r.output("foot", "--check-config", "--config="+f.Name())
	return err == nil
}

var versionOf = regexp.MustCompile(`(?mi)^\S+ v?([0-9][0-9.]*)`)

// signalFrom signals the processes named names when cmd's version is at
// least min (before it, the signal ends them instead of reloading).
func (r *run) signalFrom(cmd, min string, sig syscall.Signal, names ...string) {
	if !r.has(cmd) {
		return
	}
	out, _ := r.output(cmd, "--version")
	m := versionOf.FindStringSubmatch(out)
	if m == nil || !versionAtLeast(m[1], min) {
		r.opts.Log.Info(cmd+" can't reload on a signal: the colors apply on its next start", "version", strings.TrimSpace(out))
		return
	}
	for _, name := range names {
		signalAll(name, sig)
	}
}

func versionAtLeast(have, want string) bool {
	h, w := strings.Split(have, "."), strings.Split(want, ".")
	for i := range max(len(h), len(w)) {
		var a, b int
		if i < len(h) {
			a, _ = strconv.Atoi(h[i])
		}
		if i < len(w) {
			b, _ = strconv.Atoi(w[i])
		}
		if a != b {
			return a > b
		}
	}
	return true
}

// signalAll signals this user's processes named name (pkill -x).
func signalAll(name string, sig syscall.Signal) {
	entries, _ := os.ReadDir("/proc")
	for _, e := range entries {
		pid, err := strconv.Atoi(e.Name())
		if err != nil {
			continue
		}
		comm, err := os.ReadFile("/proc/" + e.Name() + "/comm")
		info, statErr := os.Stat("/proc/" + e.Name())
		if err != nil || statErr != nil || strings.TrimSpace(string(comm)) != name {
			continue
		}
		if st, ok := info.Sys().(*syscall.Stat_t); ok && int(st.Uid) == os.Getuid() {
			_ = syscall.Kill(pid, sig)
		}
	}
}

// writable: the file a path names, and its folder, can be changed.
func writable(path string) bool {
	return syscall.Access(path, 2) == nil && syscall.Access(filepath.Dir(path), 2) == nil
}

// gtk: says which gtk.css doesn't load the colors (one it created does),
// and live, sets light/dark.
func gtk(r *run) {
	for _, dir := range []string{"gtk-3.0", "gtk-4.0"} {
		path := filepath.Join(r.dirs.Config, dir, "gtk.css")
		if _, created := r.files[path]; created {
			continue
		}
		if data, err := os.ReadFile(path); err == nil && bytes.Contains(data, []byte(integrations.GTKImport)) {
			continue
		}
		if real, err := filepath.EvalSymlinks(path); err == nil && real != path && !writable(real) {
			// A theme's own gtk.css (nwg-look and others link GTK 4's to it)
			r.warn("'%s' is a link to '%s', which you can't change: Apply (in the GTK integration's settings) replaces the link with a file importing it and the colors.", path, real)
		} else {
			r.warn("'%s' doesn't import the colors: add '%s' at its top.", path, integrations.GTKImport)
		}
	}
	if !r.opts.Live || !r.has("gsettings") {
		return
	}
	scheme, theme := "prefer-dark", "adw-gtk3-dark"
	if r.theme.Light {
		scheme, theme = "prefer-light", "adw-gtk3"
	}
	r.command("gsettings", "set", "org.gnome.desktop.interface", "color-scheme", scheme)
	// adw-gtk3 comes as a light and a dark theme, and apps that judge the
	// mode by the theme (Firefox and its forks) follow its name, not
	// color-scheme. Any other theme is the user's to pick.
	current, _ := r.output("gsettings", "get", "org.gnome.desktop.interface", "gtk-theme")
	if current = strings.Trim(strings.TrimSpace(current), "'"); current == "adw-gtk3" || current == "adw-gtk3-dark" {
		r.command("gsettings", "set", "org.gnome.desktop.interface", "gtk-theme", theme)
	}
}

// ncspot: copies the colors between the markers in its config.toml (it
// can't include a file), and live, has it reload.
func ncspot(r *run) {
	config := filepath.Join(r.dirs.Config, "ncspot", "config.toml")
	data, err := os.ReadFile(config)
	if err != nil {
		r.warn("'%s' doesn't exist: turn on the hookup's Apply to add axiom's [theme] block.", config)
		return
	}
	colors := r.files[filepath.Join(r.dirs.State, "axiom", "ncspot-theme.toml")]
	out, own, ok := integrations.SpliceNcspot(data, colors)
	if !ok {
		r.warn("'%s' has no axiom block in its [theme] table: turn on the hookup's Apply to add it.", config)
		return
	}
	if len(own) > 0 {
		r.opts.Log.Info("ncspot: left to your config.toml", "keys", own)
	}
	if !bytes.Equal(out, data) {
		if err := fsx.WriteFile(config, out, 0o644); err != nil {
			r.warn("can't change '%s' (%v): copy axiom's [theme] block from its state file into a config.toml of your own.", config, err)
			return
		}
	}
	if !r.opts.Live {
		return
	}
	socket := filepath.Join(r.runtimeDir(), "ncspot", "ncspot.sock")
	if info, err := os.Stat(socket); err != nil || info.Mode()&os.ModeSocket == 0 {
		return
	}
	conn, err := net.DialTimeout("unix", socket, 2*time.Second)
	if err == nil {
		_ = conn.SetDeadline(time.Now().Add(2 * time.Second))
		_, err = conn.Write([]byte("reload\n"))
		conn.Close()
	}
	if err != nil {
		r.warn("couldn't ask the running ncspot to reload: %v", err)
	}
}

func (r *run) runtimeDir() string {
	if dir := r.opts.Getenv("XDG_RUNTIME_DIR"); dir != "" {
		return dir
	}
	return "/run/user/" + strconv.Itoa(os.Getuid())
}

// sockets are the unix sockets matching a glob.
func sockets(pattern string) []string {
	matches, _ := filepath.Glob(pattern)
	var out []string
	for _, m := range matches {
		if info, err := os.Stat(m); err == nil && info.Mode()&os.ModeSocket != 0 {
			out = append(out, m)
		}
	}
	return out
}

// reloadKitty: every kitty allowing remote control takes the colors.
func reloadKitty(r *run) {
	if !r.has("kitty") {
		return
	}
	file := filepath.Join(r.dirs.Config, "kitty", "axiom.conf")
	reloaded := 0
	for _, s := range sockets("/tmp/kitty-*") {
		if _, err := r.output("kitty", "@", "--to", "unix:"+s, "set-colors", "--all", "--configured", file); err == nil {
			reloaded++
		}
	}
	r.opts.Log.Info("kitty: reloaded the instances allowing remote control", "count", reloaded)
}

// reloadNvim: every Neovim with the axiom_theme module reloads it.
func reloadNvim(r *run) {
	if !r.has("nvim") {
		return
	}
	reloaded := 0
	for _, s := range sockets(filepath.Join(r.runtimeDir(), "nvim.*.0")) {
		// "true" only from an nvim that has the module and reloaded
		out, _ := r.output("nvim", "--server", s, "--remote-expr",
			`luaeval("select(1, pcall(function() require(\"axiom_theme\").reload() end))")`)
		if out = strings.TrimSpace(out); out == "true" || out == "v:true" {
			reloaded++
		}
	}
	r.opts.Log.Info("nvim: reloaded the instances with axiom_theme", "count", reloaded)
}

// bus runs f on a session bus connection, if there is a bus.
func (r *run) bus(f func(ctx context.Context, c *dbus.Conn)) {
	addr, err := dbus.SessionAddress(r.opts.Getenv)
	if err != nil {
		return
	}
	ctx, cancel := context.WithTimeout(r.ctx, 5*time.Second)
	defer cancel()
	c, err := dbus.Dial(ctx, addr, dbus.Options{Log: r.opts.Log})
	if err != nil {
		r.opts.Log.Info("no session bus to reload "+r.key+" through", "err", err)
		return
	}
	defer c.Close()
	f(ctx, c)
}

// reloadZathura: each zathura (a bus name per process) sources its
// zathurarc again.
func reloadZathura(r *run) {
	r.bus(func(ctx context.Context, c *dbus.Conn) {
		reply, err := c.Call(ctx, dbus.BusName, dbus.BusPath, dbus.BusInterface, "ListNames", "")
		if err != nil || len(reply.Body) == 0 {
			return
		}
		names, _ := reply.Body[0].([]string)
		for _, name := range names {
			if strings.HasPrefix(name, "org.pwmt.zathura.PID-") {
				_, _ = c.Call(ctx, name, "/org/pwmt/zathura", "org.pwmt.zathura", "SourceConfig", "")
			}
		}
	})
}

// kde keeps kdeglobals' color groups a copy of Axiom.colors once its
// [General] ColorScheme names it (KDE apps outside Plasma read that copy,
// not the file), and says which apps picked a scheme of their own in
// their color scheme menu, as kdeglobals' [UiSettings] doesn't reach
// them.
func kde(r *run) {
	path := filepath.Join(r.dirs.Config, "kdeglobals")
	kdeglobals, err := os.ReadFile(path)
	if err != nil {
		return
	}
	if integrations.ColorSchemeIn(kdeglobals, "UiSettings") == "Axiom" {
		rcs, _ := filepath.Glob(filepath.Join(r.dirs.Config, "*rc"))
		for _, rc := range rcs {
			data, _ := os.ReadFile(rc)
			if own := integrations.ColorSchemeIn(data, "UiSettings"); own != "" && own != "Axiom" {
				r.warn("'%s' picks its own color scheme (%s): choose Axiom in that app's Settings → Color Scheme to follow axiom's theme.", rc, own)
			}
		}
	}
	if integrations.ColorSchemeIn(kdeglobals, "General") != "Axiom" {
		return
	}
	merged := integrations.MergeKDE(r.files[filepath.Join(r.dirs.Data, "color-schemes", "Axiom.colors")], kdeglobals)
	if bytes.Equal(merged, kdeglobals) {
		return
	}
	if err := fsx.WriteFile(path, merged, 0o644); err != nil {
		r.warn("can't change '%s' (%v): KDE apps keep its colors.", path, err)
		return
	}
	if r.opts.Live {
		// Running KDE apps re-read the palette (KGlobalSettings::PaletteChanged)
		r.bus(func(_ context.Context, c *dbus.Conn) {
			_ = c.Emit("/KGlobalSettings", "org.kde.KGlobalSettings", "notifyChange", "ii", int32(0), int32(0))
		})
	}
}

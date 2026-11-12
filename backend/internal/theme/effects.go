package theme

import (
	"bytes"
	"context"
	"encoding/json"
	"net"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/footprint"
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
	"bat":     {after: live(bat)},
	"cava":    {after: live(func(r *run) { signalAll("cava", syscall.SIGUSR2) })},
	"fcitx5":  {after: live(reloadFcitx5)},
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
	// kitty rereads its whole config on SIGUSR1: no remote control or
	// socket needed
	"kitty":   {after: live(func(r *run) { r.signalFrom("kitty", "0.24", syscall.SIGUSR1, "kitty") })},
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
	const wOK = 2 // access(2)'s W_OK
	return syscall.Access(path, wOK) == nil && syscall.Access(filepath.Dir(path), wOK) == nil
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
	if !r.opts.Live || r.opts.GSettings == nil && !r.has("gsettings") {
		return
	}
	scheme, theme := "prefer-dark", "adw-gtk3-dark"
	if r.theme.Light {
		scheme, theme = "prefer-light", "adw-gtk3"
	}
	r.setting("color-scheme", scheme)
	// adw-gtk3 comes as a light and a dark theme, and apps that judge the
	// mode by the theme (Firefox and its forks) follow its name, not
	// color-scheme. Any other theme is the user's to pick.
	current, _ := r.gsettings("get", gnomeInterface, "gtk-theme")
	if current = strings.Trim(strings.TrimSpace(current), "'"); current == "adw-gtk3" || current == "adw-gtk3-dark" {
		r.setting("gtk-theme", theme)
	}
}

const gnomeInterface = "org.gnome.desktop.interface"

// gsettings runs gsettings (the options' seam, else the installed one).
func (r *run) gsettings(args ...string) (string, error) {
	if r.opts.GSettings != nil {
		return r.opts.GSettings(r.ctx, args...)
	}
	return r.output("gsettings", args...)
}

// setting sets a key of GNOME's interface schema, recorded in the ledger
// first (what it held, what it's set to); a failure is a warning.
func (r *run) setting(key, value string) {
	id, err := r.opts.Ledger.Begin(footprint.Row{Kind: footprint.KindGSetting, Target: footprint.GSettingTarget(gnomeInterface, key), Owner: r.owner},
		r.opts.Ledger.PriorGSetting(r.ctx, func(ctx context.Context, args ...string) (string, error) { return r.gsettings(args...) }, gnomeInterface, key))
	if err != nil {
		r.warn("gsettings %s %s: not set (%v)", gnomeInterface, key, err)
		return
	}
	if _, err := r.gsettings("set", gnomeInterface, key, value); err != nil {
		r.warn("gsettings set %s %s: %v", gnomeInterface, key, err)
		return
	}
	r.opts.Ledger.Done(id, footprint.Raw(value))
}

// bat: its cache is built again (and, undone, once more without the files).
func bat(r *run) {
	argv := []string{"bat", "cache", "--build"}
	if !r.has("bat") {
		return
	}
	id, err := r.opts.Ledger.Begin(footprint.Row{Kind: footprint.KindRebuild, Target: "bat", Owner: r.owner, Wrote: footprint.Raw(argv)}, footprint.PriorAbsent)
	if err != nil {
		r.warn("bat's cache isn't built (%v)", err)
		return
	}
	r.command(argv[0], argv[1:]...)
	r.opts.Ledger.Done(id, footprint.Raw(argv))
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
		id, err := r.opts.Ledger.Begin(footprint.Row{Kind: footprint.KindMarkedBlock, Target: config, Owner: r.owner,
			Wrote: footprint.Raw(footprint.BlockWrote{Begin: integrations.NcspotBegin, End: integrations.NcspotEnd})}, footprint.PriorAbsent)
		if err == nil {
			err = fsx.WriteFile(config, out, 0o644)
		}
		if err == nil {
			r.opts.Ledger.Done(id, nil)
		}
		if err != nil {
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

// reloadFcitx5: a running fcitx5 rereads classicui.conf and its theme.
// Only when it owns its name: the call would otherwise start fcitx5
// through its D-Bus service file.
func reloadFcitx5(r *run) {
	r.bus(func(ctx context.Context, c *dbus.Conn) {
		const name = "org.fcitx.Fcitx5"
		if owner, _ := c.NameOwner(ctx, name); owner != "" {
			_, _ = c.Call(ctx, name, "/controller", "org.fcitx.Fcitx.Controller1", "ReloadAddonConfig", "s", "classicui")
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
	if err := r.mergeKDE(path, kdeglobals, merged); err != nil {
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

// mergeKDE writes kdeglobals with the scheme merged in, recording per key
// what each changed key held before and holds now (ini-groups): an undo
// puts back exactly those keys, each only while it's still as written.
func (r *run) mergeKDE(path string, before, merged []byte) error {
	prior, wrote := integrations.KeysChanged(before, merged)
	id, err := r.opts.Ledger.Begin(footprint.Row{Kind: footprint.KindINIGroups, Target: path, Owner: r.owner}, func() (json.RawMessage, error) {
		return footprint.Raw(prior), nil
	})
	if err != nil {
		return err
	}
	// A later merge's changes join the first's: what the file held before
	// axiom stays the prior
	if old, ok := r.opts.Ledger.Get(id); ok {
		var was, wasWrote integrations.Keys
		_ = json.Unmarshal(old.Prior, &was)
		_ = json.Unmarshal(old.Wrote, &wasWrote)
		prior, wrote = integrations.MergeKeys(was, prior), integrations.MergeWrote(wasWrote, wrote)
		_ = r.opts.Ledger.Amend(id, func(row *footprint.Row) { row.Prior = footprint.Raw(prior) })
	}
	if err := fsx.WriteFile(path, merged, 0o644); err != nil {
		return err
	}
	r.opts.Ledger.Done(id, footprint.Raw(wrote))
	return nil
}

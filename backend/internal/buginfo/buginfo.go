// Package buginfo gathers what a bug report needs to know about this
// machine (`axiom bug-info`, which fills in the binary and the config from
// the daemon): the tree's version, Quickshell's, the running compositor's
// with its monitor count, and the distribution. Nothing personal: no
// monitor names, no paths, no user names.
package buginfo

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/compositor/ipc"
	"github.com/axiom-shell/axiom/backend/internal/compositor/render"
	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/store"
)

// Unknown is what a line says when it couldn't be found out.
const Unknown = "unknown"

// How long each question to a program or the compositor gets
const askTimeout = 5 * time.Second

// Report is the bug report form's "System info", one line each.
type Report struct {
	Axiom      string `json:"axiom"`  // the tree: "clone v1.2.0-3-gabc1234 (branch fix)", "package 1.2.0-1"
	Binary     string `json:"binary"` // the daemon's version, or this binary's when none runs
	Quickshell string `json:"quickshell"`
	Compositor string `json:"compositor"`
	Monitors   string `json:"monitors"` // how many are on
	Distro     string `json:"distro"`
	Config     string `json:"config"`
}

// Compositor is what's asked of the running compositor
// (compositor/ipc's Hypr, Niri and Sway).
type Compositor interface {
	Version(ctx context.Context) (string, error)
	Outputs(ctx context.Context) ([]render.Output, error)
}

// CompositorFromEnv is the compositor the environment names (by its
// socket, as the daemon picks it), nil for none.
func CompositorFromEnv(getenv func(string) string) Compositor {
	if h := ipc.HyprFromEnv(getenv); h != nil {
		return h
	}
	if n := ipc.NiriFromEnv(getenv); n != nil {
		return n
	}
	if s := ipc.SwayFromEnv(getenv); s != nil {
		return s
	}
	return nil
}

// Options are where the machine's lines come from.
type Options struct {
	// Tree is the axiom tree in use
	Tree string
	// Compositor is the one running (nil: none found)
	Compositor Compositor
	// Desktop names the desktop when no compositor was found
	// ($XDG_CURRENT_DESKTOP)
	Desktop string
	// Output runs a program and returns its stdout (git, qs)
	Output func(ctx context.Context, name string, args ...string) (string, error)
	// OSRelease are the os-release files, the first readable one used
	OSRelease []string
}

// Machine fills in the lines about this machine: Axiom, Quickshell,
// Compositor, Monitors and Distro.
func Machine(ctx context.Context, o Options, r *Report) {
	ask := func(name string, args ...string) string {
		actx, cancel := context.WithTimeout(ctx, askTimeout)
		defer cancel()
		out, err := o.Output(actx, name, args...)
		if err != nil {
			return ""
		}
		line, _, _ := strings.Cut(strings.TrimSpace(out), "\n")
		return line
	}
	r.Axiom = treeVersion(o.Tree, ask)
	r.Quickshell = or(ask("qs", "--version"), "not found")
	r.Compositor, r.Monitors = or(o.Desktop, Unknown), Unknown
	if o.Compositor != nil {
		cctx, cancel := context.WithTimeout(ctx, askTimeout)
		defer cancel()
		if v, err := o.Compositor.Version(cctx); err == nil {
			r.Compositor = v
		}
		if outputs, err := o.Compositor.Outputs(cctx); err == nil {
			on := 0
			for _, out := range outputs {
				if !out.Disabled {
					on++
				}
			}
			r.Monitors = fmt.Sprint(on)
		}
	}
	r.Distro = Unknown
	for _, path := range o.OSRelease {
		if data, err := os.ReadFile(path); err == nil {
			r.Distro = or(distro(string(data)), Unknown)
			break
		}
	}
}

// treeVersion says which axiom the tree is: a package's version (its
// .packaged marker), else a clone's git description and branch.
func treeVersion(tree string, ask func(name string, args ...string) string) string {
	if tree == "" {
		return "unknown (no axiom tree found)"
	}
	if data, err := os.ReadFile(filepath.Join(tree, ".packaged")); err == nil {
		line, _, _ := strings.Cut(strings.TrimSpace(string(data)), "\n")
		return "package " + line
	}
	described := ask("git", "-C", tree, "describe", "--tags", "--always", "--dirty")
	if described == "" {
		return "unknown (neither a clone nor a package)"
	}
	if branch := ask("git", "-C", tree, "branch", "--show-current"); branch != "" && branch != "main" {
		return fmt.Sprintf("clone %s (branch %s)", described, branch)
	}
	return "clone " + described
}

// distro is os-release's PRETTY_NAME, else its ID.
func distro(osRelease string) string {
	fields := map[string]string{}
	for line := range strings.Lines(osRelease) {
		if k, v, ok := strings.Cut(strings.TrimSpace(line), "="); ok {
			fields[k] = strings.Trim(v, `"'`)
		}
	}
	return or(fields["PRETTY_NAME"], fields["ID"])
}

// ConfigLine says what the config is: its format, version and compositor
// mode, and whether it loads. cfg is nil when it couldn't be read.
func ConfigLine(cfg *jsonx.Object, st store.State) string {
	switch {
	case st.Missing:
		return "missing (the defaults apply)"
	case cfg == nil:
		return "unreadable"
	}
	format, _ := cfg.Value("format").(float64)
	if format == 0 {
		format = 1
	}
	version, _ := cfg.Value("version").(float64)
	mode, _ := config.Lookup(cfg, config.Keys("Compositor", "mode"))
	if mode == nil {
		mode = "detached"
	}
	verdict := "ok"
	if st.Blocked {
		verdict = fmt.Sprintf("blocked (issues: %d)", len(st.Issues))
	}
	return fmt.Sprintf("format %v, version %v, compositor mode %v, %s", format, version, mode, verdict)
}

func or(s, fallback string) string {
	if s == "" {
		return fallback
	}
	return s
}

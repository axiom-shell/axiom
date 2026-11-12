package daemon

import (
	"context"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/compositor/manager"
	"github.com/axiom-shell/axiom/backend/internal/cursortheme"
	"github.com/axiom-shell/axiom/backend/internal/footprint"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
	"github.com/axiom-shell/axiom/backend/internal/hookup"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/schema"
	"github.com/axiom-shell/axiom/backend/internal/secrets"
	"github.com/axiom-shell/axiom/backend/internal/theme"
	"github.com/axiom-shell/axiom/backend/internal/tree"
	"github.com/axiom-shell/axiom/backend/internal/uninstall"
)

// uninstallPart: what the Settings button "Remove axiom from this system"
// asks (docs/dev/backend/uninstall.md): the plan an uninstall would carry
// out, and starting it, detached, so it outlives this daemon (which it
// quits first).
func (d *Daemon) uninstallPart() part {
	return part{name: "uninstall", methods: d.uninstallMethods}
}

// UninstallPlanResult is the plan, and what the dialog says of the start.
type UninstallPlanResult struct {
	Plan uninstall.Plan `json:"plan"`
	// Log is where the detached uninstall's output goes
	Log string `json:"log"`
	// Packaged: axiom is installed as a package, which the uninstall leaves
	// to the package manager
	Packaged bool `json:"packaged"`
}

// UninstallStartRequest carries the answers to the questions.
type UninstallStartRequest struct {
	Answers uninstall.Answers `json:"answers"`
}

// UninstallStartResult says where the detached uninstall writes.
type UninstallStartResult struct {
	Log string `json:"log"`
}

// uninstallLog is the detached uninstall's output, in the runtime folder
// beside (not in) axiom's own, which the uninstall removes.
const uninstallLog = "axiom-uninstall.log"

func (d *Daemon) uninstallLog() string {
	return filepath.Join(d.opts.Getenv("XDG_RUNTIME_DIR"), uninstallLog)
}

func (d *Daemon) packaged() bool {
	return fsx.IsFile(filepath.Join(d.installTree, ".packaged"))
}

// uninstallOptions are what an uninstall made by this daemon reads: its
// folders, its ledger, the keyring on its bus. The display it runs on isn't
// counted as running.
func (d *Daemon) uninstallOptions() uninstall.Options {
	return uninstall.Options{
		Dirs: d.dirs, Getenv: d.opts.Getenv, Bin: d.installed, Ledger: d.footprint,
		Inferred: func(ctx context.Context) ([]footprint.Row, []footprint.Row) {
			return OfflineInferred(ctx, d.opts.Getenv, d.installTree, d.installed)
		},
		Session: d.sessionSeams(),
		Secrets: uninstall.SecretsSeam{Count: func(ctx context.Context) (int, error) {
			conn, err := d.sessionBus(ctx)
			if err != nil {
				return 0, nil
			}
			defer conn.Close()
			return secrets.Count(ctx, conn)
		}},
		ExcludeDisplay: d.runtime.Display, Log: d.opts.Log.With("part", "uninstall"),
	}
}

func (d *Daemon) uninstallMethods(reg *rpc.Registry) {
	rpc.Handle(reg, "uninstall.plan", func(ctx context.Context, c *rpc.Conn, _ struct{}) (UninstallPlanResult, error) {
		if !fromShell(c) {
			return UninstallPlanResult{}, axerr.New(axerr.Refused, "only the shell asks what an uninstall would do")
		}
		plan, err := uninstall.Build(ctx, d.uninstallOptions())
		return UninstallPlanResult{Plan: plan, Log: d.uninstallLog(), Packaged: d.packaged()}, err
	})
	rpc.Handle(reg, "uninstall.start", func(ctx context.Context, c *rpc.Conn, p UninstallStartRequest) (UninstallStartResult, error) {
		if !fromShell(c) {
			return UninstallStartResult{}, axerr.New(axerr.Refused, "only the shell starts an uninstall")
		}
		return d.startUninstall(ctx, p.Answers)
	})
}

// startUninstall writes the answers to a file only this user reads (in the
// runtime folder) and starts the uninstall detached, its output in the
// log: install.sh --uninstall for a script install, which also takes the
// install and the binary away, else `axiom uninstall` (a package's files
// are the package manager's). Either quits this daemon first (--stop). One
// at a time: a second start while one runs is refused.
func (d *Daemon) startUninstall(ctx context.Context, a uninstall.Answers) (UninstallStartResult, error) {
	if !d.uninstalling.CompareAndSwap(false, true) {
		return UninstallStartResult{}, axerr.New(axerr.Conflict, "an uninstall is already running")
	}
	started := false
	defer func() {
		if !started {
			d.uninstalling.Store(false)
		}
	}()
	rt := d.opts.Getenv("XDG_RUNTIME_DIR")
	if !filepath.IsAbs(rt) {
		return UninstallStartResult{}, axerr.New(axerr.Unavailable, "no runtime folder to keep the answers in")
	}
	data, err := json.Marshal(a)
	if err != nil {
		return UninstallStartResult{}, err
	}
	f, err := os.CreateTemp(rt, "axiom-uninstall-answers-*.json")
	if err != nil {
		return UninstallStartResult{}, axerr.Wrap(axerr.Unavailable, err, "saving the answers")
	}
	_, werr := f.Write(data)
	f.Close()
	if werr != nil {
		os.Remove(f.Name())
		return UninstallStartResult{}, axerr.Wrap(axerr.Unavailable, werr, "saving the answers")
	}
	argv := []string{d.installed, "uninstall", "--stop", "--yes", "--answers", f.Name()}
	if script := filepath.Join(d.installTree, "install.sh"); !d.packaged() && fsx.IsFile(script) {
		argv = []string{"bash", script, "--uninstall", "--yes", "--answers", f.Name()}
	}
	// Looked for here: a program that doesn't start can't be told by the
	// detached start
	if _, err := exec.LookPath(argv[0]); err != nil {
		os.Remove(f.Name())
		return UninstallStartResult{}, axerr.Wrap(axerr.Unavailable, err, "starting %s", argv[0])
	}
	log := d.uninstallLog()
	if err := d.sessionSeams().SpawnTo(ctx, argv, nil, "", log); err != nil {
		os.Remove(f.Name())
		return UninstallStartResult{}, err
	}
	started = true
	d.opts.Log.Info("uninstall: started", "argv", argv, "log", log)
	return UninstallStartResult{Log: log}, nil
}

// OfflineInferred is what the ledger's backfill finds without the shell to
// say where to look: the hookup targets of the built schema's x-hookup (the
// ThemeIntegrations' switches), the lines of each compositor's include and
// autostart, and the screen-share picker's, for each compositor; and the
// integrations' files and the cursor's folders. Nothing is written.
func OfflineInferred(ctx context.Context, getenv func(string) string, treeDir, bin string) (hookups, files []footprint.Row) {
	req := FootprintBackfillRequest{Targets: map[string]FootprintBackfillTargets{}}
	if data, err := tree.BuildSchema(treeDir); err == nil {
		if root, err := jsonx.Unmarshal(data); err == nil {
			props, _ := schema.Get(schema.Get(schema.Get(root, "properties"), "ThemeIntegrations"), "properties").(*jsonx.Object)
			if props != nil {
				for _, key := range props.Keys() {
					node := props.Value(key)
					var e FootprintBackfillTargets
					if json.Unmarshal(jsonx.MarshalCompact(schema.Get(node, "x-hookup")), &e.Targets) != nil || len(e.Targets) == 0 {
						continue
					}
					json.Unmarshal(jsonx.MarshalCompact(schema.Get(node, "x-profiles")), &e.Profiles)
					e.Owner = "ThemeIntegrations." + key
					req.Targets[key] = e
				}
			}
		}
	}
	for _, kind := range []string{"hyprland", "sway", "niri"} {
		if w, ok := manager.NewOffline(getenv, kind, bin); ok {
			req.Targets["compositor/"+kind] = FootprintBackfillTargets{Targets: w.Targets()}
		}
	}
	req.Targets["screenSharing/hyprland"] = FootprintBackfillTargets{Owner: "ScreenSharing.enabled", Targets: []hookup.Target{{
		File: hookup.Files{"{config}/hypr/xdph.conf"}, Place: hookup.End, Text: "screencopy:custom_picker_binary = " + bin}}}
	req.Targets["screenSharing/sway"] = FootprintBackfillTargets{Owner: "ScreenSharing.enabled", Targets: []hookup.Target{{
		File: hookup.Files{"{config}/xdg-desktop-portal-wlr/config"}, Place: hookup.Section, Section: "screencast",
		Text: "chooser_type = dmenu\nchooser_cmd = '" + bin + "' screenshare-pick --for xdpw"}}}
	in := theme.NewIntegrator(theme.IntegrateOptions{Getenv: getenv, Profiles: func(key string) []string { return req.Targets[key].Profiles }})
	files = in.Existing()
	files = append(files, cursortheme.New(cursortheme.Options{Getenv: getenv, GSettings: gsettings}).Existing(ctx, cursorOwner)...)
	return inferredHookups(getenv, treeDir, req), files
}

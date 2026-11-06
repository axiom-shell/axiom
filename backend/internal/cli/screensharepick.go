package cli

import (
	"bufio"
	"context"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/screenshare"
)

const screenSharePickName = "screenshare-pick"

// The menus xdg-desktop-portal-wlr's default chooser tries, in order, after
// slurp (src/screencast/chooser.c): axiom's falls back to them as it would
var xdpwMenus = []string{
	"wmenu -p 'Select a source to share:' -l 10",
	"wofi -d -n --prompt='Select a source to share:'",
	"rofi -dmenu -p 'Select a source to share:'",
	"bemenu --prompt='Select a source to share:'",
	"mew -l 10 -p 'Select a source to share:'",
	"fuzzel -d -l 10 -p 'Select a source to share:'",
}

func screenSharePickCommand() *Command {
	return &Command{
		Name:    screenSharePickName,
		Summary: "The screen-share picker xdg-desktop-portal-hyprland and -wlr run",
		Hidden:  true,
		Help: `Shows axiom's screen-share picker for a portal and prints its choice
the way the portal reads it. xdg-desktop-portal-hyprland runs the axiom
binary itself as its custom_picker_binary (its environment says so);
xdg-desktop-portal-wlr runs ` + "`axiom screenshare-pick --for xdpw`" + ` as its
dmenu chooser. With axiom's picker off, or no axiom to show it, the
portal's own picker runs instead.`,
		Setup: func(fs *flag.FlagSet) Runner {
			backend := fs.String("for", "", "the portal asking: xdph or xdpw")
			allowToken := fs.Bool("allow-token", false, "xdph: let the app keep a restore token (its allow_token_by_default)")
			return func(ctx context.Context, e *Env, args []string) error {
				switch *backend {
				case screenshare.BackendXDPH:
					return pickXDPH(ctx, e, *allowToken)
				case screenshare.BackendXDPW:
					return pickXDPW(ctx, e)
				}
				return usageError([]string{"axiom", screenSharePickName}, "--for takes xdph or xdpw")
			}
		},
	}
}

// xdphPickerArgs are the arguments to run as xdg-desktop-portal-hyprland's
// picker with, when it ran this binary (args, xdph's own), else nil.
func xdphPickerArgs(args []string, getenv func(string) string) []string {
	if !screenshare.XDPHPicker(args, getenv) {
		return nil
	}
	return append([]string{screenSharePickName, "--for", screenshare.BackendXDPH}, args...)
}

// pickResult is screenshare.pick's result.
type pickResult struct {
	Status   string              `json:"status"`
	Choice   *screenshare.Choice `json:"choice"`
	Remember bool                `json:"remember"`
}

// pick asks the daemon; fallback is true when the portal's own picker
// should answer instead (axiom's is off, or there's no axiom to show it).
func pick(ctx context.Context, e *Env, r screenshare.Request) (res pickResult, fallback bool, err error) {
	params := map[string]any{"backend": r.Backend, "outputs": r.Outputs, "windows": r.Windows, "region": r.Region}
	err = call(ctx, e, "screenshare.pick", params, &res)
	switch {
	case ctx.Err() != nil:
		return res, false, ctx.Err()
	case err != nil:
		fmt.Fprintln(e.Stderr, "axiom: no screen-share picker, the portal's own instead:", err)
		return res, true, nil
	}
	return res, res.Status == "off", nil
}

func pickXDPH(ctx context.Context, e *Env, allowToken bool) error {
	r := screenshare.XDPHRequest(e.Getenv)
	res, fallback, err := pick(ctx, e, r)
	if err != nil {
		return err
	}
	if fallback {
		var args []string
		if allowToken {
			args = []string{"--allow-token"}
		}
		return runFallback(ctx, e, "hyprland-share-picker", args, nil)
	}
	if res.Status == "picked" {
		fmt.Fprint(e.Stdout, screenshare.XDPHSelection(r, res.Choice, res.Remember || allowToken))
	}
	return nil
}

func pickXDPW(ctx context.Context, e *Env) error {
	var lines []string
	sc := bufio.NewScanner(e.Stdin)
	for sc.Scan() {
		if line := sc.Text(); line != "" {
			lines = append(lines, line)
		}
	}
	r, labels := screenshare.XDPWRequest(lines)
	res, fallback, err := pick(ctx, e, r)
	if err != nil {
		return err
	}
	if !fallback {
		if label := screenshare.XDPWLabel(labels, res.Choice); res.Status == "picked" && label != "" {
			fmt.Fprintln(e.Stdout, label)
		}
		return nil
	}
	// xdpw's default chooser: slurp for monitors alone, else a menu
	if _, err := exec.LookPath("slurp"); err == nil && len(r.Windows) == 0 {
		var out strings.Builder
		if err := runFallback(ctx, e, "slurp", []string{"-f", "%o", "-or"}, &out); err != nil {
			return err
		}
		if label := screenshare.XDPWMonitorLabel(labels, out.String()); label != "" {
			fmt.Fprintln(e.Stdout, label)
		}
		return nil
	}
	for _, menu := range xdpwMenus {
		if _, err := exec.LookPath(strings.Fields(menu)[0]); err != nil {
			continue
		}
		cmd := exec.CommandContext(ctx, "/bin/sh", "-c", menu)
		cmd.Stdin = strings.NewReader(strings.Join(lines, "\n") + "\n")
		cmd.Stderr = e.Stderr
		out, err := cmd.Output()
		if err != nil {
			// A menu closed without a pick exits 1: a cancel
			return nil
		}
		first, _, _ := strings.Cut(string(out), "\n")
		if first != "" {
			fmt.Fprintln(e.Stdout, first)
		}
		return nil
	}
	return axerr.New(axerr.Unavailable, "no screen-share picker: install slurp or a menu (wmenu, wofi, rofi, fuzzel, …)")
}

// runFallback runs the portal's own picker, its output to out (stdout when
// nil).
func runFallback(ctx context.Context, e *Env, name string, args []string, out *strings.Builder) error {
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Stdin = e.Stdin
	cmd.Stdout = e.Stdout
	if out != nil {
		cmd.Stdout = out
	}
	cmd.Stderr = e.Stderr
	cmd.Env = os.Environ()
	err := cmd.Run()
	var exit *exec.ExitError
	if errors.As(err, &exit) {
		// Its own exit, its own answer (a cancel prints nothing)
		return nil
	}
	if err != nil {
		return axerr.Wrap(axerr.Unavailable, err, "running %s", name)
	}
	return nil
}

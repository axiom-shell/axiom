package cli

import (
	"context"
	"encoding/json"
	"flag"
	"os"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/greeterinstall"
	"github.com/axiom-shell/axiom/backend/internal/greeterinstall/rules"
)

// greeterInstallName is the command root runs through pkexec: Main hands
// it over before anything else (no log file, XDG folder or daemon socket
// of the user's is touched as root).
const greeterInstallName = "greeter-install"

func greeterInstallCommand() *Command {
	return &Command{
		Name:    greeterInstallName,
		Summary: "Install, update or remove axiom's login screen, as root (pkexec)",
		Args:    "install|update|uninstall REPO USER [STAGED [SOURCE [CHANNEL [BINARY]]]]",
		Hidden:  true,
		Help: `What scripts/greeter/greeter_install.sh runs as root, through pkexec
(the daemon's greeter.apply): copies axiom for greetd's user to
/usr/share/axiom-greeter from SOURCE (git, on CHANNEL tags or main;
local, the clone REPO as it is, with BINARY; package), snapshots the
STAGED bundle, points greetd's default_session at it and installs the
polkit action; uninstall puts greetd's config back and removes it all.
Prints one JSON object: { ok, changed, backup, error }. An update is
run by the copy it replaces, so these arguments are a contract between
versions. Every path is under $AXIOM_GREETER_ROOT, for tests: never
run it against the real / to test.`,
		Setup: func(fs *flag.FlagSet) Runner {
			return func(ctx context.Context, e *Env, args []string) error {
				if code := greeterInstall(ctx, e, args); code != 0 {
					return axerr.New(axerr.Internal, "the login screen's %s failed", firstArg(args))
				}
				return nil
			}
		},
	}
}

// greeterInstall runs one install, update or uninstall and prints its
// result: the exit code is 1 when it failed.
func greeterInstall(ctx context.Context, e *Env, args []string) int {
	var result rules.Result
	req, err := rules.ParseArgs(args)
	if err != nil {
		result = rules.Result{Changed: []string{}, Error: err.Error()}
	} else {
		in := greeterinstall.New(greeterinstall.Options{
			Root:     e.Getenv("AXIOM_GREETER_ROOT"),
			Releases: e.Getenv("AXIOM_GREETER_RELEASES"),
			Getenv:   e.Getenv,
			Environ:  os.Environ,
		})
		result = in.Run(ctx, req)
	}
	enc := json.NewEncoder(e.Stdout)
	enc.SetEscapeHTML(false)
	_ = enc.Encode(result)
	if !result.OK {
		return 1
	}
	return 0
}

func firstArg(args []string) string {
	if len(args) == 0 {
		return ""
	}
	return args[0]
}

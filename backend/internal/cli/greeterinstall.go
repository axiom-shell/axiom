package cli

import (
	"context"
	"encoding/json"
	"os"

	"github.com/axiom-shell/axiom/backend/internal/greeterinstall"
	"github.com/axiom-shell/axiom/backend/internal/greeterinstall/rules"
)

// greeterInstallName is the command root runs through pkexec (hidden: no
// Command of Root's): Main hands it over before anything else, so no log
// file, XDG folder or daemon socket of the user's is touched as root.
// `axiom greeter-install install|update|uninstall REPO USER [STAGED
// [SOURCE [CHANNEL [BINARY]]]]` prints one JSON object, { ok, changed,
// backup, error }; an update is run by the copy it replaces, so these
// arguments are a contract between versions. Every path is under
// $AXIOM_GREETER_ROOT, for tests: never run it against the real / to test.
const greeterInstallName = "greeter-install"

// greeterInstall runs one install, update or uninstall and prints its
// result: the exit code is 1 when it failed.
func greeterInstall(ctx context.Context, e *Env, args []string) int {
	var result rules.Result
	req, err := rules.ParseArgs(args)
	if err != nil {
		result = rules.Result{Changed: []string{}, Error: err.Error()}
	} else {
		in := greeterinstall.New(greeterinstall.Options{
			Root:    e.Getenv("AXIOM_GREETER_ROOT"),
			Getenv:  e.Getenv,
			Environ: os.Environ,
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

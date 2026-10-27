package greeterinstall

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os/exec"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/greeterinstall/rules"
)

// pkexecDismissed is pkexec's exit code when its prompt was dismissed.
const pkexecDismissed = 126

// Elevated is a run as root as the shell hears of it.
type Elevated struct {
	rules.Result
	// The password prompt was dismissed (nothing ran)
	Dismissed bool `json:"dismissed"`
}

// Elevate runs req as root through pkexec, one password prompt: root's
// own helper once it's installed (its polkit action's prompt says what
// it's for), else first, the program that installs it. It runs to the
// end once started, whatever ctx does.
func (in *Installer) Elevate(ctx context.Context, req rules.Request, first []string) (Elevated, error) {
	ctx = context.WithoutCancel(ctx)
	program := first
	if helper, binaries := in.helper(); helper && binaries {
		program = []string{in.path(HelperPath)}
	}
	args := append(append([]string{}, program[1:]...), req.Args()...)
	cmd := exec.CommandContext(ctx, in.opts.Pkexec, append([]string{program[0]}, args...)...)
	cmd.Env = in.opts.Environ()
	var out, errOut bytes.Buffer
	cmd.Stdout, cmd.Stderr = &out, &errOut
	err := cmd.Run()
	var exit *exec.ExitError
	if err != nil && !errors.As(err, &exit) {
		return Elevated{}, fmt.Errorf("running pkexec: %w", err)
	}
	if exit != nil && exit.ExitCode() == pkexecDismissed {
		return Elevated{Dismissed: true}, nil
	}
	var r Elevated
	if jerr := json.Unmarshal(bytes.TrimSpace(out.Bytes()), &r.Result); jerr != nil || (!r.OK && r.Error == "") {
		// Nothing of the installer's: pkexec's own reason (no agent, not
		// authorized)
		r.OK = false
		r.Error = firstLine(strings.TrimSpace(errOut.String()))
		if r.Error == "" {
			r.Error = fmt.Sprintf("pkexec failed (%d)", cmd.ProcessState.ExitCode())
		}
	}
	if exit != nil {
		r.OK = false
	}
	return r, nil
}

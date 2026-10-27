package greeterinstall

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
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
// it's for), else a binary root may run (firstProgram), own being the one
// this user built. A refusal is the reply's error, before any prompt. It
// runs to the end once started, whatever ctx does.
func (in *Installer) Elevate(ctx context.Context, req rules.Request, own string) (Elevated, error) {
	ctx = context.WithoutCancel(ctx)
	program := []string{in.path(HelperPath)}
	if helper, binaries := in.helper(); !helper || !binaries {
		binary, cleanup, err := in.firstProgram(ctx, req, own)
		if err != nil {
			var f failure
			if errors.As(err, &f) {
				return Elevated{Result: rules.Result{Changed: []string{}, Error: f.Error()}}, nil
			}
			return Elevated{}, err
		}
		defer cleanup()
		program = []string{binary, "greeter-install"}
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

// firstProgram is the axiom binary pkexec runs before root has a helper of
// its own: one root owns, or one checked against its release's SHA256SUMS
// before anything runs as root (maintainer, 2026-10-27: "root owned
// checksum verified binary"). A package's is root's own; git's is the
// newest release's prebuilt one, downloaded to a folder of this user's
// and verified (cleanup removes it); local reuses own, the binary this
// user built, unchecked. Anything else is refused ("Refuse the install
// (except for if you have the local clone install path selected, in which
// case it reuses your most recently built binary, and skips the
// checksum)"): the main channel, a release with no binary for this
// machine, a remote that isn't GitHub's.
func (in *Installer) firstProgram(ctx context.Context, req rules.Request, own string) (string, func(), error) {
	none := func() {}
	switch req.Source {
	case rules.SourceLocal:
		if own == "" {
			return "", none, failf("no axiom binary of yours to run")
		}
		return own, none, nil
	case rules.SourcePackage:
		binary := in.path("/usr/bin/axiom")
		if !in.rootOwned(binary) {
			return "", none, failf("%s isn't root's: install axiom's package", binary)
		}
		return binary, none, nil
	}
	if req.Channel == rules.ChannelMain {
		return "", none, failf("the main channel has no release binary to check: set the login screen up from the newest release, or from Local")
	}
	url := in.git(req.Repo, nil).upstreamURL(ctx, in.origin())
	if url == "" {
		return "", none, failf("%s has no remote to fetch axiom from", req.Repo)
	}
	target, ok := in.remoteTarget(ctx, url, req.Channel)
	if !ok {
		return "", none, failf("nothing to fetch from %s on the %s channel (offline?)", url, req.Channel)
	}
	dir, err := os.MkdirTemp("", "axiom-greeter-")
	if err != nil {
		return "", none, err
	}
	cleanup := func() { os.RemoveAll(dir) }
	binary := filepath.Join(dir, "axiom")
	ok, err = in.releaseBinary(ctx, url, target, binary)
	if err == nil && !ok {
		err = failf("%s has no release binary to check for this machine: the login screen installs only a release's, or yours from Local", target.Name())
	}
	if err != nil {
		cleanup()
		return "", none, err
	}
	return binary, cleanup, nil
}

// rootOwned says whether only root can change a file: root's, and
// writable by no one else (on a test root: the user running the tests).
func (in *Installer) rootOwned(path string) bool {
	info, err := os.Stat(path)
	owner, ok := ownerOf(path)
	want := 0
	if in.root != "" {
		want = os.Getuid()
	}
	return err == nil && ok && owner == want && info.Mode().IsRegular() && info.Mode().Perm()&0o022 == 0
}

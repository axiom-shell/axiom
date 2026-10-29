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
	"runtime"
	"strings"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/greeterinstall/rules"
	"github.com/axiom-shell/axiom/backend/internal/release"
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
// it's for), else a binary root may run (firstProgram). A refusal is the reply's error, before any prompt. It
// runs to the end once started, whatever ctx does. authorized (nil: none)
// is called once the password was given and the program runs as root.
func (in *Installer) Elevate(ctx context.Context, req rules.Request, authorized func()) (Elevated, error) {
	ctx = context.WithoutCancel(ctx)
	program := []string{in.path(HelperPath)}
	var stdin []byte
	// An older helper doesn't install the binary, or refuses main
	helper, binaries := in.helper()
	if !helper || !binaries || (req.Source == rules.SourceGit && req.Channel == rules.ChannelMain && !in.helperSays(edgeMarker)) {
		var err error
		if program, stdin, err = in.firstProgram(ctx, req); err != nil {
			var f failure
			if errors.As(err, &f) {
				return Elevated{Result: rules.Result{Changed: []string{}, Error: f.Error()}}, nil
			}
			return Elevated{}, err
		}
	}
	cmd := exec.CommandContext(ctx, in.opts.Pkexec, append(program, req.Args()...)...)
	cmd.Env = in.opts.Environ()
	cmd.Stdin = bytes.NewReader(stdin)
	var out, errOut bytes.Buffer
	cmd.Stdout, cmd.Stderr = &out, &errOut
	err := cmd.Start()
	if err == nil {
		done := make(chan struct{})
		if authorized != nil {
			go watchAuthorized(cmd.Process.Pid, in.opts.Pkexec, authorized, done)
		}
		err = cmd.Wait()
		close(done)
	}
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

// watchAuthorized calls authorized once pid stops being pkexec: pkexec
// execs its program only once the password was given, so a process
// named for something else is that program running as root. It stops
// when done closes.
func watchAuthorized(pid int, pkexec string, authorized func(), done <-chan struct{}) {
	name := filepath.Base(pkexec)
	name = name[:min(len(name), 15)] // the kernel's TASK_COMM_LEN
	tick := time.NewTicker(200 * time.Millisecond)
	defer tick.Stop()
	for {
		select {
		case <-done:
			return
		case <-tick.C:
		}
		comm, err := os.ReadFile(fmt.Sprintf("/proc/%d/comm", pid))
		if err == nil && strings.TrimSpace(string(comm)) != name {
			authorized()
			return
		}
	}
}

// firstProgram is what pkexec runs before root has a helper of its own
// (or, for main, while its helper is older than main's builds): a binary
// root owns, or one checked against its release's SHA256SUMS (maintainer,
// 2026-10-27: "root owned checksum verified binary"). A package's is
// root's own; local reuses req.Binary, the one this user's daemon runs,
// unchecked. git's is the channel's official build (the newest release's,
// or main's newest, the edge prerelease's: "Allow via CI build
// (Recommended)"), downloaded here and handed to root on stdin, which
// checks it against the SHA256SUMS root fetches itself (verifyAndRun):
// this user supplies the bytes, never the sum they're checked against.
// Anything else is refused ("Refuse the install (except for if you have
// the local clone install path selected, in which case it reuses your
// most recently built binary, and skips the checksum)"): a channel with no
// build for this machine.
func (in *Installer) firstProgram(ctx context.Context, req rules.Request) ([]string, []byte, error) {
	switch req.Source {
	case rules.SourceLocal:
		if req.Binary == "" {
			return nil, nil, failf("no axiom binary of yours to run")
		}
		return []string{req.Binary, "greeter-install"}, nil, nil
	case rules.SourcePackage:
		binary := in.path("/usr/bin/axiom")
		if !in.rootOwned(binary) {
			return nil, nil, failf("%s isn't root's: install axiom's package", binary)
		}
		return []string{binary, "greeter-install"}, nil, nil
	}
	url := in.upstream()
	target, ok := in.remoteTarget(ctx, url, req.Channel)
	if !ok {
		return nil, nil, failf("nothing to fetch from %s on the %s channel (offline?)", url, req.Channel)
	}
	data, sums, err := in.releaseBinary(ctx, target)
	if err != nil {
		return nil, nil, err
	}
	if data == nil {
		return nil, nil, failf("%s has no official binary to check for this machine: the login screen installs only an official build's, or yours from Local", target.Name())
	}
	asset, _ := release.Asset(runtime.GOARCH)
	return []string{"/bin/sh", "-c", verifyAndRun, "sh", in.varDir(), sums, asset}, data, nil
}

// verifyAndRun is how root runs a release binary the user's daemon
// downloaded: its bytes (stdin) go into a new folder only root can use,
// made under the greeter's folder ($1, root's own; not /tmp, which may be
// mounted noexec), and are checked there against the sum for asset ($3)
// in the SHA256SUMS root fetches from the official release ($2), then
// run. The folder is removed when it's done.
const verifyAndRun = `set -e
umask 077
mkdir -p "$1"
if [ -L "$1" ] || [ ! -O "$1" ]; then echo "$1 is a link or isn't root's" >&2; exit 1; fi
dir=$(mktemp -d "$1/.install.XXXXXXXX")
trap 'rm -rf "$dir"' EXIT
cat >"$dir/axiom"
sum=$(curl -fsSL --max-time 30 -- "$2" | awk -v f="$3" '$2 == f || $2 == "*" f { print $1; exit }')
echo "$sum  $dir/axiom" | sha256sum -c --status || { echo "the axiom binary doesn't match its release's SHA256SUMS" >&2; exit 1; }
chmod 700 "$dir/axiom"
shift 3
"$dir/axiom" greeter-install "$@"`

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

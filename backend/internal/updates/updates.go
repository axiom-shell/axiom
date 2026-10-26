// Package updates is the pending package updates for the shell, the
// `updates` polled topic: the distribution's own check (the command the
// shell's Packages.updates names, sent with the request) and an AUR
// helper's `-Qua`, parsed into packages. The hub runs one Fetch at a time,
// which matters: concurrent `checkupdates` runs share a temporary sync db
// and fail with "Cannot fetch updates".
package updates

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"os/exec"
	"regexp"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/topics"
)

// Package is one pending update; From is "" where the check doesn't say.
type Package struct {
	Name string `json:"name"`
	From string `json:"from"`
	To   string `json:"to"`
}

// State is what the shell shows (UpdatesManager). Every check ends in
// one, a failed one too (keeping the last packages), so the shell knows
// it's over.
type State struct {
	Repo []Package `json:"repo"`
	AUR  []Package `json:"aur"`
	// Error is why the repo check failed ("" when it didn't)
	Error string `json:"error"`
	At    int64  `json:"at"` // when the check ended (ms since the epoch)
}

// Check is how a distribution checks for updates without root
// (Packages.updates' `check`, `found`, `none` and `format`).
type Check struct {
	Command []string `json:"command"`
	// The exit codes with updates and with none; anything else failed
	// (offline, db locked)
	Found  []int  `json:"found"`
	None   []int  `json:"none"`
	Format string `json:"format"` // "pacman" or "dnf"
}

type request struct {
	Check     *Check `json:"check"`
	AURHelper string `json:"aurHelper"` // "" for no AUR
}

// Parse reads a check's output in format. "pacman": `name from -> to`
// (checkupdates, and an AUR helper's -Qua). "dnf": `name.arch version
// repo` under a heading, skipping installed packages an update obsoletes
// (repo `@…`).
func Parse(format string, out []byte) []Package {
	found := []Package{}
	for line := range strings.SplitSeq(string(out), "\n") {
		f := strings.Fields(line)
		switch format {
		case "pacman":
			if len(f) >= 4 && f[2] == "->" {
				found = append(found, Package{Name: f[0], From: f[1], To: f[3]})
			}
		case "dnf":
			if len(f) == 3 && dnfName.MatchString(f[0]) && !strings.HasPrefix(f[2], "@") {
				found = append(found, Package{Name: f[0][:strings.LastIndexByte(f[0], '.')], To: f[1]})
			}
		}
	}
	return found
}

var dnfName = regexp.MustCompile(`^.+\.[A-Za-z0-9_]+$`)

// An AUR helper is a command name, never a path or anything a shell reads
var helperName = regexp.MustCompile(`^[\w.+-]+$`)

// Options are what the source runs; zero values are the real ones.
type Options struct {
	Log      *slog.Logger
	Now      func() time.Time
	LookPath func(file string) (string, error)
	// Run runs bin with args and returns its stdout, exit code (-1 when it
	// couldn't run or was killed) and stderr
	Run func(ctx context.Context, bin string, args ...string) ([]byte, int, string)
}

// Source is the `updates` topic.
func Source(o Options) topics.Source {
	if o.Log == nil {
		o.Log = slog.New(slog.DiscardHandler)
	}
	if o.LookPath == nil {
		o.LookPath = exec.LookPath
	}
	if o.Run == nil {
		o.Run = run
	}
	if o.Now == nil {
		o.Now = time.Now
	}
	// The last state, and the last failure and helper warned about, so
	// each is said once
	last := State{Repo: []Package{}, AUR: []Package{}}
	var failed, warned string
	// A loop stopped and started again can briefly overlap the old one:
	// its check waits for the cancelled one to end
	var mu sync.Mutex
	return topics.Source{
		Name:    "updates",
		Floor:   topics.MinInterval,
		Default: 30 * time.Minute,
		Fetch: func(ctx context.Context, requests []json.RawMessage) (any, error) {
			mu.Lock()
			defer mu.Unlock()
			var check *Check
			helper := ""
			for _, raw := range requests {
				var r request
				if json.Unmarshal(raw, &r) != nil {
					continue
				}
				if check == nil && r.Check != nil && len(r.Check.Command) > 0 {
					check = r.Check
				}
				if helper == "" && helperName.MatchString(r.AURHelper) {
					helper = r.AURHelper
				}
			}
			st := State{Repo: []Package{}, AUR: []Package{}}
			if check != nil {
				if repo, err := runCheck(ctx, o, check); err != nil {
					st.Repo, st.Error = last.Repo, err.Error()
					if st.Error != failed {
						failed = st.Error
						o.Log.Warn("checking for updates", "err", err)
					}
				} else {
					st.Repo, failed = repo, ""
				}
				st.AUR = aur(ctx, o, helper, &warned)
			}
			st.At = o.Now().UnixMilli()
			last = st
			return st, nil
		},
	}
}

// aur is helper's -Qua; none without a helper or with one not installed
// (said once, through warned).
func aur(ctx context.Context, o Options, helper string, warned *string) []Package {
	if helper == "" {
		return []Package{}
	}
	bin, err := o.LookPath(helper)
	if err != nil {
		if *warned != helper {
			*warned = helper
			o.Log.Warn("the AUR helper is not installed", "helper", helper)
		}
		return []Package{}
	}
	*warned = ""
	// -Qua exits 1 when nothing is outdated
	out, _, _ := o.Run(ctx, bin, "-Qua")
	return Parse("pacman", out)
}

func runCheck(ctx context.Context, o Options, c *Check) ([]Package, error) {
	bin, err := o.LookPath(c.Command[0])
	if err != nil {
		return nil, fmt.Errorf("%s: %w", c.Command[0], err)
	}
	out, code, stderr := o.Run(ctx, bin, c.Command[1:]...)
	if !slices.Contains(c.Found, code) && !slices.Contains(c.None, code) {
		return nil, fmt.Errorf("%s failed (%d): %s", c.Command[0], code, stderr)
	}
	return Parse(c.Format, out), nil
}

func run(ctx context.Context, bin string, args ...string) ([]byte, int, string) {
	// A check that hangs (a stuck mirror) gives way to the next interval
	ctx, cancel := context.WithTimeout(ctx, 5*time.Minute)
	defer cancel()
	var out, errOut bytes.Buffer
	cmd := exec.CommandContext(ctx, bin, args...)
	cmd.Stdout, cmd.Stderr = &out, &errOut
	cmd.WaitDelay = time.Second
	err := cmd.Run()
	code := 0
	if exit, ok := errors.AsType[*exec.ExitError](err); ok {
		code = exit.ExitCode()
	} else if err != nil {
		code = -1
	}
	return out.Bytes(), code, strings.TrimSpace(errOut.String())
}

package binds

import (
	"bytes"
	"context"
	"os"
	"os/exec"
	"runtime/debug"
	"strconv"
	"strings"
	"syscall"
	"time"

	"golang.org/x/sys/unix"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// MemoryLimit caps what reading Hyprland's files may take in a child
// process (Options.Isolate). gopher-lua has no heap limit of its own, and
// a file building a huge string allocates it within one instruction, past
// any check between them: only the kernel can refuse it, and then only
// the child dies, never the daemon (the shell's parent).
const MemoryLimit = 1 << 30

// LimitMemory caps this process's data at limit bytes (RLIMIT_DATA: what
// the Go heap maps), the Go runtime collecting hard well before it. For a
// child that runs files it can't trust to stay small; it can't be undone.
func LimitMemory(limit int64) error {
	debug.SetMemoryLimit(limit / 4 * 3)
	return unix.Setrlimit(unix.RLIMIT_DATA, &unix.Rlimit{Cur: uint64(limit), Max: uint64(limit)})
}

// extractIsolated runs extract in a child: `<Isolate> compositor binds
// extract`, which limits its memory to MemoryLimit before it runs a file
func extractIsolated(ctx context.Context, o Options) (*jsonx.Object, error) {
	args := []string{"compositor", "binds", "extract", "--kind", o.Kind, "--tree", o.Tree,
		"--memory-limit", strconv.Itoa(MemoryLimit)}
	if o.Only != "" {
		args = append(args, "--only", o.Only)
	}
	args = append(args, "--", o.Dir)
	// The files' own timeout, and time to start and answer
	ctx, cancel := context.WithTimeout(ctx, o.Timeout+10*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, o.Isolate, args...)
	var stdout, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	if err := cmd.Run(); err != nil {
		msg := strings.TrimSpace(stderr.String())
		tooBig := axerr.New(axerr.Unavailable, "reading the binds took more than %d MiB, so nothing moved", MemoryLimit>>20)
		switch {
		// The Go runtime's own words when the limit refuses it memory
		case strings.Contains(msg, "out of memory") || strings.Contains(msg, "cannot allocate memory"):
			return nil, tooBig
		case ctx.Err() != nil:
			return nil, axerr.New(axerr.Unavailable, "reading the binds took too long, so nothing moved")
		// Refused memory inside its collector, the runtime may crash
		// instead (a SIGSEGV), with no word of memory
		case diedOfMemory(peakRSS(cmd.ProcessState), ownPeakRSS()):
			return nil, tooBig
		case msg != "":
			// The command line's own error, its first line
			first, _, _ := strings.Cut(msg, "\n")
			return nil, axerr.Wrap(axerr.Unavailable, err, "reading the binds: %s", first)
		}
		return nil, axerr.Wrap(axerr.Unavailable, err, "reading the binds")
	}
	v, err := jsonx.Unmarshal(stdout.Bytes())
	result, ok := v.(*jsonx.Object)
	if err != nil || !ok {
		return nil, axerr.New(axerr.Unavailable, "reading the binds: not the JSON extract prints")
	}
	return result, nil
}

// diedOfMemory tells a child that died of MemoryLimit from one that
// crashed, by its peak RSS (childPeak) against this process's (ownPeak).
// Reading the files takes a few MiB, so a child that held a quarter of the
// limit died of it. But a child started by vfork (as Go starts every one)
// counts the memory its parent held when it exec'd in its own peak, so a
// peak this process may have reached itself tells nothing, and reads as a
// crash.
func diedOfMemory(childPeak, ownPeak int64) bool {
	return childPeak >= MemoryLimit/4 && childPeak > ownPeak
}

// peakRSS is the most memory an ended process held, in bytes (0 if
// unknown)
func peakRSS(ps *os.ProcessState) int64 {
	if ps == nil {
		return 0
	}
	if ru, ok := ps.SysUsage().(*syscall.Rusage); ok {
		return ru.Maxrss << 10 // KiB on Linux
	}
	return 0
}

// ownPeakRSS is the most memory this process has held, in bytes (0 if
// unknown)
func ownPeakRSS() int64 {
	var ru syscall.Rusage
	if syscall.Getrusage(syscall.RUSAGE_SELF, &ru) != nil {
		return 0
	}
	return ru.Maxrss << 10
}

package command

import (
	"bytes"
	"context"
	"os/exec"
	"strings"
	"sync"
	"syscall"
	"time"
)

// A streamed command (`mode: "stream"`, Waybar's continuous scripts): it
// runs through `sh -c` in a process group of its own for as long as
// anyone streams it, and each line it prints is an output, the way a
// poll's whole stdout is.

// What a stream gets: a line keeps its first maxLine bytes; a chatty
// script is published at most once per coalesce (its latest line); one
// that exits restarts after a backoff doubling up to maxBackoff (back to
// the first after a run that lasted that long); stopping it sends the
// group SIGTERM, then SIGKILL after stopGrace; its stderr reaches the log
// at most stderrLines lines per stderrWindow.
const (
	maxLine      = 64 << 10
	coalesce     = 250 * time.Millisecond
	firstBackoff = time.Second
	maxBackoff   = time.Minute
	stopGrace    = 2 * time.Second
	stderrLines  = 5
	stderrWindow = 10 * time.Second
)

// How a streamOnce ended.
type streamEnd int

const (
	streamExited    streamEnd = iota // the command exited
	streamStopped                    // ctx ended or nobody streams it any more
	streamRestarted                  // Restart: killed, to start again at once
)

// stream runs command until ctx ends or no watcher streams it any more,
// restarting it with backoff whenever it exits (a refresh or a restart
// restarts it at once; a restart also starts the backoff over).
func (w *Watches) stream(ctx context.Context, command string, run *watched) {
	backoff := firstBackoff
	stderr := &rateLimited{w: w, command: command}
	for {
		started := w.o.Now()
		exited, end := w.streamOnce(ctx, command, run, stderr)
		switch end {
		case streamStopped:
			return
		case streamRestarted:
			backoff = firstBackoff
			continue
		}
		if exited.Sub(started) >= maxBackoff {
			backoff = firstBackoff
		}
		due := w.o.Until(exited.Add(backoff))
		backoff = min(2*backoff, maxBackoff)
	wait:
		for {
			select {
			case <-ctx.Done():
				return
			case <-run.changed:
				if !w.isStreamed(command) {
					return
				}
			case <-run.refresh:
				break wait
			case <-run.restart:
				backoff = firstBackoff
				break wait
			case <-due:
				break wait
			}
		}
	}
}

// streamOnce runs command once, publishing its lines, until it exits
// (when, streamExited; the exit is published with the last stderr line
// and Exited) or it's stopped (streamStopped: ctx ended or nobody streams
// it any more; streamRestarted: Restart), when its group is killed and
// nothing is published for it.
func (w *Watches) streamOnce(ctx context.Context, command string, run *watched, stderr *rateLimited) (time.Time, streamEnd) {
	// A restart from before this run is no restart of it
	select {
	case <-run.restart:
	default:
	}
	stderr.reset()
	var opts Options
	if w.o.Options != nil {
		opts = w.o.Options()
	}
	cmd := exec.Command("sh", "-c", command)
	cmd.Env = opts.Env
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	var (
		mu      sync.Mutex
		pending *string // the latest line not published yet
	)
	lines := make(chan struct{}, 1)
	stdout := &lineWriter{line: func(l string) {
		mu.Lock()
		pending = &l
		mu.Unlock()
		signal(lines)
	}}
	errw := &lineWriter{line: stderr.log}
	wait, err := start(cmd, opts.Children, true, stdout, errw)
	if err != nil {
		now := w.o.Now()
		w.publish(command, run, "", "", 0, false, startError("sh", err), now)
		return now, streamExited
	}
	exited := make(chan struct{})
	go func() {
		wait()
		close(exited)
	}()
	text, published := "", time.Time{}
	var due <-chan time.Time
	flush := func(exitCode int, errLine string, ended bool) {
		mu.Lock()
		if pending != nil {
			text, pending = *pending, nil
		}
		mu.Unlock()
		published, due = w.o.Now(), nil
		w.publish(command, run, text, errLine, exitCode, ended, nil, published)
	}
	for {
		select {
		case <-ctx.Done():
			stop(cmd, exited)
			return time.Time{}, streamStopped
		case <-run.changed:
			if !w.isStreamed(command) {
				stop(cmd, exited)
				return time.Time{}, streamStopped
			}
		case <-run.restart:
			stop(cmd, exited)
			return time.Time{}, streamRestarted
		case <-run.refresh:
			flush(0, "", false)
		case <-lines:
			if due == nil {
				due = w.o.Until(published.Add(coalesce))
			}
		case <-due:
			flush(0, "", false)
		case <-exited:
			stdout.flush()
			errw.flush() // a last line without a newline
			flush(cmd.ProcessState.ExitCode(), stderr.lastLine(), true)
			return published, streamExited
		}
	}
}

// stop sends cmd's group SIGTERM, then SIGKILL once it exited or after
// stopGrace (a member ignoring SIGTERM), and waits for it.
func stop(cmd *exec.Cmd, exited <-chan struct{}) {
	group := -cmd.Process.Pid
	syscall.Kill(group, syscall.SIGTERM)
	select {
	case <-exited:
	case <-time.After(stopGrace):
	}
	syscall.Kill(group, syscall.SIGKILL)
	<-exited
}

// lineWriter hands each line written to it, without its newline, to
// line, keeping its first maxLine bytes.
type lineWriter struct {
	buf  []byte
	line func(string)
}

func (l *lineWriter) Write(p []byte) (int, error) {
	n := len(p)
	for len(p) > 0 {
		i := bytes.IndexByte(p, '\n')
		chunk := p
		if i >= 0 {
			chunk = p[:i]
		}
		if room := maxLine - len(l.buf); room > 0 {
			l.buf = append(l.buf, chunk[:min(len(chunk), room)]...)
		}
		if i < 0 {
			break
		}
		l.flush()
		p = p[i+1:]
	}
	return n, nil
}

// flush hands on what's left: a last line with no newline (called once
// the writes are over).
func (l *lineWriter) flush() {
	if len(l.buf) > 0 {
		l.line(string(l.buf))
		l.buf = l.buf[:0]
	}
}

// rateLimited logs a stream's stderr lines, at most stderrLines per
// stderrWindow, counting the ones dropped.
type rateLimited struct {
	w        *Watches
	command  string
	since    time.Time
	n, drops int
	mu       sync.Mutex
	last     string // the latest non-empty line, however many were dropped
}

// reset forgets the last line (a new run starts).
func (r *rateLimited) reset() {
	r.mu.Lock()
	r.last = ""
	r.mu.Unlock()
}

// lastLine is the latest non-empty line this run wrote, cut for an entry.
func (r *rateLimited) lastLine() string {
	r.mu.Lock()
	defer r.mu.Unlock()
	return lastLine(r.last)
}

func (r *rateLimited) log(line string) {
	if strings.TrimSpace(line) != "" {
		r.mu.Lock()
		r.last = line
		r.mu.Unlock()
	}
	if now := r.w.o.Now(); now.Sub(r.since) >= stderrWindow {
		if r.drops > 0 {
			r.w.o.Log.Warn("a streamed command's stderr lines were dropped", "command", r.command, "lines", r.drops)
		}
		r.since, r.n, r.drops = now, 0, 0
	}
	if r.n++; r.n > stderrLines {
		r.drops++
		return
	}
	r.w.o.Log.Warn("a streamed command's stderr", "command", r.command, "line", line)
}

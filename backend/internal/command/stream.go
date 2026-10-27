package command

import (
	"bytes"
	"context"
	"os/exec"
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

// stream runs command until ctx ends or no watcher streams it any more,
// restarting it with backoff whenever it exits (a refresh restarts it at
// once).
func (w *Watches) stream(ctx context.Context, command string, run *watched) {
	backoff := firstBackoff
	stderr := &rateLimited{w: w, command: command}
	for {
		started := w.o.Now()
		exited, ok := w.streamOnce(ctx, command, run, stderr)
		if !ok {
			return
		}
		if exited.Sub(started) >= maxBackoff {
			backoff = firstBackoff
		}
		due := exited.Add(backoff)
		backoff = min(2*backoff, maxBackoff)
	wait:
		for {
			d := due.Sub(w.o.Now())
			if d <= 0 {
				break
			}
			select {
			case <-ctx.Done():
				return
			case <-run.changed:
				if !w.isStreamed(command) {
					return
				}
			case <-run.refresh:
				break wait
			case <-w.o.After(d):
				break wait
			}
		}
	}
}

// streamOnce runs command once, publishing its lines, until it exits
// (when, and true) or it's stopped: ctx ended or nobody streams it any
// more (false), when its group is killed.
func (w *Watches) streamOnce(ctx context.Context, command string, run *watched, stderr *rateLimited) (time.Time, bool) {
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
	cmd.Stdout, cmd.Stderr = stdout, &lineWriter{line: stderr.log}
	cmd.WaitDelay = pipeWait
	if err := cmd.Start(); err != nil {
		now := w.o.Now()
		w.publish(command, run, "", 0, startError("sh", err), now)
		return now, true
	}
	exited := make(chan struct{})
	go func() {
		cmd.Wait()
		close(exited)
	}()
	text, published := "", time.Time{}
	var due <-chan time.Time
	flush := func(exitCode int) {
		mu.Lock()
		if pending != nil {
			text, pending = *pending, nil
		}
		mu.Unlock()
		published, due = w.o.Now(), nil
		w.publish(command, run, text, exitCode, nil, published)
	}
	for {
		select {
		case <-ctx.Done():
			stop(cmd, exited)
			return time.Time{}, false
		case <-run.changed:
			if !w.isStreamed(command) {
				stop(cmd, exited)
				return time.Time{}, false
			}
		case <-run.refresh:
			flush(0)
		case <-lines:
			if due == nil {
				if d := published.Add(coalesce).Sub(w.o.Now()); d > 0 {
					due = w.o.After(d)
				} else {
					flush(0)
				}
			}
		case <-due:
			flush(0)
		case <-exited:
			stdout.flush()
			flush(cmd.ProcessState.ExitCode())
			return published, true
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
}

func (r *rateLimited) log(line string) {
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

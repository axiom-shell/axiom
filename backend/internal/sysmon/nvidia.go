package sysmon

import (
	"bufio"
	"context"
	"io"
	"os/exec"
	"slices"
	"strconv"
	"strings"
	"time"
)

// An NVIDIA card is read through one `nvidia-smi --loop-ms` for as long as
// anything wants it, not a process per sample: each nvidia-smi starts the
// driver's management library afresh, which costs far more than the
// query. The topic's fetch and the history only read its latest line, so
// a slow or stuck nvidia-smi never holds up a sample.

const (
	// The shortest interval the stream runs at
	streamFloor = 100 * time.Millisecond
	// How long a stream that failed waits before it's started again
	streamRetry = 10 * time.Second
)

// nvidia is the stream's side of the monitor (Monitor.mu).
type nvidia struct {
	// The topic's lease: its interval, until its fetches stop renewing it
	hubEvery time.Duration
	hubUntil time.Time
	// The latest line, and the interval of the stream it came from
	usage, temp int
	at          time.Time
	every       time.Duration
	failedAt    time.Time
	logged      bool
}

// leaseStream is the topic's ask for the GPU: the stream runs at its
// interval until the lease ends.
func (m *Monitor) leaseStream(every time.Duration, until time.Time) {
	m.mu.Lock()
	m.discover()
	if m.sn.nvidia == "" {
		m.mu.Unlock()
		return
	}
	changed := m.gpu.hubEvery != every || !m.o.Now().Before(m.gpu.hubUntil)
	m.gpu.hubEvery, m.gpu.hubUntil = every, until
	m.mu.Unlock()
	if changed {
		m.signal()
	}
}

// streamWant is the interval the stream should run at, 0 for none: the
// history's second while it keeps the GPU, the topic's while its lease
// lasts, never for a card asleep (that would wake it); and whether a
// failed one may start again yet (m.mu held).
func (m *Monitor) streamWant(now time.Time) (every time.Duration, retry bool) {
	if m.sn.nvidia == "" || m.sn.asleep() {
		return 0, false
	}
	if slices.Contains(m.kept(now), GPU) {
		every = historyEvery
	}
	if now.Before(m.gpu.hubUntil) && (every == 0 || m.gpu.hubEvery < every) {
		every = m.gpu.hubEvery
	}
	if every > 0 {
		every = max(every, streamFloor)
	}
	return every, m.gpu.failedAt.IsZero() || now.Sub(m.gpu.failedAt) >= streamRetry
}

// streamProc is a running stream, owned by Run.
type streamProc struct {
	every  time.Duration
	cancel context.CancelFunc
	done   chan struct{}
}

func (p *streamProc) ended() bool {
	select {
	case <-p.done:
		return true
	default:
		return false
	}
}

// stop ends the stream and waits for its reader.
func (p *streamProc) stop() {
	if p != nil {
		p.cancel()
		<-p.done
	}
}

// startStream runs nvidia-smi at every, its reader keeping the latest
// line; nil when it can't start (retried after streamRetry).
func (m *Monitor) startStream(ctx context.Context, every time.Duration) *streamProc {
	m.mu.Lock()
	bin := m.sn.nvidia
	m.gpu.every = every
	m.mu.Unlock()
	sctx, cancel := context.WithCancel(ctx)
	out, err := m.o.NvidiaStream(sctx, bin, every)
	if err != nil {
		cancel()
		m.streamFailed(err)
		return nil
	}
	p := &streamProc{every: every, cancel: cancel, done: make(chan struct{})}
	go func() {
		defer close(p.done)
		lines := bufio.NewScanner(out)
		for lines.Scan() {
			if usage, temp, ok := parseNvidia(lines.Text()); ok {
				m.mu.Lock()
				m.gpu.usage, m.gpu.temp, m.gpu.at = usage, temp, m.o.Now()
				m.gpu.logged = false
				m.mu.Unlock()
			}
			// Each line is also when Run checks the leases
			m.signal()
		}
		// Stopped, or ended by itself; either way it's ended now (a read
		// error leaves it running, and Close waits for it)
		stopped := sctx.Err() != nil
		cancel()
		err := lines.Err()
		if cerr := out.Close(); err == nil {
			err = cerr
		}
		if !stopped {
			if err == nil {
				err = io.ErrUnexpectedEOF
			}
			m.streamFailed(err)
		}
	}()
	return p
}

// streamFailed holds the stream off for streamRetry, logged once until a
// line comes.
func (m *Monitor) streamFailed(err error) {
	m.mu.Lock()
	m.gpu.failedAt = m.o.Now()
	logged := m.gpu.logged
	m.gpu.logged = true
	m.mu.Unlock()
	if !logged {
		m.o.Log.Warn("nvidia-smi stopped; trying again shortly", "err", err)
	}
	m.signal()
}

// parseNvidia reads one "usage, temp" line.
func parseNvidia(line string) (usage, temp int, ok bool) {
	f := strings.Split(line, ",")
	if len(f) < 2 {
		return 0, 0, false
	}
	usage, err1 := strconv.Atoi(strings.TrimSpace(f[0]))
	temp, err2 := strconv.Atoi(strings.TrimSpace(f[1]))
	return usage, temp, err1 == nil && err2 == nil
}

// nvidiaStream is `nvidia-smi` printing the first card's usage and
// temperature every interval, until ctx ends.
func nvidiaStream(ctx context.Context, bin string, every time.Duration) (io.ReadCloser, error) {
	cmd := exec.CommandContext(ctx, bin, "-i", "0", "--query-gpu=utilization.gpu,temperature.gpu", "--format=csv,noheader,nounits", "-lms", strconv.FormatInt(every.Milliseconds(), 10))
	cmd.WaitDelay = time.Second
	out, err := cmd.StdoutPipe()
	if err != nil {
		return nil, err
	}
	if err := cmd.Start(); err != nil {
		return nil, err
	}
	return &cmdOutput{out, cmd}, nil
}

// cmdOutput is a command's output; closing it waits for the command.
type cmdOutput struct {
	io.Reader
	cmd *exec.Cmd
}

func (c *cmdOutput) Close() error { return c.cmd.Wait() }

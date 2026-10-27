package command

import (
	"context"
	"encoding/json"
	"log/slog"
	"strings"
	"sync"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

// The watched commands (CommandManager's acquire and outputs: `exec.watch`,
// `exec.unwatch`, `exec.refresh`). Each distinct command runs through
// `sh -c` in one loop for every subscriber, at the shortest interval any
// of them asked (once, for a command only watched in once mode; as a
// stream, stream.go, for one any of them streams), and not at all without
// subscribers. A subscriber gets one latest-wins push
// carrying every command it watches, since per-command pushes on one
// method would overwrite each other.

// Watch modes and formats.
const (
	ModePoll   = "poll"
	ModeOnce   = "once"
	ModeStream = "stream"
	FormatText = "text"
	FormatJSON = "json"
)

// The interval a poll without one gets, and the shortest anyone gets.
const (
	DefaultInterval = 5 * time.Second
	MinPollInterval = 500 * time.Millisecond
)

// WatchRequest is one subscriber's watch of a command.
type WatchRequest struct {
	Command string `json:"command"` // run by sh -c
	// "poll" (the default: again every interval), "once" (run once,
	// then only on a refresh) or "stream" (run for as long as it's
	// watched, each line it prints an output)
	Mode string `json:"mode"`
	// In ms, for a poll (default 5000, at least 500)
	Interval *float64 `json:"interval"`
	// "text" (the default) or "json": the output is also parsed
	Format string `json:"format"`
}

// Entry is a command's last output.
type Entry struct {
	Text string `json:"text"` // stdout, trimmed
	// The text parsed, when a subscriber asked for json and it parsed
	// (absent for an empty output)
	Value json.RawMessage `json:"value,omitempty"`
	// Why there's no value (the text isn't JSON, which Text keeps) or no
	// output (the command didn't start)
	Error    string `json:"error,omitempty"`
	ExitCode int    `json:"exitCode"`
	// When the output became what it is (ms since the epoch): an unchanged
	// output isn't pushed again
	At int64 `json:"at"`
}

// Outputs is the push: every command the subscriber watches that has run.
type Outputs struct {
	Outputs map[string]Entry `json:"outputs"`
}

// Subscriber is where outputs go: an *rpc.Conn.
type Subscriber interface {
	NotifyLatest(method string, params any) error
}

// WatchOptions configure Watches; the zero Now and Until are the real
// clock, the zero Run is Run with Options, the zero Log discards.
type WatchOptions struct {
	Method  string         // the push's method
	Log     *slog.Logger   // a stream's stderr, rate-limited
	Options func() Options // what each run gets
	// Context bounds every loop; Go runs one on a goroutine its owner
	// waits for
	Context context.Context
	Go      func(func(ctx context.Context))
	Now     func() time.Time
	Until   func(time.Time) <-chan time.Time // fires at that time (at once when past)
	Run     func(ctx context.Context, argv []string) (Result, error)
}

// Watches holds the watched commands and who watches them.
type Watches struct {
	o    WatchOptions
	mu   sync.Mutex
	runs map[string]*watched
	subs map[Subscriber]map[string]WatchRequest
}

// watched is one command's loop, while anyone watches it.
type watched struct {
	cancel           context.CancelFunc
	changed, refresh chan struct{}
	entry            *Entry
}

// NewWatches returns Watches with nothing watched.
func NewWatches(o WatchOptions) *Watches {
	if o.Context == nil {
		o.Context = context.Background()
	}
	if o.Go == nil {
		o.Go = func(fn func(context.Context)) { go fn(o.Context) }
	}
	if o.Log == nil {
		o.Log = slog.New(slog.DiscardHandler)
	}
	if o.Now == nil {
		o.Now = time.Now
	}
	if o.Until == nil {
		o.Until = func(t time.Time) <-chan time.Time { return time.After(time.Until(t)) }
	}
	if o.Run == nil {
		o.Run = func(ctx context.Context, argv []string) (Result, error) {
			var opts Options
			if o.Options != nil {
				opts = o.Options()
			}
			return Run(ctx, opts, argv, nil)
		}
	}
	return &Watches{o: o, runs: map[string]*watched{}, subs: map[Subscriber]map[string]WatchRequest{}}
}

// Watch sets s's watch of a command (replacing its last one) and starts
// the command's loop if s is its first watcher. An output already there
// is pushed to s at once if s didn't watch the command yet.
func (w *Watches) Watch(s Subscriber, r WatchRequest) error {
	if strings.TrimSpace(r.Command) == "" {
		return axerr.New(axerr.BadRequest, "an empty command")
	}
	if r.Mode == "" {
		r.Mode = ModePoll
	}
	if r.Format == "" {
		r.Format = FormatText
	}
	if r.Mode != ModePoll && r.Mode != ModeOnce && r.Mode != ModeStream {
		return axerr.New(axerr.BadRequest, "mode %q isn't poll, once or stream", r.Mode)
	}
	if r.Format != FormatText && r.Format != FormatJSON {
		return axerr.New(axerr.BadRequest, "format %q isn't text or json", r.Format)
	}
	w.mu.Lock()
	defer w.mu.Unlock()
	wasJSON := w.json(r.Command)
	_, had := w.subs[s][r.Command]
	if w.subs[s] == nil {
		w.subs[s] = map[string]WatchRequest{}
	}
	w.subs[s][r.Command] = r
	run := w.runs[r.Command]
	switch {
	case run == nil:
		w.start(r.Command)
		return nil
	case !wasJSON && r.Format == FormatJSON && run.entry != nil:
		// Run again, parsed this time (a run in flight parses already)
		signal(run.refresh)
	default:
		signal(run.changed)
	}
	// A new watcher gets what's there; the parsed value follows
	if !had && run.entry != nil {
		w.push(s)
	}
	return nil
}

// Unwatch drops s's watch of command; the command stops with its last
// watcher.
func (w *Watches) Unwatch(s Subscriber, command string) {
	w.mu.Lock()
	defer w.mu.Unlock()
	w.drop(s, command)
}

// Forget drops every watch of s (a connection that closed).
func (w *Watches) Forget(s Subscriber) {
	w.mu.Lock()
	defer w.mu.Unlock()
	for command := range w.subs[s] {
		w.drop(s, command)
	}
}

// Refresh runs a watched command now. A stream that runs only publishes
// its last line again (parsed, if json was asked for since); one waiting
// out its backoff restarts.
func (w *Watches) Refresh(command string) {
	w.mu.Lock()
	defer w.mu.Unlock()
	if run := w.runs[command]; run != nil {
		signal(run.refresh)
	}
}

func (w *Watches) drop(s Subscriber, command string) {
	if _, ok := w.subs[s][command]; !ok {
		return
	}
	delete(w.subs[s], command)
	if len(w.subs[s]) == 0 {
		delete(w.subs, s)
	}
	run := w.runs[command]
	if w.watched(command) {
		signal(run.changed)
		return
	}
	run.cancel()
	delete(w.runs, command)
}

// watched is whether anyone watches command; w.mu is held.
func (w *Watches) watched(command string) bool {
	for _, cmds := range w.subs {
		if _, ok := cmds[command]; ok {
			return true
		}
	}
	return false
}

// streamed is whether anyone streams command; w.mu is held.
func (w *Watches) streamed(command string) bool {
	for _, cmds := range w.subs {
		if r, ok := cmds[command]; ok && r.Mode == ModeStream {
			return true
		}
	}
	return false
}

// json is whether anyone watching command asked for json; w.mu is held.
func (w *Watches) json(command string) bool {
	for _, cmds := range w.subs {
		if r, ok := cmds[command]; ok && r.Format == FormatJSON {
			return true
		}
	}
	return false
}

// interval is the shortest interval command's polls ask for, false when
// it's only watched once; w.mu is held.
func (w *Watches) interval(command string) (time.Duration, bool) {
	interval, poll := time.Duration(0), false
	for _, cmds := range w.subs {
		r, ok := cmds[command]
		if !ok || r.Mode != ModePoll {
			continue
		}
		d := DefaultInterval
		if r.Interval != nil {
			d = time.Duration(*r.Interval * float64(time.Millisecond))
		}
		d = max(d, MinPollInterval)
		if !poll || d < interval {
			interval, poll = d, true
		}
	}
	return interval, poll
}

// start runs command's loop; w.mu is held.
func (w *Watches) start(command string) {
	ctx, cancel := context.WithCancel(w.o.Context)
	run := &watched{cancel: cancel, changed: make(chan struct{}, 1), refresh: make(chan struct{}, 1)}
	w.runs[command] = run
	w.o.Go(func(context.Context) {
		defer cancel()
		w.loop(ctx, command, run)
	})
}

// loop runs command as its watchers ask, a stream or polls, switching
// when they change.
func (w *Watches) loop(ctx context.Context, command string, run *watched) {
	for ctx.Err() == nil {
		if w.isStreamed(command) {
			w.stream(ctx, command, run)
		} else {
			w.poll(ctx, command, run)
		}
	}
}

func (w *Watches) isStreamed(command string) bool {
	w.mu.Lock()
	defer w.mu.Unlock()
	return w.streamed(command)
}

// poll runs command, then waits for the shortest interval asked since
// that run (again whenever the watches change), or for a refresh; a
// command only watched once waits for a refresh alone. It returns to run
// again, or when a watcher asks for a stream.
func (w *Watches) poll(ctx context.Context, command string, run *watched) {
	ran := w.o.Now()
	res, err := w.o.Run(ctx, []string{"sh", "-c", command})
	if ctx.Err() != nil {
		return
	}
	w.publish(command, run, res.Stdout, res.ExitCode, err, ran)
	for {
		w.mu.Lock()
		interval, poll := w.interval(command)
		streamed := w.streamed(command)
		w.mu.Unlock()
		if streamed {
			return
		}
		var due <-chan time.Time
		if poll {
			due = w.o.Until(ran.Add(interval))
		}
		select {
		case <-ctx.Done():
			return
		case <-run.refresh:
			return
		case <-run.changed:
		case <-due:
			return
		}
	}
}

// publish makes command's entry from its output (a run's stdout, a
// stream's line) and pushes it to its watchers when it differs from the
// last.
func (w *Watches) publish(command string, run *watched, out string, exitCode int, err error, at time.Time) {
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.runs[command] != run {
		return // stopped meanwhile
	}
	e := Entry{Text: strings.TrimSpace(out), ExitCode: exitCode, At: at.UnixMilli()}
	if err != nil {
		e.ExitCode, e.Error = -1, err.Error()
	} else if w.json(command) && e.Text != "" {
		if json.Valid([]byte(e.Text)) {
			e.Value = json.RawMessage(e.Text)
		} else {
			e.Error = "the output isn't JSON"
		}
	}
	if last := run.entry; last != nil && last.Text == e.Text && last.ExitCode == e.ExitCode &&
		last.Error == e.Error && string(last.Value) == string(e.Value) {
		return
	}
	run.entry = &e
	for s, cmds := range w.subs {
		if _, ok := cmds[command]; ok {
			w.push(s)
		}
	}
}

// push sends s every output it watches; w.mu is held.
func (w *Watches) push(s Subscriber) {
	out := Outputs{Outputs: map[string]Entry{}}
	for command := range w.subs[s] {
		if run := w.runs[command]; run != nil && run.entry != nil {
			out.Outputs[command] = *run.entry
		}
	}
	s.NotifyLatest(w.o.Method, out)
}

func signal(ch chan struct{}) {
	select {
	case ch <- struct{}{}:
	default:
	}
}

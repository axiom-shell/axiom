package ipc

import (
	"context"
	"encoding/json"
	"log/slog"
	"sync"
	"time"
)

// Subscriber is where a stream's events go: an *rpc.Conn.
type Subscriber interface {
	Notify(method string, params any) error
}

// NiriStreamsOptions configure NiriStreams; the zero Retry is a second,
// the zero Go runs a plain goroutine, the zero Log discards.
type NiriStreamsOptions struct {
	// The pushes to a subscriber: Started when its stream (re)connects,
	// before the first event (niri's full state); Event with each event as
	// niri wrote it
	Started func(s Subscriber)
	Event   func(s Subscriber, event json.RawMessage)
	Log     *slog.Logger
	// Context bounds every stream; Go runs one on a goroutine its owner
	// waits for
	Context context.Context
	Go      func(func(ctx context.Context))
	Retry   time.Duration
}

// NiriStreams hands niri's event stream to each subscriber watching it
// (niri.watch): a connection to niri of its own per subscriber, so each
// starts with niri's full state, connected again Retry after it drops or
// fails to connect, until Forget.
type NiriStreams struct {
	niri *Niri
	o    NiriStreamsOptions
	mu   sync.Mutex
	// Each subscriber's stream, stopped by its cancel
	subs map[Subscriber]context.CancelFunc
}

// NewNiriStreams returns streams of n with nothing watched.
func NewNiriStreams(n *Niri, o NiriStreamsOptions) *NiriStreams {
	if o.Context == nil {
		o.Context = context.Background()
	}
	if o.Go == nil {
		o.Go = func(fn func(context.Context)) { go fn(o.Context) }
	}
	if o.Log == nil {
		o.Log = slog.New(slog.DiscardHandler)
	}
	if o.Retry == 0 {
		o.Retry = time.Second
	}
	return &NiriStreams{niri: n, o: o, subs: map[Subscriber]context.CancelFunc{}}
}

// Watch starts s's stream; one it already has goes on.
func (w *NiriStreams) Watch(s Subscriber) {
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.subs[s] != nil {
		return
	}
	ctx, stop := context.WithCancel(w.o.Context)
	w.subs[s] = stop
	w.o.Go(func(context.Context) {
		for ctx.Err() == nil {
			err := w.niri.Events(ctx, func() { w.o.Started(s) }, func(line []byte) {
				w.o.Event(s, json.RawMessage(append([]byte(nil), line...)))
			})
			if ctx.Err() != nil {
				return
			}
			w.o.Log.Debug("niri event stream", "err", err)
			select {
			case <-ctx.Done():
			case <-time.After(w.o.Retry):
			}
		}
	})
}

// Forget stops s's stream (a connection that closed).
func (w *NiriStreams) Forget(s Subscriber) {
	w.mu.Lock()
	defer w.mu.Unlock()
	if stop := w.subs[s]; stop != nil {
		stop()
		delete(w.subs, s)
	}
}

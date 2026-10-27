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
// fails to connect, until Unwatch or Forget.
type NiriStreams struct {
	niri *Niri
	o    NiriStreamsOptions
	mu   sync.Mutex
	// Each subscriber's stream (a later Watch replaces it)
	subs map[Subscriber]*niriStream
}

type niriStream struct{ stop context.CancelFunc }

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
	return &NiriStreams{niri: n, o: o, subs: map[Subscriber]*niriStream{}}
}

// Watch starts s's stream, again from niri's full state when it had one.
func (w *NiriStreams) Watch(s Subscriber) {
	w.mu.Lock()
	defer w.mu.Unlock()
	if old := w.subs[s]; old != nil {
		old.stop()
	}
	ctx, stop := context.WithCancel(w.o.Context)
	st := &niriStream{stop: stop}
	w.subs[s] = st
	// Pushes only while this is still s's stream: a replaced one may be
	// reading a line as it's stopped
	current := func(push func()) {
		w.mu.Lock()
		defer w.mu.Unlock()
		if w.subs[s] == st {
			push()
		}
	}
	w.o.Go(func(context.Context) {
		for ctx.Err() == nil {
			err := w.niri.Events(ctx, func() { current(func() { w.o.Started(s) }) }, func(line []byte) {
				event := json.RawMessage(append([]byte(nil), line...))
				current(func() { w.o.Event(s, event) })
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

// Unwatch stops s's stream.
func (w *NiriStreams) Unwatch(s Subscriber) {
	w.mu.Lock()
	defer w.mu.Unlock()
	if st := w.subs[s]; st != nil {
		st.stop()
		delete(w.subs, s)
	}
}

// Forget stops s's stream (a connection that closed).
func (w *NiriStreams) Forget(s Subscriber) { w.Unwatch(s) }

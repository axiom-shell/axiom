package screenshare

import (
	"context"
	"sync"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

// fakeShell records the requests a broker shows, and the ones it closes.
type fakeShell struct {
	mu    sync.Mutex
	shown []Request
	done  []string
	gone  bool
}

func (f *fakeShell) options(now func() time.Time) Options {
	return Options{
		OnRequest: func(r Request) bool {
			f.mu.Lock()
			defer f.mu.Unlock()
			if f.gone {
				return false
			}
			f.shown = append(f.shown, r)
			return true
		},
		OnDone: func(id string) {
			f.mu.Lock()
			defer f.mu.Unlock()
			f.done = append(f.done, id)
		},
		Now: now,
	}
}

func (f *fakeShell) waitShown(t *testing.T, n int) Request {
	t.Helper()
	if !testkit.Eventually(func() bool {
		f.mu.Lock()
		defer f.mu.Unlock()
		return len(f.shown) >= n
	}) {
		t.Fatalf("the shell was shown %d requests, want %d", len(f.shown), n)
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.shown[n-1]
}

func screens(names ...string) Request {
	r := Request{Backend: BackendXDPH, Windows: []Window{{Token: "7", Title: "kitty"}}}
	for _, n := range names {
		r.Outputs = append(r.Outputs, Output{Name: n})
	}
	return r
}

type result struct {
	choice *Choice
	err    error
}

func ask(b *Broker, ctx context.Context, r Request) chan result {
	ch := make(chan result, 1)
	go func() {
		c, err := b.Ask(ctx, r)
		ch <- result{c, err}
	}()
	return ch
}

func await(t *testing.T, ch chan result) result {
	t.Helper()
	select {
	case r := <-ch:
		return r
	case <-time.After(testkit.Bound(5 * time.Second)):
		t.Fatal("Ask didn't return")
		return result{}
	}
}

func TestAnswerAndCancel(t *testing.T) {
	t.Parallel()
	shell := &fakeShell{}
	b := New(shell.options(nil))
	ch := ask(b, context.Background(), screens("DP-1"))
	req := shell.waitShown(t, 1)
	if req.ID == "" {
		t.Fatal("the request has no id")
	}
	if err := b.Answer(req.ID, &Choice{Kind: KindScreen, Output: "DP-1"}, false); err != nil {
		t.Fatal(err)
	}
	if r := await(t, ch); r.err != nil || r.choice == nil || r.choice.Output != "DP-1" {
		t.Fatalf("got %+v", r)
	}
	if err := b.Answer(req.ID, nil, true); axerr.KindOf(err) != axerr.NotFound {
		t.Errorf("answering twice: %v", err)
	}

	ch = ask(b, context.Background(), screens("DP-1"))
	req = shell.waitShown(t, 2)
	if err := b.Answer(req.ID, nil, true); err != nil {
		t.Fatal(err)
	}
	if r := await(t, ch); r.err != nil || r.choice != nil {
		t.Fatalf("a cancel: %+v", r)
	}
}

func TestBadAnswer(t *testing.T) {
	t.Parallel()
	shell := &fakeShell{}
	b := New(shell.options(nil))
	ch := ask(b, context.Background(), screens("DP-1"))
	req := shell.waitShown(t, 1)
	for _, c := range []*Choice{nil, {Kind: "workspace"}} {
		if err := b.Answer(req.ID, c, false); axerr.KindOf(err) != axerr.BadRequest {
			t.Errorf("%+v: %v", c, err)
		}
	}
	// Still waiting for a good one
	b.Answer(req.ID, nil, true)
	await(t, ch)
}

func TestNoShell(t *testing.T) {
	t.Parallel()
	shell := &fakeShell{gone: true}
	b := New(shell.options(nil))
	if _, err := b.Ask(context.Background(), screens("DP-1")); axerr.KindOf(err) != axerr.Unavailable {
		t.Fatalf("got %v", err)
	}
}

func TestShellGoesAway(t *testing.T) {
	t.Parallel()
	shell := &fakeShell{}
	b := New(shell.options(nil))
	ch := ask(b, context.Background(), screens("DP-1"))
	shell.waitShown(t, 1)
	b.Forget()
	if r := await(t, ch); axerr.KindOf(r.err) != axerr.Unavailable {
		t.Fatalf("got %+v", r)
	}
}

func TestAskerGoesAway(t *testing.T) {
	t.Parallel()
	shell := &fakeShell{}
	b := New(shell.options(nil))
	ctx, cancel := context.WithCancel(context.Background())
	ch := ask(b, ctx, screens("DP-1"))
	req := shell.waitShown(t, 1)
	cancel()
	if r := await(t, ch); axerr.KindOf(r.err) != axerr.Unavailable {
		t.Fatalf("got %+v", r)
	}
	shell.mu.Lock()
	defer shell.mu.Unlock()
	if len(shell.done) != 1 || shell.done[0] != req.ID {
		t.Errorf("the shell was told %v closed, want [%s]", shell.done, req.ID)
	}
}

func TestRepeats(t *testing.T) {
	t.Parallel()
	start := time.Unix(1000, 0)
	cases := []struct {
		name   string
		reuse  int
		after  time.Duration
		first  Request
		again  Request
		choice Choice
		reused bool
	}{
		{"within the time", 10, 3 * time.Second, screens("DP-1"), screens("DP-1"), Choice{Kind: KindScreen, Output: "DP-1"}, true},
		{"a window", 10, 3 * time.Second, screens("DP-1"), screens("DP-1"), Choice{Kind: KindWindow, Window: "7"}, true},
		{"too late", 10, 10 * time.Second, screens("DP-1"), screens("DP-1"), Choice{Kind: KindScreen, Output: "DP-1"}, false},
		{"off", 0, time.Second, screens("DP-1"), screens("DP-1"), Choice{Kind: KindScreen, Output: "DP-1"}, false},
		{"the output is gone", 10, time.Second, screens("DP-1"), screens("HDMI-A-1"), Choice{Kind: KindScreen, Output: "DP-1"}, false},
		{"another app", 10, time.Second, withApp(screens("DP-1"), "a"), withApp(screens("DP-1"), "b"), Choice{Kind: KindScreen, Output: "DP-1"}, false},
		{"the same app", 10, time.Second, withApp(screens("DP-1"), "a"), withApp(screens("DP-1"), "a"), Choice{Kind: KindScreen, Output: "DP-1"}, true},
		{"an app that doesn't say", 10, time.Second, withApp(screens("DP-1"), "a"), screens("DP-1"), Choice{Kind: KindScreen, Output: "DP-1"}, true},
		{"another backend", 10, time.Second, screens("DP-1"), Request{Backend: BackendNiri, Outputs: []Output{{Name: "DP-1"}}}, Choice{Kind: KindScreen, Output: "DP-1"}, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			var mu sync.Mutex
			now := start
			clock := func() time.Time { mu.Lock(); defer mu.Unlock(); return now }
			shell := &fakeShell{}
			b := New(shell.options(clock))
			b.Configure(Settings{Enabled: true, Reuse: time.Duration(tc.reuse) * time.Second})
			ch := ask(b, context.Background(), tc.first)
			req := shell.waitShown(t, 1)
			choice := tc.choice
			if err := b.Answer(req.ID, &choice, false); err != nil {
				t.Fatal(err)
			}
			await(t, ch)
			mu.Lock()
			now = now.Add(tc.after)
			mu.Unlock()
			ch = ask(b, context.Background(), tc.again)
			if tc.reused {
				r := await(t, ch)
				if r.err != nil || r.choice == nil || *r.choice != tc.choice {
					t.Fatalf("got %+v, want %+v again", r, tc.choice)
				}
				return
			}
			req = shell.waitShown(t, 2)
			b.Answer(req.ID, nil, true)
			await(t, ch)
		})
	}
}

func withApp(r Request, app string) Request {
	r.AppID = app
	return r
}

// Requests sent at once wait for the first: its answer is reused
func TestRepeatsAtOnce(t *testing.T) {
	t.Parallel()
	shell := &fakeShell{}
	b := New(shell.options(nil))
	b.Configure(Settings{Enabled: true, Reuse: 10 * time.Second})
	first := ask(b, context.Background(), screens("DP-1"))
	req := shell.waitShown(t, 1)
	second := ask(b, context.Background(), screens("DP-1"))
	if err := b.Answer(req.ID, &Choice{Kind: KindScreen, Output: "DP-1"}, false); err != nil {
		t.Fatal(err)
	}
	for _, ch := range []chan result{first, second} {
		if r := await(t, ch); r.err != nil || r.choice == nil || r.choice.Output != "DP-1" {
			t.Fatalf("got %+v", r)
		}
	}
	shell.mu.Lock()
	defer shell.mu.Unlock()
	if len(shell.shown) != 1 {
		t.Errorf("the picker showed %d times", len(shell.shown))
	}
}

// A cancel isn't reused: the next request asks
func TestCancelNotReused(t *testing.T) {
	t.Parallel()
	shell := &fakeShell{}
	b := New(shell.options(nil))
	b.Configure(Settings{Enabled: true, Reuse: 10 * time.Second})
	ch := ask(b, context.Background(), screens("DP-1"))
	b.Answer(shell.waitShown(t, 1).ID, nil, true)
	await(t, ch)
	ch = ask(b, context.Background(), screens("DP-1"))
	b.Answer(shell.waitShown(t, 2).ID, nil, true)
	await(t, ch)
}

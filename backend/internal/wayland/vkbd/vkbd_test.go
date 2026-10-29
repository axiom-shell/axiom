package vkbd

import (
	"context"
	"fmt"
	"io"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/testkit"
	"github.com/axiom-shell/axiom/backend/internal/wayland/client"
	"github.com/axiom-shell/axiom/backend/internal/wayland/seat"
	"github.com/axiom-shell/axiom/backend/internal/wayland/wire/wiretest"
)

func TestPlan(t *testing.T) {
	t.Parallel()
	chunks := Plan("aéa\n😀\x07\tb")
	if len(chunks) != 1 {
		t.Fatalf("%d chunks", len(chunks))
	}
	c := chunks[0]
	// a é a Return 😀 Tab b: the bell is left out, a's key reused
	if fmt.Sprint(c.Keys) != "[1 2 1 3 4 5 6]" {
		t.Errorf("keys %v", c.Keys)
	}
	for _, want := range []string{"maximum = 15;", "<K1> = 9;", "key <K1> {[U0061]};", "key <K2> {[U00E9]};", "key <K3> {[Return]};", "key <K4> {[U1F600]};", "key <K5> {[Tab]};"} {
		if !strings.Contains(c.Keymap, want) {
			t.Errorf("keymap lacks %q:\n%s", want, c.Keymap)
		}
	}
	if Plan("\x00\x1b") != nil {
		t.Error("control characters made a chunk")
	}
}

func TestPlanSplitsPastTheKeycodes(t *testing.T) {
	t.Parallel()
	var b strings.Builder
	for r := rune(0x4e00); r < 0x4e00+300; r++ {
		b.WriteRune(r)
	}
	chunks := Plan(b.String())
	if len(chunks) != 2 || len(chunks[0].Keys) != perKeymap || len(chunks[1].Keys) != 300-perKeymap {
		t.Fatalf("chunks of %d and %d keys", len(chunks[0].Keys), len(chunks[1].Keys))
	}
	if chunks[1].Keys[0] != firstKeycode-8 {
		t.Errorf("the second keymap starts at %d", chunks[1].Keys[0])
	}
}

// event is a request the fake keyboard got.
type event struct {
	op      uint16
	keymap  string
	key     uint32
	pressed bool
}

func TestTypeSendsAKeymapThenKeys(t *testing.T) {
	t.Parallel()
	var mu sync.Mutex
	var manager, keyboard uint32
	events := make(chan event, 32)
	f := wiretest.New(t, []wiretest.Global{
		{Name: 1, Interface: "wl_seat", Version: 7},
		{Name: 2, Interface: ifaceManager, Version: 1},
	}, func(c *wiretest.Compositor, r wiretest.Request) {
		mu.Lock()
		defer mu.Unlock()
		switch {
		case r.Interface == ifaceManager:
			manager = r.Args.Uint()
		case r.Interface != "":
		case r.Object == manager && r.Opcode == opCreateKeyboard:
			r.Args.Uint() // seat
			keyboard = r.Args.Uint()
		case r.Object == keyboard && r.Opcode == opKeymap:
			if format := r.Args.Uint(); format != formatXKBv1 {
				t.Errorf("format %d", format)
			}
			fd, err := r.Args.Fd()
			if err != nil {
				t.Error(err)
				return
			}
			size := r.Args.Uint()
			data, _ := io.ReadAll(fd)
			fd.Close()
			if int(size) != len(data) || data[len(data)-1] != 0 {
				t.Errorf("size %d for %d bytes", size, len(data))
			}
			events <- event{op: opKeymap, keymap: string(data)}
		case r.Object == keyboard && r.Opcode == opKey:
			r.Args.Uint() // time
			key, state := r.Args.Uint(), r.Args.Uint()
			events <- event{op: opKey, key: key, pressed: state == pressed}
		case r.Object == keyboard && r.Opcode == opDestroy:
			events <- event{op: opDestroy}
		}
	})
	st := seat.New()
	kb := New(Options{Seat: st})
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- client.Run(ctx, f.Socket, st, kb) }()
	t.Cleanup(func() { cancel(); <-done })
	if !testkit.Eventually(func() bool { return kb.Available() && st.ID() != 0 }) {
		t.Fatal("not bound")
	}

	if err := kb.Type(context.Background(), "hi"); err != nil {
		t.Fatal(err)
	}
	var got []string
	for i := 0; i < 6; i++ {
		select {
		case e := <-events:
			switch e.op {
			case opKeymap:
				if !strings.Contains(e.keymap, "key <K2> {[U0069]};") {
					t.Errorf("keymap %s", e.keymap)
				}
				got = append(got, "keymap")
			case opKey:
				got = append(got, fmt.Sprintf("%d %v", e.key, e.pressed))
			case opDestroy:
				got = append(got, "destroy")
			}
		case <-time.After(testkit.Bound(3 * time.Second)):
			t.Fatalf("got %v", got)
		}
	}
	if want := "[keymap 1 true 1 false 2 true 2 false destroy]"; fmt.Sprint(got) != want {
		t.Errorf("got %v, want %s", got, want)
	}
	if err := kb.Type(context.Background(), strings.Repeat("x", MaxText+1)); err == nil {
		t.Error("an over-long text was typed")
	}
}

func TestTypeWithoutTheProtocol(t *testing.T) {
	t.Parallel()
	kb := New(Options{Seat: seat.New()})
	if err := kb.Type(context.Background(), "x"); err == nil {
		t.Error("typed without a compositor")
	}
}

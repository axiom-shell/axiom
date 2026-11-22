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

func TestPlanKeepsEmojiSequences(t *testing.T) {
	t.Parallel()
	chunks := Plan("❤️👨‍👩‍👧")
	if len(chunks) != 1 {
		t.Fatalf("%d chunks", len(chunks))
	}
	c := chunks[0]
	// 2764 FE0F 1F468 200D 1F469 200D 1F467: seven keys, the joiner's reused
	if fmt.Sprint(c.Keys) != "[1 2 3 4 5 4 6]" {
		t.Errorf("keys %v", c.Keys)
	}
	for _, want := range []string{"key <K1> {[U2764]};", "key <K2> {[UFE0F]};", "key <K4> {[U200D]};"} {
		if !strings.Contains(c.Keymap, want) {
			t.Errorf("keymap lacks %q:\n%s", want, c.Keymap)
		}
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
	mods    uint32
	pressed bool
}

// fakeKeyboard is a Keyboard bound to a fake compositor, and the requests
// that compositor gets on the keyboard it makes.
func fakeKeyboard(t *testing.T) (*Keyboard, chan event) {
	t.Helper()
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
		case r.Object == keyboard && r.Opcode == opModifiers:
			events <- event{op: opModifiers, mods: r.Args.Uint()}
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
	return kb, events
}

// requests reads n requests, as "keymap", "mods 4", "1 true" or "destroy";
// keymaps are checked against wantKey, the key line the text's keymap has.
func requests(t *testing.T, events chan event, n int, wantKey string) []string {
	t.Helper()
	var got []string
	for i := 0; i < n; i++ {
		select {
		case e := <-events:
			switch e.op {
			case opKeymap:
				if !strings.Contains(e.keymap, wantKey) {
					t.Errorf("keymap %s", e.keymap)
				}
				got = append(got, "keymap")
			case opModifiers:
				got = append(got, fmt.Sprintf("mods %d", e.mods))
			case opKey:
				got = append(got, fmt.Sprintf("%d %v", e.key, e.pressed))
			case opDestroy:
				got = append(got, "destroy")
			}
		case <-time.After(testkit.Bound(3 * time.Second)):
			t.Fatalf("got %v", got)
		}
	}
	return got
}

func TestTypeSendsAKeymapThenKeys(t *testing.T) {
	t.Parallel()
	kb, events := fakeKeyboard(t)
	if err := kb.Type(context.Background(), "hi"); err != nil {
		t.Fatal(err)
	}
	// one modifiers request (none held) and none after the last key
	got := requests(t, events, 7, "key <K2> {[U0069]};")
	if want := "[keymap mods 0 1 true 1 false 2 true 2 false destroy]"; fmt.Sprint(got) != want {
		t.Errorf("got %v, want %s", got, want)
	}
	if err := kb.Type(context.Background(), strings.Repeat("x", MaxText+1)); err == nil {
		t.Error("an over-long text was typed")
	}
}

func TestPasteSendsCtrlV(t *testing.T) {
	t.Parallel()
	kb, events := fakeKeyboard(t)
	if err := kb.Paste(context.Background()); err != nil {
		t.Fatal(err)
	}
	got := requests(t, events, 6, "{[U0076]}")
	if want := "[keymap mods 4 1 true 1 false mods 0 destroy]"; fmt.Sprint(got) != want {
		t.Errorf("got %v, want %s", got, want)
	}
}

func TestPasteReleasesCtrlWhenCancelled(t *testing.T) {
	t.Parallel()
	kb, events := fakeKeyboard(t)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	kb.Paste(ctx)
	var got []string
	for len(got) == 0 || got[len(got)-1] != "destroy" {
		got = append(got, requests(t, events, 1, "{[U0076]}")...)
	}
	// what falls between the modifiers and the release depends on the roundtrip
	if n := len(got); n < 4 || fmt.Sprint(got[:2]) != "[keymap mods 4]" || got[n-2] != "mods 0" {
		t.Errorf("got %v", got)
	}
}

func TestTypeWithoutTheProtocol(t *testing.T) {
	t.Parallel()
	kb := New(Options{Seat: seat.New()})
	if err := kb.Type(context.Background(), "x"); err == nil {
		t.Error("typed without a compositor")
	}
}

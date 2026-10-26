package dbus

import (
	"log/slog"
	"os"
	"testing"
)

func TestMatchRuleEscapesQuotes(t *testing.T) {
	t.Parallel()
	m := Match{Interface: "org.freedesktop.DBus", Member: "NameOwnerChanged", Arg0: "it's"}
	want := `type='signal',interface='org.freedesktop.DBus',member='NameOwnerChanged',arg0='it'\''s'`
	if got := m.rule(); got != want {
		t.Errorf("rule() = %s, want %s", got, want)
	}
}

func TestDroppedSignalClosesItsDescriptors(t *testing.T) {
	t.Parallel()
	ch := make(chan *Message) // never read: always behind
	s := &Subscription{C: ch, ch: ch, match: Match{Member: "Sig"}}
	c := &Conn{log: slog.New(slog.DiscardHandler), subs: map[*Subscription]struct{}{s: {}}}
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	defer w.Close()
	m := &Message{Type: TypeSignal, Member: "Sig", Files: []*os.File{r}}
	c.route(m)
	if m.Files[0] != nil {
		t.Error("the dropped signal kept its descriptor")
	}
	if _, err := r.Stat(); err == nil {
		t.Error("the descriptor is still open")
	}
}

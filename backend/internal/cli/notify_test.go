package cli

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/daemon"
	"github.com/axiom-shell/axiom/backend/internal/notification"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
)

// axiom notify sends its flags as notify.send's params, waits when it has
// buttons, and prints the one picked.
func TestNotify(t *testing.T) {
	t.Parallel()
	dir, err := os.MkdirTemp("", "ax") // short: a sockaddr_un
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(dir) })
	sock := filepath.Join(dir, "s.sock")
	ln, err := rpc.Listen(sock)
	if err != nil {
		t.Fatal(err)
	}
	reg := rpc.NewRegistry()
	rpc.Handle(reg, "daemon.hello", func(context.Context, *rpc.Conn, daemon.HelloParams) (daemon.HelloResult, error) {
		return daemon.HelloResult{}, nil
	})
	sent := make(chan notification.Notification, 2)
	rpc.Handle(reg, "notify.send", func(_ context.Context, _ *rpc.Conn, n notification.Notification) (map[string]any, error) {
		sent <- n
		if n.Wait && len(n.Actions) > 0 {
			return map[string]any{"id": 7, "action": n.Actions[1].ID}, nil
		}
		return map[string]any{"id": 7}, nil
	})
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	go (&rpc.Server{Registry: reg}).Serve(ctx, ln)
	root := &Command{Name: "axiom", Subs: []*Command{notifyCommand()}}

	code, out, errOut := run(t, root, "--socket", sock, "notify", "--icon", "info", "--urgency", "critical", "--key", "backup", "--transient",
		"--action", "open=Open", "--action", "later=Later", "Title", "Body")
	n := <-sent
	if code != 0 || out != "later\n" {
		t.Errorf("exit %d, printed %q (%s)", code, out, errOut)
	}
	want := notification.Notification{AppName: "axiom", Summary: "Title", Body: "Body", Icon: "info", Urgency: "critical",
		Key: "backup", Transient: true, Wait: true, Actions: []notification.Action{{ID: "open", Label: "Open"}, {ID: "later", Label: "Later"}}}
	if n.Summary != want.Summary || n.Body != want.Body || n.Icon != want.Icon || n.Urgency != want.Urgency || n.Key != want.Key ||
		!n.Transient || !n.Wait || len(n.Actions) != 2 || n.Actions[0] != want.Actions[0] || n.AppName != "axiom" {
		t.Errorf("sent %+v, want %+v", n, want)
	}
	// Without buttons or --wait it doesn't wait, and prints nothing
	if code, out, _ := run(t, root, "--socket", sock, "notify", "Title"); code != 0 || out != "" || (<-sent).Wait {
		t.Errorf("exit %d, printed %q", code, out)
	}
	for _, bad := range [][]string{{"notify"}, {"notify", "--urgency", "loud", "T"}, {"notify", "--action", "open", "T"}} {
		if code, _, _ := run(t, root, append([]string{"--socket", sock}, bad...)...); code == 0 {
			t.Errorf("%v succeeded", bad)
		}
	}
}

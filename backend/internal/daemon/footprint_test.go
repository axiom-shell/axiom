package daemon

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/buildinfo"
	"github.com/axiom-shell/axiom/backend/internal/footprint"
	"github.com/axiom-shell/axiom/backend/internal/hookup"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

func asShell(pid int) bool { return pid == os.Getpid() }

func TestFootprintRPCs(t *testing.T) {
	t.Parallel()
	td := newTestDaemon(t)
	td.start(t, asShell)
	// The ledger the daemon reads, written the way a recording point does
	l := NewLedger(td.getenv, nil, nil)
	target := filepath.Join(td.env["HOME"], ".config", "kitty", "axiom.conf")
	os.MkdirAll(filepath.Dir(target), 0o755)
	os.WriteFile(target, []byte("x"), 0o644)
	id, err := l.Begin(footprint.Row{Kind: footprint.KindFile, Target: target, Owner: "ThemeIntegrations.kitty"}, footprint.PriorAbsent)
	if err != nil {
		t.Fatal(err)
	}
	l.Done(id, nil)

	// A second connection hears the change
	changed := make(chan struct{}, 4)
	reg := rpc.NewRegistry()
	rpc.Handle(reg, "footprint.changed", func(context.Context, *rpc.Conn, json.RawMessage) (struct{}, error) {
		changed <- struct{}{}
		return struct{}{}, nil
	})
	listener, err := rpc.Dial(context.Background(), td.socket, reg, nil)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { listener.Close() })
	var hello HelloResult
	if err := listener.Call(context.Background(), "daemon.hello", map[string]any{"protocol": buildinfo.Protocol(), "client": "shell", "pid": os.Getpid(), "subscribe": []string{"footprint"}}, &hello); err != nil {
		t.Fatal(err)
	}

	shell, err := td.connect(t, "shell", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	cli, err := td.connect(t, "cli", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	var list FootprintListResult
	if err := cli.Call(ctx, "footprint.list", struct{}{}, &list); err != nil || len(list.Rows) != 1 || list.Rows[0].Status != footprint.StatusPresent || list.Rows[0].Owner != "ThemeIntegrations.kitty" {
		t.Fatalf("list %+v %v", list, err)
	}
	// Only the shell undoes
	if err := cli.Call(ctx, "footprint.undo", map[string]any{"ids": []string{id}}, nil); axerr.KindOf(err) != axerr.Refused {
		t.Errorf("undo from the CLI: %v", err)
	}
	var dry FootprintUndoResult
	if err := shell.Call(ctx, "footprint.undo", map[string]any{"ids": []string{id}, "dryRun": true}, &dry); err != nil || dry.Results[0].Outcome != footprint.OutcomeDone {
		t.Fatalf("dry run %+v %v", dry, err)
	}
	if _, err := os.Stat(target); err != nil {
		t.Fatal("the dry run removed the file")
	}
	var res FootprintUndoResult
	if err := shell.Call(ctx, "footprint.undo", map[string]any{"ids": []string{id}}, &res); err != nil || res.Results[0].Outcome != footprint.OutcomeDone {
		t.Fatalf("undo %+v %v", res, err)
	}
	if _, err := os.Stat(target); err == nil {
		t.Error("the file stayed")
	}
	select {
	case <-changed:
	case <-after(t):
		t.Error("no footprint.changed push")
	}
	// The CLI's note makes the daemon push too
	if err := cli.Call(ctx, "footprint.notify", struct{}{}, nil); err != nil {
		t.Error(err)
	}
	select {
	case <-changed:
	case <-after(t):
		t.Error("no push after footprint.notify")
	}
}

func TestBackfillOnceAndInferred(t *testing.T) {
	t.Parallel()
	td := newTestDaemon(t)
	td.start(t, asShell)
	home := td.env["HOME"]
	kitty := filepath.Join(td.env["XDG_CONFIG_HOME"], "kitty")
	os.MkdirAll(kitty, 0o755)
	os.WriteFile(filepath.Join(kitty, "kitty.conf"), []byte("font_size 12\n\ninclude axiom.conf\n"), 0o644)
	os.WriteFile(filepath.Join(kitty, "kitty.conf.axiom-bak-20260101-000000"), []byte("font_size 12\n"), 0o644)
	os.WriteFile(filepath.Join(kitty, "axiom.conf"), []byte("# colors\n"), 0o644)
	// A user's file with the same line and no trace of axiom
	other := filepath.Join(td.env["XDG_CONFIG_HOME"], "alacritty")
	os.MkdirAll(other, 0o755)
	os.WriteFile(filepath.Join(other, "alacritty.toml"), []byte("[general]\n"), 0o644)
	cursor := filepath.Join(td.env["XDG_DATA_HOME"], "icons", "axiom-cursor-Old")
	os.MkdirAll(cursor, 0o755)
	os.WriteFile(filepath.Join(cursor, "index.theme"), []byte("[Icon Theme]\nX-Axiom-Generated=true\n"), 0o644)

	shell, err := td.connect(t, "shell", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	req := FootprintBackfillRequest{Targets: map[string]FootprintBackfillTargets{
		"kitty":     {Owner: "ThemeIntegrations.kitty", Targets: []hookup.Target{{File: hookup.Files{"{config}/kitty/kitty.conf"}, Place: hookup.End, Text: "include axiom.conf"}}},
		"alacritty": {Owner: "ThemeIntegrations.alacritty", Targets: []hookup.Target{{File: hookup.Files{"{config}/alacritty/alacritty.toml"}, Place: hookup.Top, Text: `import = ["axiom.toml"]`}}},
	}}
	var res FootprintBackfillResult
	ctx := context.Background()
	if err := shell.Call(ctx, "footprint.backfill", req, &res); err != nil || !res.Ran {
		t.Fatalf("%+v %v", res, err)
	}
	l := NewLedger(td.getenv, nil, nil)
	got := map[string]footprint.Row{}
	for _, r := range l.Rows() {
		got[r.ID] = r
		if !r.Inferred || r.State != footprint.StateApplied {
			t.Errorf("%s isn't an inferred applied row: %+v", r.ID, r)
		}
	}
	want := []string{
		"hookup:" + filepath.Join(kitty, "kitty.conf"),
		"file:" + filepath.Join(kitty, "axiom.conf"),
		"dir:" + cursor,
	}
	for _, id := range want {
		if _, ok := got[id]; !ok {
			t.Errorf("no row %s in %v", id, got)
		}
	}
	if _, ok := got["hookup:"+filepath.Join(other, "alacritty.toml")]; ok {
		t.Error("a file with no trace of axiom got a row")
	}
	hk := got["hookup:"+filepath.Join(kitty, "kitty.conf")]
	if hk.Hookup == nil || !strings.HasSuffix(hk.Hookup.Backup, ".axiom-bak-20260101-000000") || len(hk.Hookup.Edit.Inserted) != 2 {
		t.Errorf("the hookup's record: %+v", hk.Hookup)
	}
	// Once only
	res = FootprintBackfillResult{}
	if err := shell.Call(ctx, "footprint.backfill", req, &res); err != nil || res.Ran {
		t.Errorf("a second backfill: %+v %v", res, err)
	}
	// Inferred: refused without force, and with it the file is as before axiom
	hookID := "hookup:" + filepath.Join(kitty, "kitty.conf")
	if r := l.Undo(ctx, []string{hookID}, footprint.UndoOptions{}); r[0].Outcome != footprint.OutcomeRefused {
		t.Errorf("%+v", r)
	}
	if r := l.Undo(ctx, []string{hookID}, footprint.UndoOptions{Force: true}); r[0].Outcome != footprint.OutcomeDone {
		t.Errorf("%+v", r)
	}
	if data, _ := os.ReadFile(filepath.Join(kitty, "kitty.conf")); string(data) != "font_size 12\n" {
		t.Errorf("after undo %q", data)
	}
	_ = home
}

func after(t *testing.T) <-chan time.Time { return time.After(testkit.Bound(5 * time.Second)) }

package cli

import (
	"bytes"
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/daemon"
	"github.com/axiom-shell/axiom/backend/internal/footprint"
)

// footprintHome is a scratch home with a ledger of three rows: a plain one,
// a system one and an inferred one, each a file that exists.
func footprintHome(t *testing.T) (env map[string]string, files map[string]string) {
	t.Helper()
	home := t.TempDir()
	env = map[string]string{"HOME": home, "XDG_STATE_HOME": filepath.Join(home, "state"), "XDG_CONFIG_HOME": filepath.Join(home, "config"),
		"XDG_DATA_HOME": filepath.Join(home, "data"), "XDG_CACHE_HOME": filepath.Join(home, "cache")}
	l := daemon.NewLedger(func(k string) string { return env[k] }, nil, nil)
	files = map[string]string{}
	for _, name := range []string{"plain", "system", "inferred"} {
		files[name] = filepath.Join(home, name)
		if err := os.WriteFile(files[name], []byte("x"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	for _, name := range []string{"plain", "system"} {
		id, err := l.Begin(footprint.Row{Kind: footprint.KindFile, Target: files[name], Owner: "Owner." + name, System: name == "system"}, footprint.PriorAbsent)
		if err != nil {
			t.Fatal(err)
		}
		l.Done(id, nil)
	}
	// The inferred one is the backfill's
	if _, _, err := l.Backfill([]footprint.Row{{Kind: footprint.KindFile, Target: files["inferred"], Prior: footprint.Absent()}}); err != nil {
		t.Fatal(err)
	}
	return env, files
}

func runFootprint(t *testing.T, env map[string]string, args ...string) (int, string) {
	t.Helper()
	var out, errOut bytes.Buffer
	e := &Env{Stdout: &out, Stderr: &errOut, Getenv: func(k string) string { return env[k] }}
	code := Run(context.Background(), Root(), append([]string{"--offline", "footprint"}, args...), e)
	return code, out.String() + errOut.String()
}

func TestFootprintListJSON(t *testing.T) {
	t.Parallel()
	env, files := footprintHome(t)
	code, out := runFootprint(t, env, "--json", "list")
	var got daemon.FootprintListResult
	if err := json.Unmarshal([]byte(out), &got); err != nil || code != 0 {
		t.Fatalf("%d %v: %s", code, err, out)
	}
	if len(got.Rows) != 3 || got.Rows[0].Target != files["plain"] || got.Rows[0].Status != footprint.StatusPresent || !got.Rows[1].System {
		t.Errorf("%+v", got.Rows)
	}
	if code, out := runFootprint(t, env, "list"); code != 0 || out == "" {
		t.Errorf("%d %q", code, out)
	}
}

func TestFootprintUndoAllSkipsSystemAndInferred(t *testing.T) {
	t.Parallel()
	env, files := footprintHome(t)
	if code, out := runFootprint(t, env, "undo", "--all"); code != 0 {
		t.Fatalf("%d %s", code, out)
	}
	for name, want := range map[string]bool{"plain": false, "system": true, "inferred": true} {
		if _, err := os.Stat(files[name]); (err == nil) != want {
			t.Errorf("%s exists: %v, want %v", name, err == nil, want)
		}
	}
	if code, _ := runFootprint(t, env, "undo", "--all", "--include-system"); code != 0 {
		t.Fatal(code)
	}
	if _, err := os.Stat(files["system"]); err == nil {
		t.Error("--include-system left the system row")
	}
	if _, err := os.Stat(files["inferred"]); err != nil {
		t.Error("--include-system took the inferred row")
	}
	if code, _ := runFootprint(t, env, "undo", "--all", "--force"); code != 0 {
		t.Fatal(code)
	}
	if _, err := os.Stat(files["inferred"]); err == nil {
		t.Error("--force left the inferred row")
	}
	// The mode is needed
	if code, _ := runFootprint(t, env, "undo"); code == 0 {
		t.Error("undo with nothing named ran")
	}
}

func TestFootprintUndoDryRun(t *testing.T) {
	t.Parallel()
	env, files := footprintHome(t)
	code, out := runFootprint(t, env, "--json", "undo", "--all", "--dry-run")
	var got daemon.FootprintUndoResult
	if err := json.Unmarshal([]byte(out), &got); err != nil || code != 0 || len(got.Results) != 1 || got.Results[0].Outcome != footprint.OutcomeDone {
		t.Fatalf("%d %v: %s", code, err, out)
	}
	if _, err := os.Stat(files["plain"]); err != nil {
		t.Error("the dry run deleted the file")
	}
	l := daemon.NewLedger(func(k string) string { return env[k] }, nil, nil)
	if len(l.Rows()) != 3 {
		t.Errorf("rows %+v", l.Rows())
	}
}

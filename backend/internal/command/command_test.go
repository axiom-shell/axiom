package command

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

func testCtx(t *testing.T) context.Context {
	t.Helper()
	c, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	t.Cleanup(cancel)
	return c
}

func ptr(s string) *string { return &s }

func TestRun(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name  string
		argv  []string
		input *string
		env   []string
		want  Result
		kind  axerr.Kind
	}{
		{name: "output and exit code", argv: []string{"sh", "-c", "echo out; echo err >&2; exit 3"}, want: Result{ExitCode: 3, Stdout: "out\n", Stderr: "err\n"}},
		{name: "stdin", argv: []string{"cat"}, input: ptr("secret\nline"), want: Result{Stdout: "secret\nline"}},
		{name: "no input is /dev/null", argv: []string{"cat"}, want: Result{}},
		{name: "environment", argv: []string{"sh", "-c", "printf %s \"$AXIOM_X\""}, env: []string{"AXIOM_X=1", "PATH=" + os.Getenv("PATH")}, want: Result{Stdout: "1"}},
		{name: "killed", argv: []string{"sh", "-c", "kill -9 $$"}, want: Result{ExitCode: -1}},
		{name: "missing", argv: []string{"axiom-no-such-command"}, kind: axerr.NotFound},
		{name: "empty", argv: nil, kind: axerr.BadRequest},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			got, err := Run(testCtx(t), Options{Env: tc.env}, tc.argv, tc.input)
			if tc.kind != "" {
				if axerr.KindOf(err) != tc.kind {
					t.Fatalf("err %v, want kind %s", err, tc.kind)
				}
				return
			}
			if err != nil || got != tc.want {
				t.Fatalf("got %+v, %v; want %+v", got, err, tc.want)
			}
		})
	}
}

func TestRunCapsOutput(t *testing.T) {
	t.Parallel()
	// Twice the cap: the command must not block, the rest is dropped
	got, err := Run(testCtx(t), Options{}, []string{"head", "-c", strconv.Itoa(2 * maxStdout), "/dev/zero"}, nil)
	if err != nil || got.ExitCode != 0 || len(got.Stdout) != maxStdout {
		t.Fatalf("got %d bytes, exit %d, %v", len(got.Stdout), got.ExitCode, err)
	}
}

func TestRunDoesNotWaitForAChildHoldingStdout(t *testing.T) {
	t.Parallel()
	start := time.Now()
	got, err := Run(testCtx(t), Options{PipeWait: 100 * time.Millisecond}, []string{"sh", "-c", "sleep 5 & echo hi"}, nil)
	if err != nil || got.Stdout != "hi\n" || time.Since(start) > 3*time.Second {
		t.Fatalf("got %+v, %v after %v", got, err, time.Since(start))
	}
}

func TestRunReturnsWhenTheCallerLeaves(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	ctx, cancel := context.WithCancel(testCtx(t))
	time.AfterFunc(100*time.Millisecond, cancel)
	// The command outlives the call and still finishes its work
	_, err := Run(ctx, Options{}, []string{"sh", "-c", "sleep 0.5; touch " + filepath.Join(dir, "done")}, nil)
	if axerr.KindOf(err) != axerr.Unavailable {
		t.Fatalf("err %v, want unavailable", err)
	}
	waitFor(t, filepath.Join(dir, "done"))
}

func TestSpawn(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	out := filepath.Join(dir, "out")
	// Its session, its parent and its descriptors, written once it runs
	script := `read -r _ _ _ _ _ sid _ < /proc/$$/stat; echo "$$ $sid $PPID"; ls /proc/$$/fd | wc -l`
	argv := []string{"sh", "-c", "{ " + script + "; } > " + out + ".tmp; mv " + out + ".tmp " + out}
	if err := Spawn(testCtx(t), Options{}, argv); err != nil {
		t.Fatal(err)
	}
	data := waitFor(t, out)
	f := strings.Fields(data)
	if len(f) != 4 {
		t.Fatalf("got %q", data)
	}
	if f[0] != f[1] {
		t.Errorf("pid %s isn't its session's leader (%s)", f[0], f[1])
	}
	if f[2] == strconv.Itoa(os.Getpid()) {
		t.Errorf("spawned as this process's child")
	}
	// stdin, stdout (the file), stderr, and ls's own directory
	if n, _ := strconv.Atoi(f[3]); n > 4 {
		t.Errorf("%d descriptors open: inherited some", n)
	}
}

func TestSpawnErrors(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		argv []string
		kind axerr.Kind
	}{
		{[]string{"axiom-no-such-command"}, axerr.NotFound},
		{nil, axerr.BadRequest},
	} {
		if err := Spawn(testCtx(t), Options{}, tc.argv); axerr.KindOf(err) != tc.kind {
			t.Errorf("%v: err %v, want %s", tc.argv, err, tc.kind)
		}
	}
}

func waitFor(t *testing.T, path string) string {
	t.Helper()
	for deadline := time.Now().Add(5 * time.Second); time.Now().Before(deadline); time.Sleep(20 * time.Millisecond) {
		data, err := os.ReadFile(path)
		if err == nil {
			return string(data)
		}
		if !errors.Is(err, os.ErrNotExist) {
			t.Fatal(err)
		}
	}
	t.Fatalf("%s never appeared", path)
	return ""
}

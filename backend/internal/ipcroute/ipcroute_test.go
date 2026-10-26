package ipcroute

import (
	"context"
	"os"
	"path/filepath"
	"reflect"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

func TestParseShow(t *testing.T) {
	t.Parallel()
	got := ParseShow("target brightness\n  function set(percent: int): void\n  function up(): void\ntarget todo\n  function add(text: string): bool\n")
	want := map[string][]Function{
		"brightness": {{Name: "set", Args: []Arg{{"percent", "int"}}, Returns: "void"}, {Name: "up", Returns: "void"}},
		"todo":       {{Name: "add", Args: []Arg{{"text", "string"}}, Returns: "bool"}},
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("got %+v", got)
	}
}

func TestCoerce(t *testing.T) {
	t.Parallel()
	fn := Function{Name: "f", Args: []Arg{{"n", "int"}, {"on", "bool"}, {"s", "string"}}}
	args, err := coerce(fn, []string{"5", "true", "x"})
	if err != nil || !reflect.DeepEqual(args, []any{5, true, "x"}) {
		t.Errorf("%v %v", args, err)
	}
	if _, err := coerce(fn, []string{"five", "true", "x"}); err == nil {
		t.Error("a word passed as an int")
	}
	if _, err := coerce(fn, []string{"5"}); err == nil {
		t.Error("too few arguments passed")
	}
}

// The exec fallback: a qs that fails names the function NotFound, one that
// never answers is Unavailable (a timeout says nothing about the function).
func TestExecErrorKinds(t *testing.T) {
	t.Parallel()
	for _, c := range []struct {
		name, script string
		want         axerr.Kind
	}{
		{"fails", "echo 'no such function' >&2; exit 1", axerr.NotFound},
		{"hangs", "exec sleep 10", axerr.Unavailable},
		{"answers", "echo ok", ""},
	} {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			qs := filepath.Join(t.TempDir(), "qs")
			if err := os.WriteFile(qs, []byte("#!/bin/sh\n"+c.script+"\n"), 0o755); err != nil {
				t.Fatal(err)
			}
			r := New(Options{QS: qs, ShellPID: func() int { return 1 }, Timeout: 200 * time.Millisecond})
			out, err := r.Call(context.Background(), CallParams{Target: "t", Function: "f"})
			if c.want == "" {
				if err != nil || out != "ok" {
					t.Errorf("got %q, %v", out, err)
				}
				return
			}
			if axerr.KindOf(err) != c.want {
				t.Errorf("kind %s (%v), want %s", axerr.KindOf(err), err, c.want)
			}
		})
	}
}

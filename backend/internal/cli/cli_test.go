package cli

import (
	"bytes"
	"context"
	"encoding/json"
	"flag"
	"reflect"
	"strings"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

// run executes args against root and returns the exit code and output.
func run(t *testing.T, root *Command, args ...string) (int, string, string) {
	t.Helper()
	var out, errOut bytes.Buffer
	e := &Env{Stdout: &out, Stderr: &errOut, Getenv: func(string) string { return "" }}
	code := Run(context.Background(), root, args, e)
	return code, out.String(), errOut.String()
}

// echoRoot has one leaf that prints its positionals and one flag.
func echoRoot(got *[]string, name *string) *Command {
	return &Command{Name: "axiom", Subs: []*Command{{
		Name: "group",
		Subs: []*Command{{
			Name: "echo",
			Args: "ARGS…",
			Setup: func(fs *flag.FlagSet) Runner {
				fs.StringVar(name, "name", "", "a name")
				return func(ctx context.Context, e *Env, args []string) error {
					*got = args
					if e.Globals.JSON {
						return e.Output(args, nil)
					}
					return nil
				}
			},
		}},
	}}}
}

func TestInterleavedFlagsAndTerminator(t *testing.T) {
	t.Parallel()
	cases := []struct {
		args []string
		want []string
		name string
	}{
		{[]string{"a", "--name", "x", "b"}, []string{"a", "b"}, "x"},
		{[]string{"--name=y", "a"}, []string{"a"}, "y"},
		{[]string{"a", "--", "--name", "-z"}, []string{"a", "--name", "-z"}, ""},
		{nil, nil, ""},
	}
	for _, c := range cases {
		var got []string
		var name string
		code, _, stderr := run(t, echoRoot(&got, &name), append([]string{"group", "echo"}, c.args...)...)
		if code != 0 {
			t.Fatalf("%v: exit %d (%s)", c.args, code, stderr)
		}
		if !reflect.DeepEqual(got, c.want) || name != c.name {
			t.Errorf("%v: got %v name %q, want %v name %q", c.args, got, name, c.want, c.name)
		}
	}
}

func TestGlobalsAnywhere(t *testing.T) {
	t.Parallel()
	for _, args := range [][]string{
		{"--json", "group", "echo", "a"},
		{"group", "echo", "a", "--json"},
	} {
		var got []string
		var name string
		code, out, _ := run(t, echoRoot(&got, &name), args...)
		if code != 0 || strings.TrimSpace(out) != "[\n  \"a\"\n]" {
			t.Errorf("%v: exit %d, out %q", args, code, out)
		}
	}
}

func TestUsageErrors(t *testing.T) {
	t.Parallel()
	var got []string
	var name string
	root := echoRoot(&got, &name)
	for _, args := range [][]string{{}, {"nope"}, {"group", "nope"}, {"group", "echo", "--bogus"}} {
		code, _, stderr := run(t, root, args...)
		if code != 2 {
			t.Errorf("%v: exit %d, want 2 (%s)", args, code, stderr)
		}
	}
	if code, out, _ := run(t, root, "group", "echo", "--help"); code != 0 || !strings.Contains(out, "--name") {
		t.Errorf("--help: exit %d, out %q", code, out)
	}
}

func TestJSONErrors(t *testing.T) {
	t.Parallel()
	root := &Command{Name: "axiom", Subs: []*Command{{
		Name: "fail",
		Setup: func(fs *flag.FlagSet) Runner {
			return func(ctx context.Context, e *Env, args []string) error {
				return &axerr.Error{Kind: axerr.InvalidConfig, Message: "bad", Issues: []axerr.Issue{{Path: "a.b", Message: "nope"}}}
			}
		},
	}}}
	code, out, _ := run(t, root, "fail", "--json")
	if code != 1 {
		t.Fatalf("exit %d", code)
	}
	var body struct {
		Error struct {
			Kind   string
			Issues []axerr.Issue
		}
	}
	if err := json.Unmarshal([]byte(out), &body); err != nil || body.Error.Kind != "invalid_config" || len(body.Error.Issues) != 1 {
		t.Errorf("out %q (%v)", out, err)
	}
}

func TestVersion(t *testing.T) {
	t.Parallel()
	code, out, _ := run(t, Root(), "version", "--json")
	var info struct{ Protocol int }
	if code != 0 || json.Unmarshal([]byte(out), &info) != nil || info.Protocol < 1 {
		t.Errorf("exit %d out %q", code, out)
	}
}

// A negative number is a positional, unless it's the value of the flag
// before it; a bool flag takes no value.
func TestParseInterleavedNegativeNumbers(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		args []string
		want string
		by   string
	}{
		{[]string{"TSLA", "-2"}, "TSLA -2", ""},
		{[]string{"TSLA", "-0.5", "--by", "x"}, "TSLA -0.5", "x"},
		{[]string{"--by", "-3", "TSLA"}, "TSLA", "-3"},
		{[]string{"--quiet", "-3"}, "-3", ""},
		{[]string{"--", "-x"}, "-x", ""},
	} {
		fs := flag.NewFlagSet("t", flag.ContinueOnError)
		by := fs.String("by", "", "")
		fs.Bool("quiet", false, "")
		got, err := parseInterleaved(fs, tc.args)
		if err != nil || strings.Join(got, " ") != tc.want || *by != tc.by {
			t.Errorf("%v: %v %v by %q, want %q by %q", tc.args, got, err, *by, tc.want, tc.by)
		}
	}
}

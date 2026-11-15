package command

import (
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

// streamed watches script as a stream and returns the harness and the
// subscriber.
func streamed(t *testing.T, script, format string) (*harness, *fakeSub) {
	t.Helper()
	h := newHarness(t)
	s := newSub()
	if err := h.w.Watch(s, WatchRequest{Command: script, Mode: ModeStream, Format: format}); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { h.w.Forget(s) })
	return h, s
}

// next returns the next entry of command pushed to s.
func (s *fakeSub) entry(t *testing.T, command string) Entry {
	t.Helper()
	return s.next(t).Outputs[command]
}

func (s *fakeSub) quiet(t *testing.T) {
	t.Helper()
	select {
	case p := <-s.pushes:
		t.Fatalf("pushed %+v", p)
	case <-time.After(100 * time.Millisecond):
	}
}

// Each line is an output, parsed with json (a bad line keeps its text
// and says why).
func TestStreamLines(t *testing.T) {
	t.Parallel()
	script := `echo '{"a": 1}'; sleep 0.1; echo oops; exec sleep 100`
	h, s := streamed(t, script, FormatJSON)
	if e := s.entry(t, script); string(e.Value) != `{"a": 1}` || e.ExitCode != 0 {
		t.Errorf("first line %+v", e)
	}
	h.clock.Advance(coalesce)
	if e := s.entry(t, script); e.Text != "oops" || e.Error != "the output isn't JSON" || e.Value != nil {
		t.Errorf("bad line %+v", e)
	}
}

// A chatty script is pushed its latest line once per coalesce.
func TestStreamCoalesces(t *testing.T) {
	t.Parallel()
	script := `for i in 1 2 3 4 5 6 7 8 9 10; do echo $i; done; exec sleep 100`
	h, s := streamed(t, script, FormatText)
	if s.entry(t, script).Text != "10" {
		s.quiet(t) // the rest waits for the clock
		h.clock.Advance(coalesce)
		if e := s.entry(t, script); e.Text != "10" {
			t.Errorf("coalesced to %+v", e)
		}
	}
	s.quiet(t)
}

// A line keeps its first maxLine bytes.
func TestStreamLineCap(t *testing.T) {
	t.Parallel()
	script := `head -c 100000 /dev/zero | tr '\0' a; echo; exec sleep 100`
	_, s := streamed(t, script, FormatText)
	if e := s.entry(t, script); len(e.Text) != maxLine || strings.Trim(e.Text, "a") != "" {
		t.Errorf("a line of %d bytes", len(e.Text))
	}
}

// A script that exits is restarted after a backoff that doubles.
func TestStreamRestartsWithBackoff(t *testing.T) {
	t.Parallel()
	count := filepath.Join(t.TempDir(), "count")
	script := `n=$(( $(cat ` + count + ` 2>/dev/null || echo 0) + 1 )); echo $n > ` + count + `; echo $n; exit 3`
	h, s := streamed(t, script, FormatText)
	exited := func(n string) {
		t.Helper()
		for {
			e := s.entry(t, script)
			if e.Text == n && e.ExitCode == 3 {
				return
			}
			if e.Text != n || e.ExitCode != 0 {
				t.Fatalf("waiting for run %s to exit: %+v", n, e)
			}
		}
	}
	exited("1")
	h.clock.Advance(firstBackoff)
	exited("2")
	h.clock.Advance(firstBackoff)
	s.quiet(t)
	h.clock.Advance(firstBackoff)
	exited("3")
}

// The last unwatch, and Forget, kill the script's whole group, SIGKILL
// for what ignores SIGTERM.
func TestStreamStops(t *testing.T) {
	t.Parallel()
	for _, forget := range []bool{false, true} {
		t.Run(strconv.FormatBool(forget), func(t *testing.T) {
			t.Parallel()
			pids := filepath.Join(t.TempDir(), "pids")
			script := `trap '' TERM; sleep 100 & echo $$ $! > ` + pids + `; echo up; wait`
			h, s := streamed(t, script, FormatText)
			if e := s.entry(t, script); e.Text != "up" {
				t.Fatalf("%+v", e)
			}
			data, err := os.ReadFile(pids)
			if err != nil {
				t.Fatal(err)
			}
			if forget {
				h.w.Forget(s)
			} else {
				h.w.Unwatch(s, script)
			}
			for _, pid := range strings.Fields(string(data)) {
				if !testkit.Eventually(func() bool { return !alive(pid) }) {
					t.Fatalf("%s still runs", pid)
				}
			}
		})
	}
}

// alive is whether pid runs (a zombie waiting for init doesn't).
func alive(pid string) bool {
	stat, err := os.ReadFile("/proc/" + pid + "/stat")
	if err != nil {
		return false
	}
	fields := strings.Fields(string(stat[strings.LastIndexByte(string(stat), ')')+1:]))
	return len(fields) > 0 && fields[0] != "Z"
}

// A stream that exits publishes its exit with the last stderr line and
// Exited, even when the line has no newline or the exit leaves no text.
func TestStreamExitCarriesStderr(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name, script, text, stderr string
		code                       int
	}{
		{name: "no output", script: `echo x >&2; exit 3`, stderr: "x", code: 3},
		{name: "no newline", script: `printf boom >&2; exit 4`, stderr: "boom", code: 4},
		{name: "last line wins", script: `echo one >&2; echo two >&2; echo out; exit 5`, text: "out", stderr: "two", code: 5},
		{name: "no stderr", script: `exit 6`, code: 6},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			_, s := streamed(t, c.script, FormatText)
			e := s.entry(t, c.script)
			for e.ExitCode == 0 && e.Text != "" { // a line before the exit
				e = s.entry(t, c.script)
			}
			if e.ExitCode != c.code || e.Text != c.text || e.Stderr != c.stderr || !e.Exited {
				t.Errorf("entry %+v, want exit %d text %q stderr %q exited", e, c.code, c.text, c.stderr)
			}
		})
	}
}

// A run's entry never carries an earlier run's stderr line.
func TestStreamStderrResetsPerRun(t *testing.T) {
	t.Parallel()
	count := filepath.Join(t.TempDir(), "count")
	script := `n=$(( $(cat ` + count + ` 2>/dev/null || echo 0) + 1 )); echo $n > ` + count +
		`; if [ $n = 1 ]; then echo first >&2; exit 3; fi; exit 4`
	h, s := streamed(t, script, FormatText)
	if e := s.entry(t, script); e.ExitCode != 3 || e.Stderr != "first" {
		t.Fatalf("first run %+v", e)
	}
	h.clock.Advance(firstBackoff)
	if e := s.entry(t, script); e.ExitCode != 4 || e.Stderr != "" || !e.Exited {
		t.Errorf("second run %+v", e)
	}
}

// pidOf reads an entry's text as the process id the script printed.
func pidOf(t *testing.T, e Entry) string {
	t.Helper()
	if _, err := strconv.Atoi(e.Text); err != nil {
		t.Fatalf("entry %+v isn't a pid", e)
	}
	return e.Text
}

// Restart replaces a running stream's process at once (no backoff, no
// exit published for the killed one), and one that exited and waits out
// its backoff starts again without waiting, with the backoff started
// over.
func TestStreamRestart(t *testing.T) {
	t.Parallel()
	t.Run("running", func(t *testing.T) {
		t.Parallel()
		script := `echo $$; exec sleep 100`
		h, s := streamed(t, script, FormatText)
		first := pidOf(t, s.entry(t, script))
		h.w.Restart(script)
		e := s.entry(t, script)
		if second := pidOf(t, e); second == first {
			t.Errorf("the same process %s", first)
		}
		if e.ExitCode != 0 || e.Exited {
			t.Errorf("an exit published for the killed run: %+v", e)
		}
		if !testkit.Eventually(func() bool { return !alive(first) }) {
			t.Errorf("%s still runs", first)
		}
		s.quiet(t)
	})
	t.Run("backoff", func(t *testing.T) {
		t.Parallel()
		script := `echo $$; exit 3`
		h, s := streamed(t, script, FormatText)
		exited := func() string {
			t.Helper()
			e := s.entry(t, script)
			if e.ExitCode == 0 && !e.Exited { // the line, before the exit
				e = s.entry(t, script)
			}
			if e.ExitCode != 3 || !e.Exited {
				t.Fatalf("entry %+v", e)
			}
			return pidOf(t, e)
		}
		first := exited()
		h.clock.Advance(firstBackoff) // the second run: the backoff doubles to 2s
		second := exited()
		h.w.Restart(script) // no clock advance: no waiting
		third := exited()
		if first == second || second == third {
			t.Errorf("pids %s %s %s", first, second, third)
		}
		// The backoff started over: one firstBackoff, not two
		h.clock.Advance(firstBackoff)
		if fourth := exited(); fourth == third {
			t.Errorf("no new process after %s", third)
		}
	})
}

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

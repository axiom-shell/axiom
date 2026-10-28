package binds

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

var (
	axiomOnce sync.Once
	axiomBin  string
	axiomErr  error
)

// built is the axiom binary, built once (without -race: the race
// detector's shadow memory can't start under a memory limit), as the
// daemon's child runs it
func built(t *testing.T) string {
	t.Helper()
	if _, err := exec.LookPath("go"); err != nil {
		t.Skip("no go to build axiom with")
	}
	axiomOnce.Do(func() {
		dir, err := os.MkdirTemp("", "axiom-binds-test-")
		if err != nil {
			axiomErr = err
			return
		}
		axiomBin = filepath.Join(dir, "axiom")
		cmd := exec.Command("go", "build", "-o", axiomBin, "./cmd/axiom")
		cmd.Dir = filepath.Join(testkit.RepoRoot(), "backend")
		if out, err := cmd.CombinedOutput(); err != nil {
			axiomErr = err
			axiomBin = string(out)
		}
	})
	if axiomErr != nil {
		t.Fatalf("building axiom: %v\n%s", axiomErr, axiomBin)
	}
	return axiomBin
}

// crashChild, set to a size in bytes, makes this test binary a child that
// holds that much memory and then fails, saying childSays (by default the
// Go runtime's crash), for the tests that tell a memory death from a crash
const (
	crashChild = "AXIOM_BINDS_TEST_CRASH_HOLDING"
	childSays  = "AXIOM_BINDS_TEST_CHILD_SAYS"
)

func TestMain(m *testing.M) {
	if size, err := strconv.Atoi(os.Getenv(crashChild)); err == nil {
		held := make([]byte, size)
		for i := 0; i < len(held); i += 4096 {
			held[i] = 1
		}
		says := os.Getenv(childSays)
		if says == "" {
			says = "SIGSEGV: segmentation violation"
		}
		os.Stderr.WriteString(says + "\n")
		runtime.KeepAlive(held)
		os.Exit(2)
	}
	code := m.Run()
	if axiomBin != "" && axiomErr == nil {
		os.RemoveAll(filepath.Dir(axiomBin))
	}
	os.Exit(code)
}

func (f *fx) isolated() Options {
	o := f.options()
	o.Isolate = built(f.t)
	return o
}

// Read in a child, the binds are what reading them here finds
func TestIsolatedExtractReadsTheBinds(t *testing.T) {
	t.Parallel()
	f := newFx(t, "hyprland")
	f.write("binds.lua", "for i = 1, 3 do\n  hl.bind(\"SUPER + \" .. i, hl.dsp.focus({ workspace = i }))\nend\n")
	got, err := Extract(context.Background(), f.isolated())
	if err != nil {
		t.Fatal(err)
	}
	eq(t, len(list(got, "binds")), 3)
	// The child's tracked check is git's, the test's a stub: the rest is
	// the same
	got.Set("tracked", nil)
	want := f.extract()
	want.Set("tracked", nil)
	eq(t, js(got), js(want))
}

// A file taking memory without end ends the child at MemoryLimit: an
// error, and the process that asked goes on
func TestIsolatedExtractSurvivesAFileTakingAllMemory(t *testing.T) {
	t.Parallel()
	f := newFx(t, "hyprland")
	f.write("binds.lua", "local s = \"x\"\nfor i = 1, 40 do s = s .. s end\n")
	start := time.Now()
	_, err := Extract(context.Background(), f.isolated())
	if err == nil || !strings.Contains(err.Error(), "MiB") {
		t.Fatalf("got %v", err)
	}
	if time.Since(start) > 20*time.Second {
		t.Fatal("not ended by the limit")
	}
}

// A child that crashes is told from one the limit ended by its peak RSS:
// holding a quarter of the limit (and more than this process ever held,
// which the child's peak counts), it gets the MiB message; holding a few
// MiB, the crash. A child holding as much that fails with its own error
// says that error. Not parallel: the child is chosen by the environment.
func TestIsolatedExtractTellsAMemoryDeathFromACrash(t *testing.T) {
	self, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	big := func() int { return int(max(MemoryLimit/4, ownPeakRSS())) + 16<<20 }
	for _, c := range []struct {
		held func() int
		says string
		want string
	}{
		{big, "", "took more than 1024 MiB"},
		{func() int { return 1 << 20 }, "", "reading the binds: SIGSEGV: segmentation violation"},
		{big, "binds.lua:1: attempt to call a nil value", "reading the binds: binds.lua:1: attempt to call a nil value"},
	} {
		t.Setenv(crashChild, strconv.Itoa(c.held()))
		t.Setenv(childSays, c.says)
		f := newFx(t, "hyprland")
		f.write("binds.lua", "")
		o := f.options()
		o.Isolate = self
		if _, err := Extract(context.Background(), o); err == nil || !strings.Contains(err.Error(), c.want) {
			t.Fatalf("saying %q: got %v, want %q", c.says, err, c.want)
		}
	}
}

// A child's peak counts its parent's memory at exec (vfork), so a peak
// this process may have reached itself is a crash
func TestDiedOfMemory(t *testing.T) {
	t.Parallel()
	q := int64(MemoryLimit / 4)
	for _, c := range []struct {
		child, own int64
		want       bool
	}{
		{q, 0, true},
		{q - 1, 0, false},
		{2 * q, q, true},
		{q, q, false},
		{q, 2 * q, false},
	} {
		eq(t, diedOfMemory(c.child, c.own), c.want)
	}
}

// In this process too, one string.rep can't ask for it all at once; it
// takes 5.4's separator
func TestStringRepIsCapped(t *testing.T) {
	t.Parallel()
	f := newFx(t, "hyprland")
	f.write("binds.lua", "local s = (\"x\"):rep(2^40)\nhl.bind(\"SUPER + Y\", hl.dsp.window.close())\n")
	found := f.extract()
	eq(t, len(list(found, "binds")), 0)
	if !strings.Contains(js(found.Value("errors")), "string.rep") {
		t.Fatalf("errors %s", js(found.Value("errors")))
	}
	f.write("binds.lua", "local s = string.rep(\"ab\", 3, \",\")\nhl.bind(\"SUPER + \" .. #s, hl.dsp.window.close())\n")
	eq(t, list(f.extract(), "binds")[0].Value("key"), "SUPER + 8")
}

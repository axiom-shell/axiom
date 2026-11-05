package sysmon

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"slices"
	"strconv"
	"sync"
	"syscall"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

// machine is a fake /proc and /sys under one dir
type machine struct {
	t   *testing.T
	dir string
}

func newMachine(t *testing.T) *machine {
	m := &machine{t, t.TempDir()}
	m.write("proc/meminfo", "MemTotal:       16000000 kB\nMemFree:         1000000 kB\nMemAvailable:    4000000 kB\n")
	m.write("proc/net/dev", "Inter-|   Receive\n face |bytes    packets\n    lo: 999 0 0 0 0 0 0 0 999 0 0 0 0 0 0 0\n  eth0: 1000 0 0 0 0 0 0 0 500 0 0 0 0 0 0 0\n")
	m.cpu(100, 50)
	return m
}

func (m *machine) write(path, text string) {
	m.t.Helper()
	full := filepath.Join(m.dir, path)
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		m.t.Fatal(err)
	}
	if err := os.WriteFile(full, []byte(text), 0o644); err != nil {
		m.t.Fatal(err)
	}
}

// cpu sets /proc/stat's totals: busy in user, idle in idle
func (m *machine) cpu(busy, idle int) {
	m.write("proc/stat", "cpu  "+itoa(busy)+" 0 0 "+itoa(idle)+" 0 0 0 0 0 0\ncpu0 1 2 3 4\n")
}

func (m *machine) proc(pid int, comm string, ticks int, rssPages int, uid string) {
	stat := itoa(pid) + " (" + comm + ") S 1 1 1 0 -1 0 0 0 0 0 " + itoa(ticks) + " 0 0 0 20 0 1 0 100 1000 " + itoa(rssPages) + " 0"
	m.write("proc/"+itoa(pid)+"/stat", stat)
	m.write("proc/"+itoa(pid)+"/status", "Name:\t"+comm+"\nUid:\t"+uid+"\t"+uid+"\t"+uid+"\t"+uid+"\n")
}

func itoa(n int) string { return strconv.Itoa(n) }

// clock is a fake time, safe to move while Run reads it
type clock struct {
	mu  sync.Mutex
	now time.Time
}

func (c *clock) Now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.now
}

func (c *clock) add(d time.Duration) {
	c.mu.Lock()
	c.now = c.now.Add(d)
	c.mu.Unlock()
}

// streams is a fake nvidia-smi: each start is recorded, prints line once
// (once hold, if set, is closed) and runs until stopped
type streams struct {
	mu     sync.Mutex
	line   string
	hold   chan struct{}
	fail   bool
	starts []time.Duration
	live   int
}

func (f *streams) start(ctx context.Context, bin string, every time.Duration) (io.ReadCloser, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.starts = append(f.starts, every)
	if f.fail {
		return nil, errors.New("no nvidia-smi")
	}
	f.live++
	r, w := io.Pipe()
	go func() {
		if f.hold != nil {
			select {
			case <-f.hold:
			case <-ctx.Done():
			}
		}
		w.Write([]byte(f.line))
		<-ctx.Done()
		w.Close()
		f.mu.Lock()
		f.live--
		f.mu.Unlock()
	}()
	return r, nil
}

func (f *streams) state() (starts []time.Duration, live int) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return slices.Clone(f.starts), f.live
}

func (m *machine) monitor(c *clock, nvidia bool, f *streams) *Monitor {
	if f == nil {
		f = &streams{line: "37, 61\n"}
	}
	return New(Options{
		Proc: filepath.Join(m.dir, "proc"),
		Sys:  filepath.Join(m.dir, "sys"),
		Home: "/home/u",
		Now:  c.Now,
		Sleep: func(ctx context.Context, d time.Duration) {
			c.add(d)
		},
		LookPath: func(file string) (string, error) {
			if nvidia && file == "nvidia-smi" {
				return "/usr/bin/nvidia-smi", nil
			}
			return "", exec.ErrNotFound
		},
		NvidiaStream: f.start,
	})
}

func (m *machine) fetcher(mon *Monitor) func(requests ...string) State {
	src := mon.Source()
	return func(requests ...string) State {
		var raw []json.RawMessage
		for _, r := range requests {
			raw = append(raw, json.RawMessage(r))
		}
		st, err := src.Fetch(context.Background(), raw)
		if err != nil {
			m.t.Fatal(err)
		}
		return st.(State)
	}
}

func (m *machine) source(c *clock, nvidia bool) func(requests ...string) State {
	return m.fetcher(m.monitor(c, nvidia, nil))
}

func TestCPUAndNet(t *testing.T) {
	t.Parallel()
	m := newMachine(t)
	c := &clock{now: time.UnixMilli(10_000)}
	fetch := m.source(c, false)
	req := `{"interval": 1000, "metrics": ["cpu", "net"]}`
	first := fetch(req)
	if first.CPUUsage != nil || first.NetRx != nil {
		t.Fatalf("a first sample has nothing to measure against: %+v", first)
	}
	if first.MemUsage != nil {
		t.Errorf("mem wasn't asked for")
	}
	m.cpu(130, 120) // 30 busy of 100
	m.write("proc/net/dev", "h\nh\n    lo: 5000 0 0 0 0 0 0 0 5000 0 0 0 0 0 0 0\n  eth0: 3000 0 0 0 0 0 0 0 1500 0 0 0 0 0 0 0\n")
	c.add(2 * time.Second)
	st := fetch(req)
	if st.CPUUsage == nil || *st.CPUUsage != 30 {
		t.Errorf("cpu %v, want 30", st.CPUUsage)
	}
	if st.NetRx == nil || *st.NetRx != 1000 || *st.NetTx != 500 {
		t.Errorf("net %v %v, want 1000 500 (loopback left out)", st.NetRx, st.NetTx)
	}
	if st.At != 12_000 {
		t.Errorf("at %d", st.At)
	}
	// After a pause the deltas start again
	m.cpu(200, 200)
	c.add(time.Minute)
	if st := fetch(req); st.CPUUsage != nil || st.NetRx != nil {
		t.Errorf("a sample after a pause measured over it: %+v", st)
	}
}

func TestMemAndUnion(t *testing.T) {
	t.Parallel()
	m := newMachine(t)
	fetch := m.source(&clock{now: time.UnixMilli(0)}, false)
	st := fetch(`{"metrics": ["cpu"]}`, `{"metrics": ["mem"]}`)
	if st.MemUsage == nil || *st.MemUsage != 75 || *st.MemTotalBytes != 16000000*1024 || *st.MemUsedBytes != 12000000*1024 {
		t.Errorf("mem %+v", st)
	}
}

func TestSensors(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name               string
		setup              func(m *machine)
		nvidia             bool
		hasTemp, hasGPU    bool
		cpuTemp, gpu, gtmp int
	}{
		{"none", func(m *machine) {}, false, false, false, 0, 0, 0},
		{"amd", func(m *machine) {
			m.write("sys/class/hwmon/hwmon0/name", "nvme\n")
			m.write("sys/class/hwmon/hwmon1/name", "k10temp\n")
			m.write("sys/class/hwmon/hwmon1/temp1_input", "45500\n")
			// The iGPU and the discrete card: the one with more VRAM
			m.write("sys/class/drm/card0/device/gpu_busy_percent", "3\n")
			m.write("sys/class/drm/card0/device/mem_info_vram_total", "512\n")
			m.write("sys/class/drm/card1/device/gpu_busy_percent", "42\n")
			m.write("sys/class/drm/card1/device/mem_info_vram_total", "8192\n")
			m.write("sys/class/drm/card1/device/hwmon/hwmon5/temp1_input", "60000\n")
		}, true, true, true, 46, 42, 60},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			m := newMachine(t)
			tc.setup(m)
			st := m.source(&clock{now: time.UnixMilli(0)}, tc.nvidia)(`{"metrics": ["cpuTemp", "gpu"]}`)
			if st.HasCPUTemp != tc.hasTemp || st.HasGPU != tc.hasGPU {
				t.Fatalf("has %v %v, want %v %v", st.HasCPUTemp, st.HasGPU, tc.hasTemp, tc.hasGPU)
			}
			if tc.hasTemp && *st.CPUTemp != tc.cpuTemp {
				t.Errorf("cpu temp %d", *st.CPUTemp)
			}
			if tc.hasGPU && (*st.GPUUsage != tc.gpu || *st.GPUTemp != tc.gtmp) {
				t.Errorf("gpu %d %d", *st.GPUUsage, *st.GPUTemp)
			}
		})
	}
}

func TestDisks(t *testing.T) {
	t.Parallel()
	m := newMachine(t)
	c := &clock{now: time.UnixMilli(0)}
	fetch := m.source(c, false)
	dir := t.TempDir()
	st := fetch(`{"metrics": ["disk"], "diskPaths": ["` + dir + `", "/no/such/path"]}`)
	u, ok := st.Disks[dir]
	if !ok || u.Total <= 0 || u.Used < 0 || u.Usage < 0 || u.Usage > 100 {
		t.Fatalf("disks %+v", st.Disks)
	}
	if _, ok := st.Disks["/no/such/path"]; ok {
		t.Errorf("a missing path has no usage")
	}
	if st := fetch(`{"metrics": ["cpu"], "diskPaths": ["/"]}`); st.Disks != nil {
		t.Errorf("disk wasn't asked for")
	}
}

func TestProcesses(t *testing.T) {
	t.Parallel()
	m := newMachine(t)
	m.proc(1, "systemd", 10, 100, "0")
	m.proc(42, "my (odd) app", 500, 100000, "0")
	m.write("proc/self", "not a pid\n")
	c := &clock{now: time.UnixMilli(0)}
	fetch := m.source(c, false)
	req := `{"metrics": ["processes"]}`
	// The first list reads twice (Sleep advances the clock half a second)
	first := fetch(req)
	if n := len(first.Processes); n != 2 {
		t.Fatalf("%d processes", n)
	}
	m.proc(42, "my (odd) app", 600, 100000, "0") // 100 ticks = 1 s of CPU; 400 MB of 16 GB
	c.add(2 * time.Second)
	st := fetch(req)
	want := []Process{
		{PID: 42, User: "root", CPU: 50, Mem: 2.5, Command: "my (odd) app"},
		{PID: 1, User: "root", CPU: 0, Mem: 0, Command: "systemd"},
	}
	if !reflect.DeepEqual(st.Processes, want) {
		t.Errorf("got %+v\nwant %+v", st.Processes, want)
	}
}

func TestKillRefusesInit(t *testing.T) {
	t.Parallel()
	for _, pid := range []int{-1, 0, 1} {
		if Kill(pid) == nil {
			t.Errorf("killed %d", pid)
		}
	}
}

func TestKill(t *testing.T) {
	t.Parallel()
	cmd := exec.Command("sleep", "600")
	if err := cmd.Start(); err != nil {
		t.Skip("no sleep:", err)
	}
	if err := Kill(cmd.Process.Pid); err != nil {
		cmd.Process.Kill()
		t.Fatal(err)
	}
	if err := cmd.Wait(); err == nil || cmd.ProcessState.Sys().(syscall.WaitStatus).Signal() != syscall.SIGTERM {
		t.Errorf("sleep ended with %v, want SIGTERM", err)
	}
	if axerr.KindOf(Kill(cmd.Process.Pid)) != axerr.NotFound {
		t.Errorf("killing a process that's gone isn't not_found")
	}
}

func TestHistory(t *testing.T) {
	t.Parallel()
	m := newMachine(t)
	c := &clock{now: time.UnixMilli(0)}
	mon := m.monitor(c, false, nil)
	fetch := m.fetcher(mon)
	if err := mon.Keep("shell", []string{CPU, Mem}); err != nil {
		t.Fatal(err)
	}
	busy, idle := 0, 0
	for i := range 70 {
		// 100 ticks a sample, i%50 of them busy
		busy, idle = busy+i%50, idle+100-i%50
		m.cpu(busy, idle)
		mon.record()
		c.add(time.Second)
	}
	st := fetch(`{"interval": 1000, "metrics": ["cpu", "mem", "net"], "history": ["cpu", "mem"]}`)
	// The first sample has nothing to measure CPU against: 69, the last 60
	want := []float64{}
	for i := 10; i < 70; i++ {
		want = append(want, float64(i%50))
	}
	if !reflect.DeepEqual(st.History[CPU], want) {
		t.Errorf("cpu history %v\nwant %v", st.History[CPU], want)
	}
	if n := len(st.History[Mem]); n != HistoryLength || st.History[Mem][0] != 75 {
		t.Errorf("mem history %v", st.History[Mem])
	}
	if _, ok := st.History["netRx"]; ok {
		t.Errorf("net wasn't kept before this request: %v", st.History)
	}
	if st := fetch(`{"interval": 1000, "metrics": ["mem"], "history": ["mem"]}`); len(st.History) != 1 || st.History[Mem] == nil {
		t.Errorf("only the history asked for is pushed: %v", st.History)
	}
	if st := fetch(`{"metrics": ["cpu"]}`); st.History != nil {
		t.Errorf("history wasn't asked for: %v", st.History)
	}
	// The topic's first CPU sample took the history's newest; with none
	// fresh, a first sample has none
	if st.CPUUsage == nil || *st.CPUUsage != 19 {
		t.Errorf("first cpu %v, want the history's 19", st.CPUUsage)
	}
	// A metric no longer kept is dropped and starts afresh
	mon.Keep("shell", []string{Mem})
	c.add(time.Minute) // past the history request's lease
	mon.record()
	mon.mu.Lock()
	_, hasCPU := mon.history[CPU]
	mon.mu.Unlock()
	if hasCPU {
		t.Errorf("cpu kept after it was dropped")
	}
}

func TestKeepAndHold(t *testing.T) {
	t.Parallel()
	m := newMachine(t)
	c := &clock{now: time.UnixMilli(0)}
	mon := m.monitor(c, false, nil)
	kept := func() []string {
		mon.mu.Lock()
		defer mon.mu.Unlock()
		return mon.kept(c.Now())
	}
	mon.Keep("a", []string{CPU, CPU})
	mon.Keep("b", []string{Net, Mem})
	if got := kept(); !reflect.DeepEqual(got, []string{CPU, Mem, Net}) {
		t.Errorf("kept %v", got)
	}
	mon.Forget("a")
	mon.Keep("b", nil)
	if got := kept(); got != nil {
		t.Errorf("kept %v after forget", got)
	}
	if err := mon.Keep("a", []string{Disk}); err == nil {
		t.Errorf("disk has no history")
	}
	// A history request holds its graphed metrics while it's fetched
	fetch := m.fetcher(mon)
	fetch(`{"interval": 1000, "metrics": ["net", "processes"], "history": ["net", "processes"]}`)
	if got := kept(); !reflect.DeepEqual(got, []string{Net}) {
		t.Errorf("held %v", got)
	}
	c.add(10 * time.Second)
	if got := kept(); got != nil {
		t.Errorf("held %v after the lease", got)
	}
}

// The history's samples and the topic's measure CPU apart
func TestCountersApart(t *testing.T) {
	t.Parallel()
	m := newMachine(t)
	c := &clock{now: time.UnixMilli(0)}
	mon := m.monitor(c, false, nil)
	fetch := m.fetcher(mon)
	mon.Keep("shell", []string{CPU})
	m.cpu(100, 100)
	mon.record()
	fetch(`{"metrics": ["cpu"]}`)
	c.add(500 * time.Millisecond)
	m.cpu(200, 100) // all busy
	if st := fetch(`{"metrics": ["cpu"]}`); *st.CPUUsage != 100 {
		t.Errorf("topic cpu %d", *st.CPUUsage)
	}
	c.add(500 * time.Millisecond)
	m.cpu(200, 200) // half of the history's interval busy
	mon.record()
	if got := mon.history[CPU]; !reflect.DeepEqual(got, []float64{50}) {
		t.Errorf("history cpu %v, want [50]", got)
	}
}

func TestSleepingGPU(t *testing.T) {
	t.Parallel()
	m := newMachine(t)
	dev := "sys/class/drm/card1/device/"
	m.write(dev+"gpu_busy_percent", "42\n")
	m.write(dev+"hwmon/hwmon5/temp1_input", "60000\n")
	m.write(dev+"power/control", "auto\n")
	m.write(dev+"power/runtime_status", "suspended\n")
	m.write(dev+"drm/card1/card1-DP-1/status", "disconnected\n")
	c := &clock{now: time.UnixMilli(0)}
	mon := m.monitor(c, false, nil)
	fetch := m.fetcher(mon)
	mon.Keep("shell", []string{GPU, Mem})
	kept := func() []string {
		mon.mu.Lock()
		defer mon.mu.Unlock()
		return mon.kept(c.Now())
	}
	if st := fetch(`{"metrics": ["gpu"]}`); !st.HasGPU || *st.GPUUsage != 0 || st.GPUTemp != nil {
		t.Errorf("a card asleep reads idle, unread: %+v", st)
	}
	if got := kept(); !reflect.DeepEqual(got, []string{Mem}) {
		t.Errorf("a card that may sleep is kept in the background: %v", got)
	}
	// A screen keeps it awake anyway: kept, and read
	m.write(dev+"drm/card1/card1-DP-1/status", "connected\n")
	m.write(dev+"power/runtime_status", "active\n")
	if got := kept(); !reflect.DeepEqual(got, []string{Mem, GPU}) {
		t.Errorf("kept %v", got)
	}
	if st := fetch(`{"metrics": ["gpu"]}`); *st.GPUUsage != 42 || *st.GPUTemp != 60 {
		t.Errorf("gpu %+v", st)
	}
}

// run runs mon until the test ends
func run(t *testing.T, mon *Monitor) {
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		mon.Run(ctx)
		close(done)
	}()
	t.Cleanup(func() {
		cancel()
		<-done
	})
}

func TestNvidiaStream(t *testing.T) {
	t.Parallel()
	m := newMachine(t)
	m.write("sys/bus/pci/devices/0000:01:00.0/vendor", "0x10de\n")
	m.write("sys/bus/pci/devices/0000:01:00.0/class", "0x030000\n")
	m.write("sys/bus/pci/devices/0000:01:00.0/power/control", "on\n")
	m.write("sys/bus/pci/devices/0000:01:00.0/power/runtime_status", "active\n")
	c := &clock{now: time.UnixMilli(0)}
	f := &streams{line: "37, 61\n", hold: make(chan struct{})}
	mon := m.monitor(c, true, f)
	fetch := m.fetcher(mon)
	run(t, mon)
	req := `{"interval": 1000, "metrics": ["gpu"]}`
	if st := fetch(req); !st.HasGPU || st.GPUUsage != nil {
		t.Fatalf("before the stream's first line: %+v", st)
	}
	close(f.hold)
	if !testkit.Eventually(func() bool {
		st := fetch(req)
		return st.GPUUsage != nil && *st.GPUUsage == 37 && *st.GPUTemp == 61
	}) {
		t.Fatal("the stream's line never came")
	}
	// A faster interval restarts it; one stream at a time
	fetch(`{"interval": 500, "metrics": ["gpu"]}`)
	if !testkit.Eventually(func() bool {
		starts, live := f.state()
		return slices.Equal(starts, []time.Duration{time.Second, 500 * time.Millisecond}) && live == 1
	}) {
		t.Fatalf("starts %v", f.starts)
	}
	// With the topic gone the lease ends and so does the stream
	c.add(time.Minute)
	mon.signal()
	if !testkit.Eventually(func() bool { _, live := f.state(); return live == 0 }) {
		t.Fatal("the stream outlived its lease")
	}
	// A card asleep is never streamed (that would wake it)
	m.write("sys/bus/pci/devices/0000:01:00.0/power/runtime_status", "suspended\n")
	if st := fetch(req); *st.GPUUsage != 0 || st.GPUTemp != nil {
		t.Errorf("asleep: %+v", st)
	}
	time.Sleep(50 * time.Millisecond)
	if starts, _ := f.state(); len(starts) != 2 {
		t.Errorf("a card asleep was streamed: %v", starts)
	}
}

func TestNvidiaKeptAndRetried(t *testing.T) {
	t.Parallel()
	m := newMachine(t)
	c := &clock{now: time.UnixMilli(0)}
	f := &streams{fail: true}
	mon := m.monitor(c, true, f)
	// No PCI device found: never sleeps, so the history keeps it
	mon.Keep("shell", []string{GPU})
	run(t, mon)
	if !testkit.Eventually(func() bool { starts, _ := f.state(); return len(starts) == 1 }) {
		t.Fatal("the history never started the stream")
	}
	if starts, _ := f.state(); starts[0] != time.Second {
		t.Errorf("history stream every %v", starts[0])
	}
	// A failed start waits streamRetry, then tries again
	mon.signal()
	time.Sleep(50 * time.Millisecond)
	if starts, _ := f.state(); len(starts) != 1 {
		t.Fatalf("retried at once: %v", starts)
	}
	f.mu.Lock()
	f.fail = false
	f.mu.Unlock()
	c.add(streamRetry)
	mon.signal()
	if !testkit.Eventually(func() bool { _, live := f.state(); return live == 1 }) {
		t.Fatal("never retried")
	}
}

// A stream the topic alone wants starts again after a failure with
// nothing but the topic's fetches waking the loop
func TestNvidiaRetriedForTheTopic(t *testing.T) {
	t.Parallel()
	m := newMachine(t)
	c := &clock{now: time.UnixMilli(0)}
	f := &streams{line: "37, 61\n", fail: true}
	mon := m.monitor(c, true, f)
	fetch := m.fetcher(mon)
	run(t, mon)
	req := `{"interval": 1000, "metrics": ["gpu"]}`
	fetch(req)
	if !testkit.Eventually(func() bool { starts, _ := f.state(); return len(starts) == 1 }) {
		t.Fatal("the topic never started the stream")
	}
	f.mu.Lock()
	f.fail = false
	f.mu.Unlock()
	// Fetched every second until the wait is over, the lease never ending
	for range streamRetry / time.Second {
		c.add(time.Second)
		fetch(req)
	}
	if !testkit.Eventually(func() bool { _, live := f.state(); return live == 1 }) {
		t.Fatal("never retried")
	}
}

func TestParseNvidia(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		line        string
		usage, temp int
		ok          bool
	}{
		{"37, 61", 37, 61, true},
		{"0,45", 0, 45, true},
		{"[N/A], 45", 0, 45, false},
		{"", 0, 0, false},
	} {
		usage, temp, ok := parseNvidia(tc.line)
		if usage != tc.usage || temp != tc.temp || ok != tc.ok {
			t.Errorf("%q: %d %d %v", tc.line, usage, temp, ok)
		}
	}
}

// A card asleep when the topic asks is streamed once it wakes, with
// nothing but the topic's fetches waking the loop
func TestNvidiaStreamedOnceAwake(t *testing.T) {
	t.Parallel()
	m := newMachine(t)
	dev := "sys/bus/pci/devices/0000:01:00.0/"
	m.write(dev+"vendor", "0x10de\n")
	m.write(dev+"class", "0x030000\n")
	m.write(dev+"power/control", "auto\n")
	m.write(dev+"power/runtime_status", "suspended\n")
	c := &clock{now: time.UnixMilli(0)}
	f := &streams{line: "37, 61\n"}
	mon := m.monitor(c, true, f)
	fetch := m.fetcher(mon)
	run(t, mon)
	req := `{"interval": 1000, "metrics": ["gpu"]}`
	fetch(req)
	time.Sleep(50 * time.Millisecond)
	if starts, _ := f.state(); len(starts) != 0 {
		t.Fatalf("a card asleep was streamed: %v", starts)
	}
	m.write(dev+"power/runtime_status", "active\n")
	for range 3 {
		c.add(time.Second)
		fetch(req)
	}
	if !testkit.Eventually(func() bool { _, live := f.state(); return live == 1 }) {
		t.Fatal("a card that woke was never streamed")
	}
}

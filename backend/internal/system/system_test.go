package system

import (
	"context"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strconv"
	"testing"
	"time"
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

type clock struct{ now time.Time }

func (c *clock) Now() time.Time { return c.now }

func (m *machine) source(c *clock, nvidia bool) func(requests ...string) State {
	src := Source(Options{
		Proc: filepath.Join(m.dir, "proc"),
		Sys:  filepath.Join(m.dir, "sys"),
		Home: "/home/u",
		Now:  c.Now,
		Sleep: func(ctx context.Context, d time.Duration) {
			c.now = c.now.Add(d)
		},
		LookPath: func(file string) (string, error) {
			if nvidia && file == "nvidia-smi" {
				return "/usr/bin/nvidia-smi", nil
			}
			return "", exec.ErrNotFound
		},
		NvidiaSMI: func(ctx context.Context, bin string) []byte { return []byte("37, 61\n") },
	})
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

func TestCPUAndNet(t *testing.T) {
	t.Parallel()
	m := newMachine(t)
	c := &clock{time.UnixMilli(10_000)}
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
	c.now = c.now.Add(2 * time.Second)
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
	c.now = c.now.Add(time.Minute)
	if st := fetch(req); st.CPUUsage != nil || st.NetRx != nil {
		t.Errorf("a sample after a pause measured over it: %+v", st)
	}
}

func TestMemAndUnion(t *testing.T) {
	t.Parallel()
	m := newMachine(t)
	fetch := m.source(&clock{time.UnixMilli(0)}, false)
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
		{"nvidia", func(m *machine) {}, true, false, true, 0, 37, 61},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			m := newMachine(t)
			tc.setup(m)
			st := m.source(&clock{time.UnixMilli(0)}, tc.nvidia)(`{"metrics": ["cpuTemp", "gpu"]}`)
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
	c := &clock{time.UnixMilli(0)}
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
	c := &clock{time.UnixMilli(0)}
	fetch := m.source(c, false)
	req := `{"metrics": ["processes"]}`
	// The first list reads twice (Sleep advances the clock half a second)
	first := fetch(req)
	if n := len(first.Processes); n != 2 {
		t.Fatalf("%d processes", n)
	}
	m.proc(42, "my (odd) app", 600, 100000, "0") // 100 ticks = 1 s of CPU; 400 MB of 16 GB
	c.now = c.now.Add(2 * time.Second)
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

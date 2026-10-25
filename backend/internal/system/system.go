// Package system is the machine's load for the shell, the `system` polled
// topic: CPU, memory, temperatures, GPU, network throughput, disk usage
// and the process list, read from /proc and /sys (and `nvidia-smi` for an
// NVIDIA card without an AMD one), only the metrics some subscriber asks
// for. Each push is one sample; the graphs' history stays the shell's
// (SystemManager). Also `system.kill`, which signals a process.
package system

import (
	"bytes"
	"context"
	"encoding/json"
	"math"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/topics"
)

// The metrics a request names
const (
	CPU       = "cpu"
	Mem       = "mem"
	CPUTemp   = "cpuTemp"
	GPU       = "gpu"
	Disk      = "disk"
	Net       = "net"
	Processes = "processes"
)

// State is one sample (SystemManager); a metric nobody asked for is left
// out.
type State struct {
	// At is when it was taken (ms since the epoch): every sample differs,
	// so each one is pushed and the shell's history gets them all
	At            int64            `json:"at"`
	HasCPUTemp    bool             `json:"hasCpuTemp"`
	HasGPU        bool             `json:"hasGpu"`
	CPUUsage      *int             `json:"cpuUsage,omitempty"` // percent
	CPUTemp       *int             `json:"cpuTemp,omitempty"`  // °C
	MemUsage      *int             `json:"memUsage,omitempty"`
	MemUsedBytes  *int64           `json:"memUsedBytes,omitempty"`
	MemTotalBytes *int64           `json:"memTotalBytes,omitempty"`
	GPUUsage      *int             `json:"gpuUsage,omitempty"`
	GPUTemp       *int             `json:"gpuTemp,omitempty"`
	NetRx         *float64         `json:"netRx,omitempty"` // bytes per second, all but loopback
	NetTx         *float64         `json:"netTx,omitempty"`
	Disks         map[string]Usage `json:"disks,omitempty"` // by the path as asked
	Processes     []Process        `json:"processes,omitempty"`
}

// Usage is a filesystem's, as `df` counts it.
type Usage struct {
	Used  int64 `json:"used"`
	Total int64 `json:"total"`
	Usage int   `json:"usage"` // percent
}

// Process is one row of the process list.
type Process struct {
	PID     int     `json:"pid"`
	User    string  `json:"user"`
	CPU     float64 `json:"cpu"` // percent of one core since the last sample, as top's
	Mem     float64 `json:"mem"` // percent of memory resident
	Command string  `json:"command"`
}

type request struct {
	Metrics   []string `json:"metrics"`
	DiskPaths []string `json:"diskPaths"`
	Interval  *float64 `json:"interval"` // ms
}

// Options are where the source reads; zero values are the real ones.
type Options struct {
	Proc, Sys string // "/proc", "/sys"
	Home      string // what a disk path's "~" stands for
	Now       func() time.Time
	// Sleep waits between the two reads of a first process list
	Sleep    func(ctx context.Context, d time.Duration)
	LookPath func(file string) (string, error)
	// NvidiaSMI returns `nvidia-smi --query-gpu=utilization.gpu,
	// temperature.gpu --format=csv,noheader,nounits`'s output
	NvidiaSMI func(ctx context.Context, bin string) []byte
}

const (
	// The kernel's USER_HZ, which /proc/<pid>/stat counts in: 100 on
	// every architecture Linux runs a desktop on
	clockTicks = 100
	pageSize   = 4096
	// Disk usage changes slowly and statfs can stall on a network mount
	diskEvery = time.Minute
	// A first process list's second read, so %CPU is current at once
	processWarmup = 500 * time.Millisecond
)

// Source is the `system` topic.
func Source(o Options) topics.Source {
	if o.Proc == "" {
		o.Proc = "/proc"
	}
	if o.Sys == "" {
		o.Sys = "/sys"
	}
	if o.Now == nil {
		o.Now = time.Now
	}
	if o.Sleep == nil {
		o.Sleep = func(ctx context.Context, d time.Duration) {
			select {
			case <-ctx.Done():
			case <-time.After(d):
			}
		}
	}
	if o.LookPath == nil {
		o.LookPath = exec.LookPath
	}
	if o.NvidiaSMI == nil {
		o.NvidiaSMI = nvidiaSMI
	}
	s := &sampler{o: o, users: map[string]string{}}
	return topics.Source{
		Name:    "system",
		Floor:   500 * time.Millisecond,
		Default: 2 * time.Second,
		Fetch: func(ctx context.Context, requests []json.RawMessage) (any, error) {
			return s.sample(ctx, requests), nil
		},
	}
}

// sampler keeps what a sample is measured against: the last CPU, network
// and per-process counters, and what discovery found.
type sampler struct {
	o Options
	// A loop stopped and started again can briefly overlap the old one
	mu sync.Mutex

	discovered               bool
	cpuTemp, gpuBusy, gpuTmp string // sysfs files, "" for none
	nvidia                   string // nvidia-smi's path, "" for none

	last              time.Time // the last sample
	cpuTotal, cpuIdle uint64
	rx, tx            uint64
	netAt             time.Time
	procTicks         map[int]uint64
	procAt            time.Time
	disks             map[string]Usage
	diskAt            time.Time
	diskKey           string
	users             map[string]string // uid -> name
}

func (s *sampler) sample(ctx context.Context, requests []json.RawMessage) State {
	s.mu.Lock()
	defer s.mu.Unlock()
	var metrics, paths []string
	interval := time.Duration(0)
	for _, raw := range requests {
		var r request
		if json.Unmarshal(raw, &r) != nil {
			continue
		}
		for _, m := range r.Metrics {
			if !slices.Contains(metrics, m) {
				metrics = append(metrics, m)
			}
		}
		for _, p := range r.DiskPaths {
			if p != "" && !slices.Contains(paths, p) {
				paths = append(paths, p)
			}
		}
		if r.Interval != nil {
			if d := time.Duration(*r.Interval * float64(time.Millisecond)); interval == 0 || d < interval {
				interval = d
			}
		}
	}
	if !s.discovered {
		s.discover()
	}
	now := s.o.Now()
	// A sample after a pause is measured afresh, not averaged over it
	if interval <= 0 {
		interval = 2 * time.Second
	}
	if !s.last.IsZero() && now.Sub(s.last) > 3*max(interval, 500*time.Millisecond) {
		s.cpuTotal, s.netAt, s.procTicks = 0, time.Time{}, nil
	}
	s.last = now
	wants := func(m string) bool { return slices.Contains(metrics, m) }

	st := State{At: now.UnixMilli(), HasCPUTemp: s.cpuTemp != "", HasGPU: s.gpuBusy != "" || s.nvidia != ""}
	if wants(CPU) {
		st.CPUUsage = s.cpu()
	}
	if wants(Mem) {
		if total, avail := s.meminfo(); total > 0 {
			st.MemTotalBytes, st.MemUsedBytes = ptr(total), ptr(total-avail)
			st.MemUsage = ptr(round(float64(total-avail) / float64(total) * 100))
		}
	}
	if wants(CPUTemp) && s.cpuTemp != "" {
		st.CPUTemp = ptr(round(float64(readInt(s.cpuTemp)) / 1000))
	}
	if wants(GPU) {
		if s.gpuBusy != "" {
			st.GPUUsage = ptr(int(readInt(s.gpuBusy)))
			if s.gpuTmp != "" {
				st.GPUTemp = ptr(round(float64(readInt(s.gpuTmp)) / 1000))
			}
		} else if s.nvidia != "" {
			usage, temp := parseNvidia(s.o.NvidiaSMI(ctx, s.nvidia))
			st.GPUUsage, st.GPUTemp = &usage, &temp
		}
	}
	if wants(Net) {
		st.NetRx, st.NetTx = s.net(now)
	}
	if wants(Disk) && len(paths) > 0 {
		st.Disks = s.diskUsage(now, paths)
	}
	if wants(Processes) {
		st.Processes = s.processes(ctx)
	}
	return st
}

// discover finds the CPU package sensor and the AMD card with the most
// VRAM (the discrete one, when there's also an iGPU); nvidia-smi only
// stands in without one.
func (s *sampler) discover() {
	s.discovered = true
	hwmons, _ := filepath.Glob(filepath.Join(s.o.Sys, "class/hwmon/hwmon*"))
	for _, h := range hwmons {
		switch readString(filepath.Join(h, "name")) {
		case "k10temp", "coretemp", "zenpower":
			s.cpuTemp = filepath.Join(h, "temp1_input")
		}
		if s.cpuTemp != "" {
			break
		}
	}
	cards, _ := filepath.Glob(filepath.Join(s.o.Sys, "class/drm/card*/device"))
	best := int64(-1)
	card := ""
	for _, d := range cards {
		if _, err := os.Stat(filepath.Join(d, "gpu_busy_percent")); err != nil {
			continue
		}
		if vram := readInt(filepath.Join(d, "mem_info_vram_total")); vram > best {
			best, card = vram, d
		}
	}
	if card != "" {
		s.gpuBusy = filepath.Join(card, "gpu_busy_percent")
		if temps, _ := filepath.Glob(filepath.Join(card, "hwmon/*/temp1_input")); len(temps) > 0 {
			s.gpuTmp = temps[0]
		}
	} else if bin, err := s.o.LookPath("nvidia-smi"); err == nil {
		s.nvidia = bin
	}
}

// cpu is the usage since the last read of /proc/stat (nil on the first).
func (s *sampler) cpu() *int {
	data, err := os.ReadFile(filepath.Join(s.o.Proc, "stat"))
	if err != nil {
		return nil
	}
	line, _, _ := bytes.Cut(data, []byte("\n"))
	// cpu  user nice system idle iowait irq softirq steal ...
	f := strings.Fields(string(line))
	if len(f) < 5 || f[0] != "cpu" {
		return nil
	}
	var total, idle uint64
	for i, v := range f[1:min(len(f), 9)] {
		n, _ := strconv.ParseUint(v, 10, 64)
		total += n
		if i == 3 || i == 4 {
			idle += n
		}
	}
	prevTotal, prevIdle := s.cpuTotal, s.cpuIdle
	s.cpuTotal, s.cpuIdle = total, idle
	if prevTotal == 0 || total <= prevTotal {
		return nil
	}
	return ptr(round((1 - float64(idle-prevIdle)/float64(total-prevTotal)) * 100))
}

// meminfo is MemTotal and MemAvailable in bytes.
func (s *sampler) meminfo() (total, avail int64) {
	data, _ := os.ReadFile(filepath.Join(s.o.Proc, "meminfo"))
	for line := range strings.SplitSeq(string(data), "\n") {
		f := strings.Fields(line)
		if len(f) < 2 {
			continue
		}
		n, _ := strconv.ParseInt(f[1], 10, 64)
		switch f[0] {
		case "MemTotal:":
			total = n * 1024
		case "MemAvailable:":
			avail = n * 1024
		}
	}
	return total, avail
}

// net is the throughput since the last read of /proc/net/dev (nil on the
// first).
func (s *sampler) net(now time.Time) (rx, tx *float64) {
	data, err := os.ReadFile(filepath.Join(s.o.Proc, "net/dev"))
	if err != nil {
		return nil, nil
	}
	var r, t uint64
	for i, line := range strings.Split(string(data), "\n") {
		name, rest, ok := strings.Cut(line, ":")
		if i < 2 || !ok || strings.TrimSpace(name) == "lo" {
			continue
		}
		f := strings.Fields(rest)
		if len(f) < 9 {
			continue
		}
		a, _ := strconv.ParseUint(f[0], 10, 64)
		b, _ := strconv.ParseUint(f[8], 10, 64)
		r, t = r+a, t+b
	}
	prevRx, prevTx, prevAt := s.rx, s.tx, s.netAt
	s.rx, s.tx, s.netAt = r, t, now
	if prevAt.IsZero() || !now.After(prevAt) {
		return nil, nil
	}
	secs := now.Sub(prevAt).Seconds()
	// A counter that went back (an interface gone) is no traffic
	rate := func(cur, prev uint64) *float64 {
		if cur < prev {
			return ptr(0.0)
		}
		return ptr(float64(cur-prev) / secs)
	}
	return rate(r, prevRx), rate(t, prevTx)
}

// diskUsage is statfs for each path, on its own slow clock, or at once
// when the paths change.
func (s *sampler) diskUsage(now time.Time, paths []string) map[string]Usage {
	key := strings.Join(paths, "\n")
	if key == s.diskKey && now.Sub(s.diskAt) < diskEvery {
		return s.disks
	}
	s.diskKey, s.diskAt = key, now
	s.disks = map[string]Usage{}
	for _, p := range paths {
		path := p
		if rest, ok := strings.CutPrefix(p, "~"); ok && (rest == "" || rest[0] == '/') && s.o.Home != "" {
			path = s.o.Home + rest
		}
		var fs syscall.Statfs_t
		if syscall.Statfs(path, &fs) != nil || fs.Blocks == 0 {
			continue
		}
		bs := int64(fs.Frsize)
		if bs == 0 {
			bs = fs.Bsize
		}
		total := int64(fs.Blocks) * bs
		used := int64(fs.Blocks-fs.Bfree) * bs
		s.disks[p] = Usage{Used: used, Total: total, Usage: round(float64(used) / float64(total) * 100)}
	}
	return s.disks
}

// processes is every process with its CPU since the last list; the first
// list reads twice, processWarmup apart.
func (s *sampler) processes(ctx context.Context) []Process {
	if s.procTicks == nil {
		s.procTicks, s.procAt = s.readProcs(nil), s.o.Now()
		s.o.Sleep(ctx, processWarmup)
	}
	memTotal, _ := s.meminfo()
	list := []Process{}
	ticks := s.readProcs(func(pid int, comm string, rss int64, uid string) {
		list = append(list, Process{PID: pid, User: s.user(uid), Command: comm, Mem: percent(rss*pageSize, memTotal)})
	})
	now := s.o.Now()
	secs := now.Sub(s.procAt).Seconds()
	for i := range list {
		p := &list[i]
		if prev, ok := s.procTicks[p.PID]; ok && secs > 0 && ticks[p.PID] >= prev {
			p.CPU = math.Round(float64(ticks[p.PID]-prev)/clockTicks/secs*1000) / 10
		}
	}
	s.procTicks, s.procAt = ticks, now
	slices.SortStableFunc(list, func(a, b Process) int {
		switch {
		case a.CPU > b.CPU:
			return -1
		case a.CPU < b.CPU:
			return 1
		}
		return a.PID - b.PID
	})
	return list
}

// readProcs reads every /proc/<pid>/stat for its CPU ticks, calling each
// (when set) with the rest a row shows.
func (s *sampler) readProcs(each func(pid int, comm string, rss int64, uid string)) map[int]uint64 {
	entries, _ := os.ReadDir(s.o.Proc)
	ticks := map[int]uint64{}
	for _, e := range entries {
		pid, err := strconv.Atoi(e.Name())
		if err != nil || pid <= 0 {
			continue
		}
		dir := filepath.Join(s.o.Proc, e.Name())
		comm, t, rss, ok := parseStat(readString(filepath.Join(dir, "stat")))
		if !ok {
			continue // gone since the listing
		}
		ticks[pid] = t
		if each != nil {
			each(pid, comm, rss, statusUID(readString(filepath.Join(dir, "status"))))
		}
	}
	return ticks
}

// parseStat reads /proc/<pid>/stat: comm (in parentheses, and may hold
// any character), utime + stime and rss (pages).
func parseStat(line string) (comm string, ticks uint64, rss int64, ok bool) {
	open, end := strings.IndexByte(line, '('), strings.LastIndexByte(line, ')')
	if open < 0 || end < open {
		return "", 0, 0, false
	}
	comm = line[open+1 : end]
	// After comm: state(3) ... utime(14) stime(15) ... rss(24)
	f := strings.Fields(line[end+1:])
	if len(f) < 22 {
		return "", 0, 0, false
	}
	utime, _ := strconv.ParseUint(f[11], 10, 64)
	stime, _ := strconv.ParseUint(f[12], 10, 64)
	rss, _ = strconv.ParseInt(f[21], 10, 64)
	return comm, utime + stime, rss, true
}

// statusUID is the effective uid in /proc/<pid>/status (top's USER).
func statusUID(status string) string {
	for line := range strings.SplitSeq(status, "\n") {
		if rest, ok := strings.CutPrefix(line, "Uid:"); ok {
			if f := strings.Fields(rest); len(f) >= 2 {
				return f[1]
			}
		}
	}
	return ""
}

func (s *sampler) user(uid string) string {
	if name, ok := s.users[uid]; ok {
		return name
	}
	name := uid
	if u, err := user.LookupId(uid); err == nil {
		name = u.Username
	}
	s.users[uid] = name
	return name
}

func parseNvidia(out []byte) (usage, temp int) {
	line, _, _ := strings.Cut(string(out), "\n")
	f := strings.Split(line, ",")
	if len(f) >= 2 {
		usage, _ = strconv.Atoi(strings.TrimSpace(f[0]))
		temp, _ = strconv.Atoi(strings.TrimSpace(f[1]))
	}
	return usage, temp
}

func nvidiaSMI(ctx context.Context, bin string) []byte {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	out, _ := exec.CommandContext(ctx, bin, "--query-gpu=utilization.gpu,temperature.gpu", "--format=csv,noheader,nounits").Output()
	return out
}

// Kill sends pid SIGTERM (`system.kill`, the process list's End). Init and
// anything not a process id are refused.
func Kill(pid int) error {
	if pid <= 1 {
		return axerr.New(axerr.BadRequest, "system.kill: no process %d", pid)
	}
	switch err := syscall.Kill(pid, syscall.SIGTERM); err {
	case nil:
	case syscall.ESRCH:
		return axerr.Wrap(axerr.NotFound, err, "system.kill %d", pid)
	default:
		return axerr.Wrap(axerr.Refused, err, "system.kill %d", pid)
	}
	return nil
}

func readString(path string) string {
	data, _ := os.ReadFile(path)
	return strings.TrimSpace(string(data))
}

func readInt(path string) int64 {
	n, _ := strconv.ParseInt(readString(path), 10, 64)
	return n
}

func percent(part, whole int64) float64 {
	if whole <= 0 {
		return 0
	}
	return math.Round(float64(part)/float64(whole)*1000) / 10
}

func round(f float64) int { return int(math.Round(f)) }

func ptr[T any](v T) *T { return &v }

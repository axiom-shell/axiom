// Package sysmon is the machine's load for the shell, the `system` polled
// topic: CPU, memory, temperatures, GPU, network throughput, disk usage
// and the process list, read from /proc and /sys (and a streamed
// `nvidia-smi` for an NVIDIA card without an AMD one), only the metrics
// some subscriber asks for. It also keeps the graphs' history: the last
// minute of each graphed metric, sampled once a second in-process while
// the shell names it (`system.keep`, from config) or a graph is open, so
// a graph opens with its minute already drawn and nothing is pushed while
// none is shown. Also `system.kill`, which signals a process.
package sysmon

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"math"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"reflect"
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

// graphed are the metrics with a history, in the order kept
var graphed = []string{CPU, Mem, GPU, CPUTemp, Net}

const (
	// HistoryLength is how many samples a history holds (SystemManager's
	// historyLength), one every historyEvery: a minute
	HistoryLength = 60
	historyEvery  = time.Second
)

// State is one sample (SystemManager); a metric nobody asked for is left
// out.
type State struct {
	// At is when it was taken (ms since the epoch): every sample differs,
	// so each one is pushed
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
	// History is the last HistoryLength samples, oldest first, one a
	// second, of each metric kept (cpu, mem, gpu, cpuTemp, netRx, netTx),
	// only while some request asks for it
	History map[string][]float64 `json:"history,omitempty"`
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
	// History asks for State.History: the graphed metrics it names are
	// kept while it's asked
	History []string `json:"history"`
}

// Options are where the monitor reads; zero values are the real ones.
type Options struct {
	Proc, Sys string // "/proc", "/sys"
	Home      string // what a disk path's "~" stands for
	Log       *slog.Logger
	Now       func() time.Time
	// After is the ring loop's timer
	After func(time.Duration) <-chan time.Time
	// Sleep waits between the two reads of a first process list
	Sleep    func(ctx context.Context, d time.Duration)
	LookPath func(file string) (string, error)
	// NvidiaStream starts `nvidia-smi … --loop-ms` (a line of
	// "usage, temp" every interval) until ctx ends
	NvidiaStream func(ctx context.Context, bin string, every time.Duration) (io.ReadCloser, error)
}

const (
	// The kernel's USER_HZ, which /proc/<pid>/stat counts in: 100 on
	// every architecture Linux runs a desktop on
	clockTicks = 100
	// Disk usage changes slowly and statfs can stall on a network mount
	diskEvery = time.Minute
	// A first process list's second read, so %CPU is current at once
	processWarmup = 500 * time.Millisecond
)

// rss in /proc/<pid>/stat counts pages: 16 KiB on Asahi, not 4
var pageSize = int64(os.Getpagesize())

// Monitor is the `system` topic's sampler, the graphs' history and the
// NVIDIA stream, for the daemon's lifetime.
type Monitor struct {
	o    Options
	hub  *sampler
	wake chan struct{}

	mu         sync.Mutex
	discovered bool
	sn         sensors
	// keeps: each connection's `system.keep`; held: the graphed metrics a
	// history request names, until its lease ends (the hub stops fetching
	// with no subscribers, and says nothing)
	keeps    map[any][]string
	held     map[string]time.Time
	ring     counters
	ringLast time.Time
	history  map[string][]float64
	gpu      nvidia
}

// New returns a monitor; the daemon runs its Run.
func New(o Options) *Monitor {
	if o.Proc == "" {
		o.Proc = "/proc"
	}
	if o.Sys == "" {
		o.Sys = "/sys"
	}
	if o.Log == nil {
		o.Log = slog.New(slog.DiscardHandler)
	}
	if o.Now == nil {
		o.Now = time.Now
	}
	if o.After == nil {
		o.After = time.After
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
	if o.NvidiaStream == nil {
		o.NvidiaStream = nvidiaStream
	}
	m := &Monitor{
		o:       o,
		wake:    make(chan struct{}, 1),
		keeps:   map[any][]string{},
		held:    map[string]time.Time{},
		history: map[string][]float64{},
	}
	m.hub = &sampler{m: m, users: map[string]string{}}
	return m
}

// Source is the `system` topic.
func (m *Monitor) Source() topics.Source {
	return topics.Source{
		Name:    "system",
		Floor:   topics.MinInterval,
		Default: 2 * time.Second,
		Request: reflect.TypeFor[request](),
		State:   reflect.TypeFor[State](),
		Fetch: func(ctx context.Context, requests []json.RawMessage) (any, error) {
			return m.hub.sample(ctx, requests), nil
		},
	}
}

// Keep sets the graphed metrics owner (a connection) wants a history of
// from now on, whether or not anything shows them (`system.keep`).
func (m *Monitor) Keep(owner any, metrics []string) error {
	var kept []string
	for _, metric := range metrics {
		if !slices.Contains(graphed, metric) {
			return axerr.New(axerr.BadRequest, "system.keep: %q has no history", metric)
		}
		if !slices.Contains(kept, metric) {
			kept = append(kept, metric)
		}
	}
	m.mu.Lock()
	if len(kept) == 0 {
		delete(m.keeps, owner)
	} else {
		m.keeps[owner] = kept
	}
	m.mu.Unlock()
	m.signal()
	return nil
}

// Forget drops owner's keep (a connection that closed).
func (m *Monitor) Forget(owner any) {
	m.mu.Lock()
	_, ok := m.keeps[owner]
	delete(m.keeps, owner)
	m.mu.Unlock()
	if ok {
		m.signal()
	}
}

func (m *Monitor) signal() {
	select {
	case m.wake <- struct{}{}:
	default:
	}
}

// Run samples the kept metrics into their histories once a second while
// any is kept, and runs the NVIDIA stream while anything wants it; it
// sleeps without either.
func (m *Monitor) Run(ctx context.Context) error {
	var stream *streamProc
	defer func() { stream.stop() }()
	var next time.Time
	for {
		m.mu.Lock()
		now := m.o.Now()
		ringOn := len(m.kept(now)) > 0
		want, retry := m.streamWant(now)
		m.mu.Unlock()

		if stream != nil && (stream.every != want || stream.ended()) {
			stream.stop()
			stream = nil
		}
		if stream == nil && want > 0 && retry {
			stream = m.startStream(ctx, want)
		}

		var tick <-chan time.Time
		if ringOn {
			if next.IsZero() || now.Sub(next) > 3*historyEvery {
				next = now
			}
			if !now.Before(next) {
				m.record()
				next = next.Add(historyEvery)
			}
			tick = m.o.After(next.Sub(now))
		} else {
			next = time.Time{}
		}
		var ended <-chan struct{}
		if stream != nil {
			ended = stream.done
		}
		select {
		case <-ctx.Done():
			return nil
		case <-m.wake:
		case <-tick:
		case <-ended:
		}
	}
}

// kept is every metric with a history now, in graphed's order: a GPU that
// may sleep only while a graph shows it (m.mu held).
func (m *Monitor) kept(now time.Time) []string {
	m.discover()
	var out []string
	for _, metric := range graphed {
		until, held := m.held[metric]
		if held && !now.Before(until) {
			delete(m.held, metric)
			held = false
		}
		kept := false
		for _, list := range m.keeps {
			kept = kept || slices.Contains(list, metric)
		}
		if metric == GPU && (!m.sn.hasGPU() || m.sn.maySleep()) {
			kept = false
		}
		if held || kept {
			out = append(out, metric)
		}
	}
	return out
}

// hold keeps metrics' histories for a history request, until a lease of
// a few of its intervals ends
func (m *Monitor) hold(metrics []string, until time.Time) {
	m.mu.Lock()
	added := false
	for _, metric := range metrics {
		if slices.Contains(graphed, metric) {
			_, had := m.held[metric]
			added = added || !had
			m.held[metric] = until
		}
	}
	m.mu.Unlock()
	if added {
		m.signal()
	}
}

// record takes one sample of each kept metric into its history.
func (m *Monitor) record() {
	m.mu.Lock()
	defer m.mu.Unlock()
	now := m.o.Now()
	kept := m.kept(now)
	// A sample after a pause (a suspend) is measured afresh
	if !m.ringLast.IsZero() && now.Sub(m.ringLast) > 3*historyEvery {
		m.ring = counters{}
	}
	m.ringLast = now
	push := func(key string, v float64) {
		list := append(m.history[key], v)
		if len(list) > HistoryLength {
			list = slices.Clone(list[len(list)-HistoryLength:])
		}
		m.history[key] = list
	}
	keys := map[string]bool{}
	for _, metric := range kept {
		switch metric {
		case CPU:
			if v := m.ring.cpu(m.o.Proc); v != nil {
				push(CPU, float64(*v))
			}
		case Mem:
			if total, avail := meminfo(m.o.Proc); total > 0 {
				push(Mem, float64(round(float64(total-avail)/float64(total)*100)))
			}
		case CPUTemp:
			if m.sn.cpuTemp != "" {
				push(CPUTemp, float64(round(float64(readInt(m.sn.cpuTemp))/1000)))
			}
		case GPU:
			if usage, _ := m.gpuNow(now, historyEvery); usage != nil {
				push(GPU, float64(*usage))
			}
		case Net:
			if rx, tx := m.ring.net(m.o.Proc, now); rx != nil {
				push("netRx", *rx)
				push("netTx", *tx)
			}
			keys["netRx"], keys["netTx"] = true, true
			continue
		}
		keys[metric] = true
	}
	// A metric no longer kept starts afresh when it's kept again
	for key := range m.history {
		if !keys[key] {
			delete(m.history, key)
		}
	}
}

// historyCopy is every kept history as it is (m.mu held).
func (m *Monitor) historyCopy() map[string][]float64 {
	out := make(map[string][]float64, len(m.history))
	for key, list := range m.history {
		out[key] = slices.Clone(list)
	}
	return out
}

// sensors are what discovery found: sysfs files, "" for none.
type sensors struct {
	cpuTemp string
	// The GPU: amdgpu's files, or nvidia-smi's path; dev is its PCI
	// device (its power state and screens), "" when unknown
	gpuBusy, gpuTemp, nvidia, dev string
}

func (s sensors) hasGPU() bool { return s.gpuBusy != "" || s.nvidia != "" }

// asleep: the GPU is runtime-suspended (reading the status never wakes
// it; reading the card would)
func (s sensors) asleep() bool {
	return s.dev != "" && readString(filepath.Join(s.dev, "power/runtime_status")) == "suspended"
}

// maySleep: the GPU runtime-suspends when idle (power/control "auto") and
// drives no screen, so reading it every second would keep it awake; a
// card with a screen connected never suspends anyway
func (s sensors) maySleep() bool {
	if s.dev == "" || readString(filepath.Join(s.dev, "power/control")) != "auto" {
		return false
	}
	connectors, _ := filepath.Glob(filepath.Join(s.dev, "drm/card*/card*-*/status"))
	for _, c := range connectors {
		if readString(c) == "connected" {
			return false
		}
	}
	return true
}

// discover finds the CPU package sensor and the AMD card with the most
// VRAM (the discrete one, when there's also an iGPU); nvidia-smi only
// stands in without one (m.mu held).
func (m *Monitor) discover() {
	if m.discovered {
		return
	}
	m.discovered = true
	sys := m.o.Sys
	hwmons, _ := filepath.Glob(filepath.Join(sys, "class/hwmon/hwmon*"))
	for _, h := range hwmons {
		switch readString(filepath.Join(h, "name")) {
		case "k10temp", "coretemp", "zenpower":
			m.sn.cpuTemp = filepath.Join(h, "temp1_input")
		}
		if m.sn.cpuTemp != "" {
			break
		}
	}
	cards, _ := filepath.Glob(filepath.Join(sys, "class/drm/card*/device"))
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
		m.sn.dev = card
		m.sn.gpuBusy = filepath.Join(card, "gpu_busy_percent")
		if temps, _ := filepath.Glob(filepath.Join(card, "hwmon/*/temp1_input")); len(temps) > 0 {
			m.sn.gpuTemp = temps[0]
		}
		return
	}
	bin, err := m.o.LookPath("nvidia-smi")
	if err != nil {
		return
	}
	m.sn.nvidia = bin
	// The first NVIDIA display controller, what `nvidia-smi -i 0` reads
	devs, _ := filepath.Glob(filepath.Join(sys, "bus/pci/devices/*"))
	for _, d := range devs {
		if readString(filepath.Join(d, "vendor")) == "0x10de" && strings.HasPrefix(readString(filepath.Join(d, "class")), "0x03") {
			m.sn.dev = d
			break
		}
	}
}

// gpuNow is the GPU's usage and temperature now (nil for unknown): 0 for
// a card asleep, never woken; an NVIDIA card's from its stream's latest
// line, if one came within a few intervals (m.mu held).
func (m *Monitor) gpuNow(now time.Time, every time.Duration) (usage, temp *int) {
	switch {
	case !m.sn.hasGPU():
		return nil, nil
	case m.sn.asleep():
		return ptr(0), nil
	case m.sn.gpuBusy != "":
		usage = ptr(int(readInt(m.sn.gpuBusy)))
		if m.sn.gpuTemp != "" {
			temp = ptr(round(float64(readInt(m.sn.gpuTemp)) / 1000))
		}
		return usage, temp
	}
	if m.gpu.at.IsZero() || now.Sub(m.gpu.at) > 3*max(every, m.gpu.every, historyEvery) {
		return nil, nil
	}
	return ptr(m.gpu.usage), ptr(m.gpu.temp)
}

// sampler is the topic's fetch: it keeps what a sample is measured
// against, the last CPU, network and per-process counters.
type sampler struct {
	m *Monitor
	// A loop stopped and started again can briefly overlap the old one
	mu sync.Mutex

	last      time.Time // the last sample
	c         counters
	procTicks map[int]uint64
	procAt    time.Time
	disks     map[string]Usage
	diskAt    time.Time
	diskKey   string
	users     map[string]string // uid -> name
}

func (s *sampler) sample(ctx context.Context, requests []json.RawMessage) State {
	s.mu.Lock()
	defer s.mu.Unlock()
	m := s.m
	var metrics, paths, history []string
	interval := time.Duration(0)
	for _, raw := range requests {
		var r request
		if json.Unmarshal(raw, &r) != nil {
			continue
		}
		for _, metric := range r.Metrics {
			if !slices.Contains(metrics, metric) {
				metrics = append(metrics, metric)
			}
		}
		for _, metric := range r.History {
			if !slices.Contains(history, metric) {
				history = append(history, metric)
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
	now := m.o.Now()
	if interval <= 0 {
		interval = 2 * time.Second
	}
	// The leases of what this fetch asks of the ring and the stream: a
	// few intervals, renewed by every fetch
	lease := now.Add(3*max(interval, historyEvery) + historyEvery)
	if len(history) > 0 {
		m.hold(history, lease)
	}
	wants := func(metric string) bool { return slices.Contains(metrics, metric) }
	if wants(GPU) {
		m.leaseStream(interval, lease)
	}

	// A sample after a pause is measured afresh, not averaged over it
	if !s.last.IsZero() && now.Sub(s.last) > 3*max(interval, 500*time.Millisecond) {
		s.c, s.procTicks = counters{}, nil
	}
	s.last = now

	m.mu.Lock()
	m.discover()
	sn := m.sn
	st := State{At: now.UnixMilli(), HasCPUTemp: sn.cpuTemp != "", HasGPU: sn.hasGPU()}
	if wants(GPU) {
		st.GPUUsage, st.GPUTemp = m.gpuNow(now, interval)
	}
	if len(history) > 0 {
		st.History = m.historyCopy()
	}
	// A first CPU or network sample has nothing to measure against: the
	// history's newest stands in, when it's fresh
	newest := func(key string) *float64 {
		if list := m.history[key]; len(list) > 0 && now.Sub(m.ringLast) <= 2*historyEvery {
			return ptr(list[len(list)-1])
		}
		return nil
	}
	cpuNewest, rxNewest, txNewest := newest(CPU), newest("netRx"), newest("netTx")
	m.mu.Unlock()

	if wants(CPU) {
		if st.CPUUsage = s.c.cpu(m.o.Proc); st.CPUUsage == nil && cpuNewest != nil {
			st.CPUUsage = ptr(int(*cpuNewest))
		}
	}
	if wants(Mem) {
		if total, avail := meminfo(m.o.Proc); total > 0 {
			st.MemTotalBytes, st.MemUsedBytes = ptr(total), ptr(total-avail)
			st.MemUsage = ptr(round(float64(total-avail) / float64(total) * 100))
		}
	}
	if wants(CPUTemp) && sn.cpuTemp != "" {
		st.CPUTemp = ptr(round(float64(readInt(sn.cpuTemp)) / 1000))
	}
	if wants(Net) {
		if st.NetRx, st.NetTx = s.c.net(m.o.Proc, now); st.NetRx == nil && rxNewest != nil {
			st.NetRx, st.NetTx = rxNewest, txNewest
		}
	}
	if wants(Disk) && len(paths) > 0 {
		st.Disks = s.diskUsage(now, paths)
	}
	if wants(Processes) {
		st.Processes = s.processes(ctx)
	}
	return st
}

// counters are what CPU usage and network throughput are measured
// against: the topic's samples and the history's keep their own, so
// neither cuts the other's interval short.
type counters struct {
	cpuTotal, cpuIdle uint64
	rx, tx            uint64
	netAt             time.Time
}

// cpu is the usage since the last read of /proc/stat (nil on the first).
func (c *counters) cpu(proc string) *int {
	data, err := os.ReadFile(filepath.Join(proc, "stat"))
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
	prevTotal, prevIdle := c.cpuTotal, c.cpuIdle
	c.cpuTotal, c.cpuIdle = total, idle
	if prevTotal == 0 || total <= prevTotal {
		return nil
	}
	return ptr(round((1 - float64(idle-prevIdle)/float64(total-prevTotal)) * 100))
}

// meminfo is MemTotal and MemAvailable in bytes.
func meminfo(proc string) (total, avail int64) {
	data, _ := os.ReadFile(filepath.Join(proc, "meminfo"))
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
func (c *counters) net(proc string, now time.Time) (rx, tx *float64) {
	data, err := os.ReadFile(filepath.Join(proc, "net/dev"))
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
	prevRx, prevTx, prevAt := c.rx, c.tx, c.netAt
	c.rx, c.tx, c.netAt = r, t, now
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
		if rest, ok := strings.CutPrefix(p, "~"); ok && (rest == "" || rest[0] == '/') && s.m.o.Home != "" {
			path = s.m.o.Home + rest
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
		s.procTicks, s.procAt = s.readProcs(nil), s.m.o.Now()
		s.m.o.Sleep(ctx, processWarmup)
	}
	memTotal, _ := meminfo(s.m.o.Proc)
	list := []Process{}
	ticks := s.readProcs(func(pid int, comm string, rss int64, uid string) {
		list = append(list, Process{PID: pid, User: s.user(uid), Command: comm, Mem: percent(rss*pageSize, memTotal)})
	})
	now := s.m.o.Now()
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
	entries, _ := os.ReadDir(s.m.o.Proc)
	ticks := map[int]uint64{}
	for _, e := range entries {
		pid, err := strconv.Atoi(e.Name())
		if err != nil || pid <= 0 {
			continue
		}
		dir := filepath.Join(s.m.o.Proc, e.Name())
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

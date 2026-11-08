// Package procprio lowers the priority of the process it runs in, on
// every thread: the file index's crawl child runs at SCHED_IDLE with idle
// disk priority (it gets the CPU and the disk only when nothing else
// wants them), the thumbnail child at nice 10 with the lowest best-effort
// disk priority. Threads made later inherit both from the thread that
// makes them. Docs: docs/dev/features/file-search.md.
package procprio

import (
	"fmt"
	"os"
	"strconv"
	"strings"

	"golang.org/x/sys/unix"
)

// I/O priority classes and the call's "who" (linux/ioprio.h)
const (
	ClassBestEffort = 2
	ClassIdle       = 3
	whoProcess      = 1
	classShift      = 13
)

// Idle puts every thread of this process at SCHED_IDLE and in the idle
// I/O class.
func Idle() error {
	return eachThread(func(tid int) error {
		if err := unix.SchedSetAttr(tid, &unix.SchedAttr{Size: unix.SizeofSchedAttr, Policy: unix.SCHED_IDLE}, 0); err != nil {
			return fmt.Errorf("SCHED_IDLE: %w", err)
		}
		return setIOPrio(tid, ClassIdle, 0)
	})
}

// Background puts every thread of this process at nice and in the
// best-effort I/O class's lowest level (7).
func Background(nice int) error {
	return eachThread(func(tid int) error {
		if err := unix.Setpriority(unix.PRIO_PROCESS, tid, nice); err != nil {
			return fmt.Errorf("nice: %w", err)
		}
		return setIOPrio(tid, ClassBestEffort, 7)
	})
}

func setIOPrio(tid, class, level int) error {
	if _, _, errno := unix.Syscall(unix.SYS_IOPRIO_SET, whoProcess, uintptr(tid), uintptr(class<<classShift|level)); errno != 0 {
		return fmt.Errorf("ioprio_set: %w", errno)
	}
	return nil
}

// IOPrio is a thread's I/O class and level.
func IOPrio(tid int) (class, level int, err error) {
	r, _, errno := unix.Syscall(unix.SYS_IOPRIO_GET, whoProcess, uintptr(tid), 0)
	if errno != 0 {
		return 0, 0, errno
	}
	return int(r) >> classShift, int(r) & (1<<classShift - 1), nil
}

// Policy is a thread's scheduling policy, as /proc/<pid>/task/<tid>/stat
// has it (field 41: 0 normal, 5 SCHED_IDLE).
func Policy(pid, tid int) (int, error) {
	data, err := os.ReadFile(fmt.Sprintf("/proc/%d/task/%d/stat", pid, tid))
	if err != nil {
		return 0, err
	}
	// The command's name may hold spaces and parentheses: fields count
	// from after its last ')', which is field 2
	s := string(data)
	fields := strings.Fields(s[strings.LastIndexByte(s, ')')+1:])
	const policyField = 41 - 3
	if len(fields) <= policyField {
		return 0, fmt.Errorf("procprio: a short stat line")
	}
	return strconv.Atoi(fields[policyField])
}

// Threads are a process's thread ids.
func Threads(pid int) ([]int, error) {
	entries, err := os.ReadDir(fmt.Sprintf("/proc/%d/task", pid))
	if err != nil {
		return nil, err
	}
	var out []int
	for _, e := range entries {
		if tid, err := strconv.Atoi(e.Name()); err == nil {
			out = append(out, tid)
		}
	}
	return out, nil
}

// eachThread calls fn once for every thread, reading the list again until
// it finds no new one (a thread started meanwhile by one not yet lowered
// would otherwise be missed).
func eachThread(fn func(tid int) error) error {
	done := map[int]bool{}
	for {
		tids, err := Threads(os.Getpid())
		if err != nil {
			return err
		}
		fresh := false
		for _, tid := range tids {
			if done[tid] {
				continue
			}
			fresh = true
			done[tid] = true
			// A thread that ended meanwhile is fine
			if err := fn(tid); err != nil && !os.IsNotExist(err) && !strings.Contains(err.Error(), "no such process") {
				return err
			}
		}
		if !fresh {
			return nil
		}
	}
}

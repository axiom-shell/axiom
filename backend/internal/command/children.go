package command

import (
	"io"
	"os"
	"sync"
	"syscall"
	"time"
)

// Children are the commands running as this process's children (runs,
// polls, streams), handed on by a re-exec: the old image's pipes close
// with it (a later write gets SIGPIPE) and the new image wouldn't wait on
// them (a zombie), so it drains their output and reaps them (Adopt). A
// stream is stopped: the new image starts its own.
type Children struct {
	mu sync.Mutex
	m  map[int]Child
}

// Child is a running command as a re-exec hands it on.
type Child struct {
	PID int `json:"pid"`
	// The read ends of its stdout and stderr (descriptors kept across
	// the exec)
	Output []int `json:"output"`
	// A stream: sent SIGTERM before the exec, SIGKILL after stopGrace
	Stop  bool `json:"stop,omitempty"`
	files []*os.File
}

func (c *Children) add(ch Child) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.m == nil {
		c.m = map[int]Child{}
	}
	c.m[ch.PID] = ch
}

func (c *Children) remove(pid int) {
	c.mu.Lock()
	defer c.mu.Unlock()
	delete(c.m, pid)
}

// Handoff lists the running children for a re-exec, their output's
// descriptors without close-on-exec (the caller holds syscall.ForkLock,
// so no other child inherits them, and restores it if the exec fails),
// and sends each stream's group SIGTERM.
func (c *Children) Handoff() []Child {
	c.mu.Lock()
	defer c.mu.Unlock()
	var out []Child
	for _, ch := range c.m {
		ch.Output = nil
		for _, f := range ch.files {
			fd := int(f.Fd()) // -1 once closed (the run finished meanwhile)
			if fd >= 0 && clearCloseOnExec(fd) == nil {
				ch.Output = append(ch.Output, fd)
			}
		}
		if ch.Stop {
			syscall.Kill(-ch.PID, syscall.SIGTERM)
		}
		out = append(out, ch)
	}
	return out
}

// Adopt takes over a child the previous image handed on: its output is
// dropped until it closes, and it's waited on (a stream killed first).
// The goroutines end with the child, as Run's own do.
func Adopt(ch Child) {
	for _, fd := range ch.Output {
		syscall.CloseOnExec(fd)
		f := os.NewFile(uintptr(fd), "output")
		go func() {
			io.Copy(io.Discard, f)
			f.Close()
		}()
	}
	go func() {
		if ch.Stop {
			time.Sleep(stopGrace)
			syscall.Kill(-ch.PID, syscall.SIGKILL)
		}
		var ws syscall.WaitStatus
		syscall.Wait4(ch.PID, &ws, 0, nil)
	}()
}

func clearCloseOnExec(fd int) error {
	_, _, errno := syscall.Syscall(syscall.SYS_FCNTL, uintptr(fd), syscall.F_SETFD, 0)
	if errno != 0 {
		return errno
	}
	return nil
}

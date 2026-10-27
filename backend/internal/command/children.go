package command

import (
	"io"
	"os"
	"sync"
	"syscall"
	"time"
)

// Children are the commands running as this process's children (runs,
// polls, streams), handed on by a re-exec: the old image's ends of their
// pipes close with it (a later write gets SIGPIPE) and the new image
// wouldn't wait on them (a zombie), so it drains and reaps them (Adopt).
// A stream is stopped: the new image starts its own.
type Children struct {
	mu sync.Mutex
	m  map[int]Child
}

// Child is a running command as a re-exec hands it on: its pid, the read
// ends of its stdout and stderr, and whether it's a stream (sent SIGTERM
// before the exec, SIGKILL after stopGrace).
type Child struct {
	PID    int   `json:"pid"`
	Output []int `json:"output"`
	Stream bool  `json:"stream,omitempty"`
	files  []*os.File
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

// Handoff lists the running children for a re-exec and sends each
// stream's group SIGTERM. The list stays held until Resume (the exec
// failed), so no run ends meanwhile and closes a descriptor handed on.
func (c *Children) Handoff() []Child {
	c.mu.Lock()
	var out []Child
	for _, ch := range c.m {
		ch.Output = nil
		for _, f := range ch.files {
			ch.Output = append(ch.Output, int(f.Fd()))
		}
		if ch.Stream {
			syscall.Kill(-ch.PID, syscall.SIGTERM)
		}
		out = append(out, ch)
	}
	return out
}

// Resume releases the list after an exec that failed.
func (c *Children) Resume() { c.mu.Unlock() }

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
		if ch.Stream {
			time.Sleep(stopGrace)
			syscall.Kill(-ch.PID, syscall.SIGKILL)
		}
		var ws syscall.WaitStatus
		syscall.Wait4(ch.PID, &ws, 0, nil)
	}()
}

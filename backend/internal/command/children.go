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
// wouldn't wait on them (a zombie), so it drains and reaps them (Adopt),
// listing them in turn for the next re-exec.
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
			// Not f.Fd(): it would make the pipe blocking, and a close no
			// longer ends a read of it
			if rc, err := f.SyscallConn(); err == nil {
				rc.Control(func(fd uintptr) { ch.Output = append(ch.Output, int(fd)) })
			}
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

// track lists ch while it runs, copying its output to out (dropped past
// its length), and returns what waits for it: wait (its exit), then its
// output at most pipeWait more (a background child it left may hold the
// pipes for as long as it lives).
func (c *Children) track(ch Child, wait func(), out ...io.Writer) func() {
	copied := make(chan struct{}, len(ch.files))
	for i, f := range ch.files {
		w := io.Discard
		if i < len(out) {
			w = out[i]
		}
		go func() {
			io.Copy(w, f)
			copied <- struct{}{}
		}()
	}
	c.add(ch)
	closeAll := func() {
		for _, f := range ch.files {
			f.Close()
		}
	}
	return func() {
		wait()
		// Before its pipes close: a handoff holding the list keeps them
		c.remove(ch.PID)
		timeout := time.After(pipeWait)
		for range ch.files {
			select {
			case <-copied:
			case <-timeout:
				closeAll() // ends the copies
				<-copied
			}
		}
		closeAll()
	}
}

// Adopt takes over a child the previous image handed on, as its own
// until it exits (handed on again by the next re-exec): its output
// dropped, waited on, a stream killed first after stopGrace.
func (c *Children) Adopt(ch Child) {
	for _, fd := range ch.Output {
		syscall.CloseOnExec(fd)
		ch.files = append(ch.files, os.NewFile(uintptr(fd), "output"))
	}
	wait := c.track(ch, func() {
		if ch.Stream {
			time.Sleep(stopGrace)
			syscall.Kill(-ch.PID, syscall.SIGKILL)
		}
		var ws syscall.WaitStatus
		syscall.Wait4(ch.PID, &ws, 0, nil)
	})
	go wait()
}

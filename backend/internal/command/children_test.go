package command

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"syscall"
	"testing"
	"time"
)

// A running command is listed for a re-exec with its output's
// descriptors, and dropped once it's done.
func TestChildrenHandoff(t *testing.T) {
	t.Parallel()
	var children Children
	done := make(chan Result, 1)
	go func() {
		res, _ := Run(context.Background(), Options{Children: &children}, []string{"sh", "-c", "sleep 0.3; echo hi"}, nil)
		done <- res
	}()
	var listed []Child
	for deadline := time.Now().Add(5 * time.Second); len(listed) == 0; time.Sleep(10 * time.Millisecond) {
		if time.Now().After(deadline) {
			t.Fatal("the run isn't listed")
		}
		children.mu.Lock()
		n := len(children.m)
		children.mu.Unlock()
		if n > 0 {
			listed = children.Handoff()
			children.Resume()
		}
	}
	if len(listed) != 1 || len(listed[0].Output) != 2 || listed[0].Stream {
		t.Fatalf("listed %+v", listed)
	}
	if res := <-done; res.Stdout != "hi\n" {
		t.Errorf("the run after a handoff that didn't exec: %+v", res)
	}
	if len(children.m) != 0 {
		t.Errorf("left %+v", children.m)
	}
}

// An adopted child keeps writing after the old image's end of its pipe
// closed (no SIGPIPE), is listed for the next re-exec, and is reaped (no
// zombie).
func TestAdopt(t *testing.T) {
	t.Parallel()
	marker := filepath.Join(t.TempDir(), "done")
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command("sh", "-c", "sleep 0.2; head -c 200000 /dev/zero; echo ok > "+marker)
	cmd.Stdout = w
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	w.Close()
	fd, err := syscall.Dup(int(r.Fd()))
	if err != nil {
		t.Fatal(err)
	}
	r.Close() // the old image's end
	var children Children
	children.Adopt(Child{PID: cmd.Process.Pid, Output: []int{fd}})
	// Listed in turn for the next re-exec
	if listed := children.Handoff(); len(listed) != 1 || len(listed[0].Output) != 1 {
		t.Errorf("listed %+v", listed)
	}
	children.Resume()
	pid := strconv.Itoa(cmd.Process.Pid)
	for deadline := time.Now().Add(5 * time.Second); ; time.Sleep(20 * time.Millisecond) {
		if _, err := os.Stat("/proc/" + pid); err != nil {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("not reaped")
		}
	}
	if _, err := os.Stat(marker); err != nil {
		t.Error("the child didn't finish:", err)
	}
}

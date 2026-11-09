package procprio

import (
	"os"
	"os/exec"
	"testing"
)

const childEnv = "AXIOM_PROCPRIO_CHILD"

// The child lowers itself and reports by its exit code; the parent reads
// its threads before it exits, so the test never lowers itself
func TestMain(m *testing.M) {
	switch os.Getenv(childEnv) {
	case "idle":
		if err := Idle(); err != nil {
			os.Stderr.WriteString(err.Error())
			os.Exit(2)
		}
		os.Stdout.WriteString("ready\n")
		os.Stdin.Read(make([]byte, 1))
		os.Exit(0)
	case "background", "nicer":
		// A process already nicer stays so, without failing
		if os.Getenv(childEnv) == "nicer" && Background(15) != nil {
			os.Exit(2)
		}
		if err := Background(10); err != nil {
			os.Stderr.WriteString(err.Error())
			os.Exit(2)
		}
		os.Stdout.WriteString("ready\n")
		os.Stdin.Read(make([]byte, 1))
		os.Exit(0)
	}
	os.Exit(m.Run())
}

func TestLowersEveryThread(t *testing.T) {
	t.Parallel()
	for _, c := range []struct {
		mode   string
		policy int
		class  int
		level  int
	}{
		{"idle", 5, ClassIdle, 0},
		{"background", 0, ClassBestEffort, 7},
		{"nicer", 0, ClassBestEffort, 7},
	} {
		t.Run(c.mode, func(t *testing.T) {
			t.Parallel()
			cmd := exec.Command(os.Args[0])
			cmd.Env = append(os.Environ(), childEnv+"="+c.mode)
			stdin, _ := cmd.StdinPipe()
			stdout, _ := cmd.StdoutPipe()
			if err := cmd.Start(); err != nil {
				t.Fatal(err)
			}
			defer cmd.Wait()
			defer stdin.Close()
			if _, err := stdout.Read(make([]byte, 6)); err != nil {
				t.Fatalf("the child: %v", err)
			}
			tids, err := Threads(cmd.Process.Pid)
			if err != nil || len(tids) < 2 {
				t.Fatalf("threads %v %v", tids, err)
			}
			for _, tid := range tids {
				if p, err := Policy(cmd.Process.Pid, tid); err != nil || p != c.policy {
					t.Errorf("thread %d: policy %d %v", tid, p, err)
				}
				if class, level, err := IOPrio(tid); err != nil || class != c.class || level != c.level {
					t.Errorf("thread %d: ioprio %d/%d %v", tid, class, level, err)
				}
			}
		})
	}
}

package testkit

import (
	"os"
	"strconv"
	"sync"
	"time"
)

// waitFactor is AXIOM_TEST_WAIT_FACTOR (a number above 0, default 1):
// CI's go job sets it, as a loaded runner can be slower than any bound
// tuned on a quiet machine.
var waitFactor = sync.OnceValue(func() float64 {
	if f, err := strconv.ParseFloat(os.Getenv("AXIOM_TEST_WAIT_FACTOR"), 64); err == nil && f > 0 {
		return f
	}
	return 1
})

// Bound is d stretched by AXIOM_TEST_WAIT_FACTOR: the longest a test waits
// for something that should happen. A wait that something doesn't happen
// stays short and unstretched.
func Bound(d time.Duration) time.Duration {
	return time.Duration(float64(d) * waitFactor())
}

// Eventually polls cond every 10 ms and reports whether it held within
// Bound(10 s). The bound is long because only a failing test reaches it.
func Eventually(cond func() bool) bool {
	deadline := time.Now().Add(Bound(10 * time.Second))
	for {
		if cond() {
			return true
		}
		if time.Now().After(deadline) {
			return false
		}
		time.Sleep(10 * time.Millisecond)
	}
}

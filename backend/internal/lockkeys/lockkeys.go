// Package lockkeys is the `lockKeys` topic: whether Caps Lock, Num Lock
// and Scroll Lock are on, read from the keyboards' LEDs in sysfs
// (/sys/class/leds/input*::capslock and the like). No compositor reports
// the locked modifiers over its IPC on all three backends, but each keeps
// its keyboards' LEDs in step with them, and every user may read those.
// sysfs LED files can't be watched (no inotify, no uevent on a change),
// so the topic polls them, only while the shell subscribes.
package lockkeys

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strconv"
	"strings"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/topics"
)

// Options configure the source; the zero Root is /sys/class/leds.
type Options struct {
	Root string
}

// State is what the topic pushes. A key is on while any keyboard's LED
// for it is; Available is false where no keyboard has a Caps Lock LED (a
// VM, a remote session), so the shell shows nothing rather than "off".
type State struct {
	Available bool `json:"available"`
	Caps      bool `json:"caps"`
	Num       bool `json:"num"`
	Scroll    bool `json:"scroll"`
}

// Source is the `lockKeys` topic.
func Source(o Options) topics.Source {
	if o.Root == "" {
		o.Root = "/sys/class/leds"
	}
	return topics.Source{
		Name: "lockKeys",
		// A key toggled shows within a blink; anything faster is wasted
		Floor:   100 * time.Millisecond,
		Default: 150 * time.Millisecond,
		Request: reflect.TypeFor[struct{}](),
		State:   reflect.TypeFor[State](),
		Fetch: func(context.Context, []json.RawMessage) (any, error) {
			return Read(o.Root), nil
		},
	}
}

// Read reads the LEDs under root.
func Read(root string) State {
	caps, found := lit(root, "capslock")
	num, _ := lit(root, "numlock")
	scroll, _ := lit(root, "scrolllock")
	return State{Available: found, Caps: caps, Num: num, Scroll: scroll}
}

// lit reports whether any `<device>::<name>` LED under root is lit, and
// whether there is one at all. An unreadable or garbled brightness counts
// as off.
func lit(root, name string) (on, found bool) {
	dirs, _ := filepath.Glob(filepath.Join(root, "*::"+name))
	for _, dir := range dirs {
		found = true
		b, err := os.ReadFile(filepath.Join(dir, "brightness"))
		if err != nil {
			continue
		}
		if n, err := strconv.Atoi(strings.TrimSpace(string(b))); err == nil && n > 0 {
			return true, true
		}
	}
	return false, found
}

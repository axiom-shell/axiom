package daemon

import (
	"context"
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"sync"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/xkb"
)

// inputPart: the xkb registry (package xkb), for the input sources' layout
// picker and the full layout names niri and sway report
// (KeyboardLayoutManager.registry).
func (d *Daemon) inputPart() part {
	return part{name: "input", methods: d.inputMethods}
}

// xkbRules is the registry under the xkb data root
const xkbRules = "rules/evdev.xml"

func (d *Daemon) inputMethods(reg *rpc.Registry) {
	// Read once: the file changes only with a package update
	var (
		mu     sync.Mutex
		cached *xkb.Registry
	)
	rpc.Handle(reg, "input.layouts", func(ctx context.Context, c *rpc.Conn, _ struct{}) (xkb.Registry, error) {
		mu.Lock()
		defer mu.Unlock()
		if cached != nil {
			return *cached, nil
		}
		r, err := readXkbRegistry(xkbRoot(d.opts.Getenv))
		if err != nil {
			return xkb.Registry{}, err
		}
		cached = &r
		return r, nil
	})
}

// xkbRoot is where xkb's data is: $XKB_CONFIG_ROOT, as libxkbcommon
// reads it, else the usual place
func xkbRoot(getenv func(string) string) string {
	if root := getenv("XKB_CONFIG_ROOT"); root != "" {
		return root
	}
	return "/usr/share/X11/xkb"
}

func readXkbRegistry(root string) (xkb.Registry, error) {
	f, err := os.Open(filepath.Join(root, xkbRules))
	if errors.Is(err, fs.ErrNotExist) {
		return xkb.Registry{}, axerr.Wrap(axerr.Unavailable, err, "no xkb registry (xkeyboard-config isn't installed)")
	}
	if err != nil {
		return xkb.Registry{}, axerr.Wrap(axerr.Failed, err, "reading the xkb registry")
	}
	defer f.Close()
	r, err := xkb.Parse(f)
	if err != nil {
		return xkb.Registry{}, axerr.Wrap(axerr.Failed, err, "reading the xkb registry")
	}
	return r, nil
}

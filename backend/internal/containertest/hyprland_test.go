//go:build container

package containertest

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

// HY1 (docs/dev/hyprland/config-modes.md): does hl.on("hyprland.start", …)
// run again on `hyprctl reload`? The answer decides whether a start line
// inside the handler counts as one that a reload re-runs
// (manager.hyprStartHandlerFiresOnReload). The config appends a tag to a
// file in the handler and at its top level; the counts are logged.
//
// It skips here: Hyprland's Wayland backend needs xdg_wm_base 6, which sway
// 1.12 lacks, and, nested in niri, zwp_linux_dmabuf_v1 version 4, which
// niri's doesn't offer (CBackend::create() failed both times). The answer
// was found by one run of scripts/dev/nested.sh hyprland --managed on the
// host (docs/dev/hyprland/config-modes.md › HY1).
func TestContainerHyprlandStartHandlerOnReload(t *testing.T) {
	s := NewSession(t)
	s.StartSway("")
	counts := filepath.Join(s.Home, "counts")
	s.StartHyprlandNested(fmt.Sprintf(`local function note(tag)
  local f = io.open(%q, "a")
  f:write(tag, "\n")
  f:close()
end
note("toplevel")
hl.on("hyprland.start", function() note("start") end)
`, counts))
	count := func(tag string) int {
		data, _ := os.ReadFile(counts)
		n := 0
		for _, line := range strings.Split(string(data), "\n") {
			if line == tag {
				n++
			}
		}
		return n
	}
	if !testkit.Eventually(func() bool { return count("toplevel") > 0 }) {
		t.Skipf("Hyprland never ran the Lua config (an older one?); log tail:\n%s", s.Tail("hyprland.log", 20))
	}
	// the start event comes once the compositor is up
	testkit.Eventually(func() bool { return count("start") > 0 })
	beforeTop, beforeStart := count("toplevel"), count("start")
	s.Hyprctl("reload")
	time.Sleep(testkit.Bound(time.Second))
	t.Logf("HY1: before the reload: toplevel %d, start %d; after: toplevel %d, start %d",
		beforeTop, beforeStart, count("toplevel"), count("start"))
	if count("toplevel") <= beforeTop {
		t.Fatal("the reload didn't run the config again")
	}
	t.Logf("HY1 RESULT: hyprland.start handler fires on reload = %v", count("start") > beforeStart)
}

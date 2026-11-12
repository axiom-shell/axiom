//go:build container

package containertest

import (
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

const portalSeed = "[preferred]\ndefault=gtk\norg.freedesktop.impl.portal.ScreenCast=gnome\n"

// The niri portal line is a session effect: added while ScreenSharing is on,
// taken out (the file as it was) when axiom stops, however it stops. It runs
// against the real xdg-desktop-portal, which axiom restarts (its pid
// changes) when the file changes.
func TestContainerNiriPortalLineIsASessionEffect(t *testing.T) {
	s := NewSessionWith(t, "XDG_CURRENT_DESKTOP=niri")
	s.StartSway("")
	s.StartNiriNested("\n")
	// What runs in niri doesn't see the sway around it
	delete(s.vars, "SWAYSOCK")
	conf := s.WriteFile(".config/xdg-desktop-portal/niri-portals.conf", portalSeed)
	desc, err := os.ReadFile(filepath.Join(os.Getenv("AXIOM_SRC"), "data", "portal", "axiom.portal"))
	if err != nil {
		t.Fatal(err)
	}
	s.WriteFile(".local/share/xdg-desktop-portal/portals/axiom.portal", string(desc))
	pid0, err := s.PingPortal()
	if err != nil {
		t.Skipf("xdg-desktop-portal doesn't start here: %v", err)
	}
	read := func() string { data, _ := os.ReadFile(conf); return string(data) }
	hasLine := func() bool { return strings.Contains(read(), "org.freedesktop.impl.portal.ScreenCast=axiom") }
	// the portal was restarted: another pid answers
	restarted := func(old int) func() bool {
		return func() bool { pid, err := s.PingPortal(); return err == nil && pid != old }
	}

	p := s.StartAxiom("niri")
	// control: with sharing off the file and the portal are left alone
	if raw, err := s.ShellCall("screenshare.portalLine", map[string]any{}); err != nil || !strings.Contains(string(raw), `"off"`) {
		t.Fatalf("portalLine = %s, %v", raw, err)
	}
	if read() != portalSeed {
		t.Fatalf("the file changed with sharing off:\n%s", read())
	}
	if pid, err := s.PingPortal(); err != nil || pid != pid0 {
		t.Fatalf("the portal changed with sharing off: %d (was %d), %v", pid, pid0, err)
	}
	s.Axiom("config", "set", "ScreenSharing.enabled", "true")
	if !testkit.Eventually(hasLine) {
		t.Fatalf("no line after enabling; file:\n%s\ndaemon log:\n%s", read(), s.Tail(daemonLog, 20))
	}
	if got := read(); !strings.Contains(got, "# axiom: org.freedesktop.impl.portal.ScreenCast=gnome") {
		t.Fatalf("the gnome line wasn't commented out:\n%s", got)
	}
	if !testkit.Eventually(restarted(pid0)) {
		t.Fatal("the portal wasn't restarted after the line went in")
	}
	pid1, _ := s.PingPortal()

	// a clean quit: the file is as it was
	stopAxiom(t, p)
	if got := read(); got != portalSeed {
		t.Fatalf("after quit:\n%s", got)
	}
	if !testkit.Eventually(restarted(pid1)) {
		t.Fatal("the portal wasn't restarted after the line came out")
	}

	// kill -9: the guard restores it
	p = s.StartAxiom("niri")
	if !testkit.Eventually(hasLine) {
		t.Fatalf("no line after the restart; daemon log:\n%s", s.Tail(daemonLog, 20))
	}
	guard := s.Guard()
	p.Signal(syscall.SIGKILL)
	p.Wait()
	if !testkit.Eventually(func() bool { return read() == portalSeed }) {
		t.Fatalf("the guard didn't restore the file:\n%s\nguard log:\n%s", read(), s.GuardLog())
	}

	// the guard restarts the portal after the file: let it finish
	if !WaitGone(guard) {
		t.Fatal("the guard is still running")
	}

	// a link (dotfiles): never touched, the state says so
	target := s.WriteFile("dotfiles/niri-portals.conf", portalSeed)
	os.Remove(conf)
	if err := os.Symlink(target, conf); err != nil {
		t.Fatal(err)
	}
	pidL, _ := s.PingPortal()
	p = s.StartAxiom("niri")
	raw, err := s.ShellCall("screenshare.portalLine", map[string]any{})
	if err != nil || !strings.Contains(string(raw), `"link"`) {
		t.Fatalf("portalLine = %s, %v", raw, err)
	}
	stopAxiom(t, p)
	if info, err := os.Lstat(conf); err != nil || info.Mode()&os.ModeSymlink == 0 {
		t.Fatalf("the link was replaced: %v %v", info, err)
	}
	if pid, err := s.PingPortal(); err != nil || pid != pidL {
		t.Fatalf("the portal was restarted for a link: %d (was %d), %v", pid, pidL, err)
	}
	if data, _ := os.ReadFile(target); string(data) != portalSeed {
		t.Fatalf("the link's target changed:\n%s", data)
	}
}

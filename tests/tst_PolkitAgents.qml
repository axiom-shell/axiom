import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "PolkitAgents"

  function test_processPattern() {
    const pattern = new RegExp(PolkitAgents.processPattern);
    verify(pattern.test("/usr/lib/hyprpolkitagent/hyprpolkitagent"));
    verify(pattern.test("/usr/lib/polkit-kde-authentication-agent-1 --flag"));
    verify(pattern.test("soteria"));
    verify(!pattern.test("/usr/lib/polkit-1/polkitd --no-debug"), "polkitd itself isn't an agent");
    verify(!pattern.test("vim hyprpolkitagent.conf"));
    verify(!pattern.test("vim /tmp/soteria"), "an argument naming an agent isn't one");
    verify(!pattern.test("sh -c /usr/bin/lxpolkit"), "nor is a shell running one");
  }

  function test_units() {
    verify(PolkitAgents.units.includes("hyprpolkitagent.service"));
    verify(!PolkitAgents.units.includes(""));
  }
}

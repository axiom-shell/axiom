import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "CompositorKind"

  function test_kind() {
    compare(CompositorKind.kind({}), "");
    compare(CompositorKind.kind({
      "SWAYSOCK": "/run/user/1000/sway-ipc.1000.130759.sock"
    }), "sway");
    compare(CompositorKind.kind({
      "HYPRLAND_INSTANCE_SIGNATURE": "",
      "NIRI_SOCKET": "/run/user/1000/niri.wayland-1.244518.sock"
    }), "niri", "an empty variable is unset");
  }

  function test_sessionKey() {
    const env = {
      "HYPRLAND_INSTANCE_SIGNATURE": "abc_1_2",
      "SWAYSOCK": "/run/user/1000/sway-ipc.1000.130759.sock"
    };
    compare(CompositorKind.sessionKey(env, "hyprland"), "abc_1_2");
    compare(CompositorKind.sessionKey(env, "sway"), "/run/user/1000/sway-ipc.1000.130759.sock");
    compare(CompositorKind.sessionKey(env, "niri"), "", "not set");
    compare(CompositorKind.sessionKey(env, ""), "", "no compositor");
  }
}

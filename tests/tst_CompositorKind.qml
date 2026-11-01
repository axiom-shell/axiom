import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "CompositorKind"

  readonly property var env: ({
      "SWAYSOCK": "/run/user/1000/sway-ipc.1000.130759.sock",
      "NIRI_SOCKET": "/run/user/1000/niri.wayland-1.244518.sock",
      "XDG_RUNTIME_DIR": "/run/user/1000"
    })

  function test_candidates() {
    compare(CompositorKind.candidates({}), []);
    compare(CompositorKind.candidates(env), [
      {
        "kind": "sway",
        "pid": "130759",
        "lockFile": ""
      },
      {
        "kind": "niri",
        "pid": "244518",
        "lockFile": ""
      }
    ], "pids from the socket names");
    compare(CompositorKind.candidates({
      "HYPRLAND_INSTANCE_SIGNATURE": "abc_1_2",
      "XDG_RUNTIME_DIR": "/run/user/1000"
    }), [
      {
        "kind": "hyprland",
        "pid": "",
        "lockFile": "/run/user/1000/hypr/abc_1_2/hyprland.lock"
      }
    ]);
    compare(CompositorKind.candidates({
      "NIRI_SOCKET": "/tmp/odd-name"
    })[0].pid, "", "a socket name without a pid");
  }

  function test_pick() {
    let asked = 0;
    compare(CompositorKind.pick([], () => true), "");
    compare(CompositorKind.pick([
      {
        "kind": "sway"
      }
    ], () => {
      asked++;
      return false;
    }), "sway", "the only one, even if not running");
    compare(asked, 0, "nothing asked with one candidate");
    const both = CompositorKind.candidates(env);
    compare(CompositorKind.pick(both, c => c.kind === "niri"), "niri", "a stale SWAYSOCK loses to the running niri");
    compare(CompositorKind.pick(both, () => true), "sway", "both running: the first");
    compare(CompositorKind.pick(both, () => false), "sway", "none running: the first");
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

  function test_lockPid() {
    compare(CompositorKind.lockPid("1234\nwayland-1\n"), "1234");
    compare(CompositorKind.lockPid(null), "");
    compare(CompositorKind.lockPid("garbage"), "");
  }

  function test_isProcess() {
    verify(CompositorKind.isProcess("niri", "niri\n"));
    verify(CompositorKind.isProcess("hyprland", "Hyprland\n"));
    verify(!CompositorKind.isProcess("sway", null), "gone");
    verify(!CompositorKind.isProcess("sway", "bash\n"), "a reused pid");
  }
}

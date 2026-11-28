import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "OutputWindows"

  function out(active, specialId, specialName) {
    const o = {
      "activeWorkspaceId": active,
      "specialWorkspaceId": specialId
    };
    if (specialName !== undefined)
      o.specialWorkspaceName = specialName;
    return o;
  }

  function win(id, name, fullscreen, maximized) {
    return {
      "workspaceId": id,
      "workspaceName": name,
      "fullscreen": fullscreen === true,
      "maximized": maximized === true
    };
  }

  function test_hypr057_special() {
    const w = win(-1, "special:gaming", true);
    const o = out(5, 0, "special:gaming");
    compare(OutputWindows.hasFullscreen(o, [w]), true);
    compare(OutputWindows.shown(o, [w]).length, 1, "the window shows");
  }

  function test_special_closed() {
    compare(OutputWindows.hasFullscreen(out(5, 0, ""), [win(-1, "special:gaming", true)]), false);
  }

  function test_no_active_workspace() {
    compare(OutputWindows.shown(out(-1, 0, ""), [win(-1, "special:gaming", true)]).length, 0);
  }

  function test_regular_under_special() {
    compare(OutputWindows.hasFullscreen(out(5, 0, "special:gaming"), [win(5, "5", true)]), true);
  }

  function test_other_special() {
    compare(OutputWindows.hasFullscreen(out(5, 0, "special:gaming"), [win(-1, "special:magic", true)]), false);
  }

  function test_id_fallback() {
    compare(OutputWindows.hasFullscreen(out(5, -98), [win(-98, "", true)]), true);
  }

  function test_maximized_only() {
    compare(OutputWindows.hasFullscreen(out(5, 0, ""), [win(5, "5", false, true)]), false);
  }

  function test_sway_niri_shape() {
    const o = out(2, 0);
    compare(OutputWindows.hasFullscreen(o, [win(3, "3", true)]), false, "other workspace");
    compare(OutputWindows.hasFullscreen(o, [win(2, "2", true)]), true, "active workspace");
  }

  function test_null_output() {
    compare(OutputWindows.shown(null, [win(5, "5", true)]), []);
    compare(OutputWindows.hasFullscreen(null, [win(5, "5", true)]), false);
  }

  function test_workspace_key() {
    compare(OutputWindows.workspaceKey(out(5, 0, "special:gaming")), "5/special:gaming");
    compare(OutputWindows.workspaceKey(out(5, 0, "")), "5/0");
  }
}

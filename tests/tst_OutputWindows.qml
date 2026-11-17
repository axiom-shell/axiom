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

  function test_hypr057Special() {
    const w = win(-1, "special:gaming", true);
    const o = out(5, 0, "special:gaming");
    compare(OutputWindows.hasFullscreen(o, [w]), true);
    compare(OutputWindows.shown(o, [w]).length, 1, "the window shows");
  }

  function test_specialClosed() {
    compare(OutputWindows.hasFullscreen(out(5, 0, ""), [win(-1, "special:gaming", true)]), false);
  }

  function test_noActiveWorkspace() {
    compare(OutputWindows.shown(out(-1, 0, ""), [win(-1, "special:gaming", true)]).length, 0);
  }

  function test_regularUnderSpecial() {
    compare(OutputWindows.hasFullscreen(out(5, 0, "special:gaming"), [win(5, "5", true)]), true);
  }

  function test_otherSpecial() {
    compare(OutputWindows.hasFullscreen(out(5, 0, "special:gaming"), [win(-1, "special:magic", true)]), false);
  }

  function test_idFallback() {
    compare(OutputWindows.hasFullscreen(out(5, -98), [win(-98, "", true)]), true);
  }

  function test_maximizedOnly() {
    compare(OutputWindows.hasFullscreen(out(5, 0, ""), [win(5, "5", false, true)]), false);
  }

  function test_swayNiriShape() {
    const o = out(2, 0);
    compare(OutputWindows.hasFullscreen(o, [win(3, "3", true)]), false, "other workspace");
    compare(OutputWindows.hasFullscreen(o, [win(2, "2", true)]), true, "active workspace");
  }

  function test_nullOutput() {
    compare(OutputWindows.shown(null, [win(5, "5", true)]), []);
    compare(OutputWindows.hasFullscreen(null, [win(5, "5", true)]), false);
  }

  function test_workspaceKey() {
    compare(OutputWindows.workspaceKey(out(5, 0, "special:gaming")), "5/special:gaming");
    compare(OutputWindows.workspaceKey(out(5, 0, "")), "5/0");
  }
}

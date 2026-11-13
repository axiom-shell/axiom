import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "UpdatesLook"

  function test_settledFailureShows() {
    verify(UpdatesLook.settledFailed(false, true, false));
    verify(!UpdatesLook.settledFailed(true, false, false));
  }

  function test_flipWhileCheckingKeepsLook() {
    verify(!UpdatesLook.settledFailed(false, true, true), "ok look kept");
    verify(UpdatesLook.settledFailed(true, false, true), "failed look kept");
  }
}

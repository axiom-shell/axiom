import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "DetachedNudge"

  readonly property var due: ({
      "mode": "detached",
      "supported": true,
      "onboardingShown": false,
      "greeter": false,
      "nudged": false,
      "firstRunPending": false
    })

  function with_(key, value) {
    return Object.assign({}, due, {
      [key]: value
    });
  }

  function test_due() {
    verify(DetachedNudge.shouldNudge(due));
  }

  function test_only_detached() {
    verify(!DetachedNudge.shouldNudge(with_("mode", "included")));
    verify(!DetachedNudge.shouldNudge(with_("mode", "managed")));
  }

  function test_needs_a_supported_compositor() {
    verify(!DetachedNudge.shouldNudge(with_("supported", false)));
    verify(!DetachedNudge.shouldNudge(with_("supported", undefined)));
  }

  function test_not_while_the_onboarder_shows() {
    verify(!DetachedNudge.shouldNudge(with_("onboardingShown", true)));
  }

  function test_not_on_the_greeter() {
    verify(!DetachedNudge.shouldNudge(with_("greeter", true)));
  }

  function test_not_before_a_first_runs_onboarder_has_closed() {
    verify(!DetachedNudge.shouldNudge(with_("firstRunPending", true)));
  }

  function test_only_once_per_launch() {
    verify(!DetachedNudge.shouldNudge(with_("nudged", true)));
  }
}

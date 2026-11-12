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
      "nudged": false
    })

  function with_(key, value) {
    return Object.assign({}, due, {
      [key]: value
    });
  }

  function test_due() {
    verify(DetachedNudge.shouldNudge(due));
  }

  function test_onlyDetached() {
    verify(!DetachedNudge.shouldNudge(with_("mode", "included")));
    verify(!DetachedNudge.shouldNudge(with_("mode", "managed")));
  }

  function test_needsASupportedCompositor() {
    verify(!DetachedNudge.shouldNudge(with_("supported", false)));
    verify(!DetachedNudge.shouldNudge(with_("supported", undefined)));
  }

  function test_notWhileTheOnboarderShows() {
    verify(!DetachedNudge.shouldNudge(with_("onboardingShown", true)));
  }

  function test_notOnTheGreeter() {
    verify(!DetachedNudge.shouldNudge(with_("greeter", true)));
  }

  function test_onlyOncePerLaunch() {
    verify(!DetachedNudge.shouldNudge(with_("nudged", true)));
  }
}

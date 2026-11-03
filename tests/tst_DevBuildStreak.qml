import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "DevBuildStreak"

  readonly property var failing: ({
      "failing": true,
      "failedAt": "2026-11-04T10:00:00.123456789+01:00"
    })

  // Only a streak's first failure notifies; a later one moves its time on
  function test_failures() {
    compare(DevBuildStreak.next(null, null, ""), {
      "notify": "",
      "streak": DevBuildStreak.clear
    }, "nothing built: nothing");
    compare(DevBuildStreak.next(null, {
      "ok": false,
      "at": "2026-11-04T10:00:00.123456789+01:00"
    }, ""), {
      "notify": "failed",
      "streak": failing
    });
    compare(DevBuildStreak.next(failing, {
      "ok": false,
      "at": "2026-11-04T10:00:00.123456789+01:00"
    }, ""), {
      "notify": "",
      "streak": failing
    }, "the same failure again: nothing");
    compare(DevBuildStreak.next(failing, {
      "ok": false,
      "at": "2026-11-04T10:05:00+01:00"
    }, ""), {
      "notify": "",
      "streak": {
        "failing": true,
        "failedAt": "2026-11-04T10:05:00+01:00"
      }
    }, "a second failure: no notification");
  }

  // The streak ends on the next success, this image's or the recorded one
  function test_success() {
    compare(DevBuildStreak.next(failing, {
      "ok": true,
      "at": "2026-11-04T10:06:00+01:00"
    }, ""), {
      "notify": "works",
      "streak": DevBuildStreak.clear
    });
    compare(DevBuildStreak.next(failing, null, "2026-11-04T10:06:00.5+01:00"), {
      "notify": "works",
      "streak": DevBuildStreak.clear
    }, "after the re-exec: the recorded build");
    compare(DevBuildStreak.next(failing, null, "2026-11-04T09:00:00+01:00"), {
      "notify": "",
      "streak": failing
    }, "a recorded build older than the failure: still failing");
    compare(DevBuildStreak.next(failing, null, ""), {
      "notify": "",
      "streak": failing
    }, "nothing recorded: still failing");
    compare(DevBuildStreak.next(null, {
      "ok": true,
      "at": "2026-11-04T10:06:00+01:00"
    }, ""), {
      "notify": "",
      "streak": DevBuildStreak.clear
    }, "a success with nothing failing: nothing");
  }
}

pragma Singleton
import QtQuick

/**
 * Which dev build notification to send (DevManager): only the first failure
 * of a failing streak, then one "works again" the next time a build
 * succeeds. The streak is `{ failing, failedAt }` (the latest failure's
 * time), kept by the caller across restarts: a successful build re-execs
 * axiom into the dev image, whose `lastBuild` starts empty, so a success
 * may only show as the build recorded for the dev tree (dev.state's
 * `build.at`), newer than the failure.
 */
QtObject {
  id: root

  // The streak with nothing failing
  readonly property var clear: ({
      "failing": false,
      "failedAt": ""
    })

  // A Go time (RFC 3339, up to nanoseconds) as ms, NaN when there is none:
  // the JS engine reads at most milliseconds
  function _time(at) {
    return at ? Date.parse(String(at).replace(/(\.\d{3})\d+/, "$1")) : NaN;
  }

  // { notify: "" | "failed" | "works", streak }: `streak` the saved one (or
  // null), `lastBuild` this image's { ok, at } (or null), `recordedAt` the
  // dev tree's recorded build's time (or "")
  function next(streak, lastBuild, recordedAt) {
    const failing = streak?.failing === true;
    const failedAt = failing ? String(streak.failedAt ?? "") : "";
    const now = {
      "failing": failing,
      "failedAt": failedAt
    };
    if (lastBuild && lastBuild.ok === false) {
      if (String(lastBuild.at) === failedAt)
        return {
          "notify": "",
          "streak": now
        };
      return {
        "notify": failing ? "" : "failed",
        "streak": {
          "failing": true,
          "failedAt": String(lastBuild.at)
        }
      };
    }
    if (!failing)
      return {
        "notify": "",
        "streak": root.clear
      };
    const builtAt = lastBuild?.ok === true ? lastBuild.at : recordedAt;
    const failed = root._time(failedAt);
    // A success newer than the failure ends the streak (an unreadable
    // failure time: any success does)
    if (builtAt && (isNaN(failed) || root._time(builtAt) > failed))
      return {
        "notify": "works",
        "streak": root.clear
      };
    return {
      "notify": "",
      "streak": now
    };
  }
}

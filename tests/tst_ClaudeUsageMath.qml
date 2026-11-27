import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "ClaudeUsageMath"

  readonly property var low: ({
      "label": "low",
      "status": "ok",
      "session": {
        "percent": 20
      },
      "weekly": {
        "percent": 80
      }
    })
  readonly property var high: ({
      "label": "high",
      "status": "ok",
      "session": {
        "percent": 60
      },
      "weekly": {
        "percent": 10
      }
    })
  readonly property var pending: ({
      "label": "pending",
      "status": "pending"
    })

  function test_percent_of() {
    compare(ClaudeUsageMath.percentOf(low, "session"), 20, "session is the default metric");
    compare(ClaudeUsageMath.percentOf(low, "weekly"), 80, "weekly reads the weekly limit");
    compare(ClaudeUsageMath.percentOf(pending, "session"), -1, "a pending row has no percent");
    compare(ClaudeUsageMath.percentOf(null, "session"), -1, "no row has no percent");
  }

  function test_fullest() {
    compare(ClaudeUsageMath.fullest([low, high], "session").label, "high", "the highest session percent");
    compare(ClaudeUsageMath.fullest([low, high], "weekly").label, "low", "the weekly metric picks by weekly");
    compare(ClaudeUsageMath.fullest([pending, low], "session").label, "low", "a -1 pending row loses");
    compare(ClaudeUsageMath.fullest([low, pending], "session").label, "low", "and loses in any position");
    compare(ClaudeUsageMath.fullest([], "session"), null, "no rows: none");
  }
}

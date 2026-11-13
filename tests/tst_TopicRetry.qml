import QtQuick
import QtTest
import qs.components.methods

// Which topic answers are asked again (TopicRetry)
TestCase {
  name: "TopicRetry"

  function test_answered_resets() {
    compare(TopicRetry.decide(null, 3, 5), {
      "action": "done",
      "attempts": 0
    });
  }

  function test_busy_is_retried_and_counted() {
    compare(TopicRetry.decide({
      "kind": "busy"
    }, 0, 5), {
      "action": "retry",
      "attempts": 1
    });
    compare(TopicRetry.decide({
      "kind": "busy"
    }, 4, 5).action, "retry");
  }

  function test_busy_gives_up_at_the_cap() {
    compare(TopicRetry.decide({
      "kind": "busy"
    }, 5, 5), {
      "action": "giveUp",
      "attempts": 0
    });
  }

  function test_other_errors_are_not_retried() {
    for (const kind of ["bad_request", "not_found", "internal"])
      compare(TopicRetry.decide({
        "kind": kind
      }, 1, 5).action, "warn", kind);
  }

  function test_unavailable_is_left_alone() {
    compare(TopicRetry.decide({
      "kind": "unavailable"
    }, 2, 5), {
      "action": "ignore",
      "attempts": 2
    });
  }
}

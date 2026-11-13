import QtQuick
import QtTest
import qs.components.methods

// What a polled topic is asked for (TopicRequest)
TestCase {
  name: "TopicRequest"

  function req(interval, metrics, extra) {
    return Object.assign({
      "interval": interval,
      "metrics": metrics ?? [],
      "diskPaths": [],
      "history": false
    }, extra ?? {});
  }

  function test_no_requests_is_null() {
    compare(TopicRequest.systemRequest([]), null);
    compare(TopicRequest.systemRequest(undefined), null);
  }

  function test_one_consumer() {
    compare(TopicRequest.systemRequest([req(1000, ["cpu"], {
        "diskPaths": ["/"],
        "history": true
      })]), {
      "interval": 1000,
      "metrics": ["cpu"],
      "diskPaths": ["/"],
      "history": ["cpu"]
    });
  }

  function test_shortest_interval_wins() {
    compare(TopicRequest.systemRequest([req(2000), req(1000)]).interval, 1000);
    compare(TopicRequest.systemRequest([req(1000), req(2000)]).interval, 1000);
  }

  function test_bad_interval_is_the_default_never_zero() {
    for (const bad of [undefined, 0, "", false, NaN, -5, Infinity])
      compare(TopicRequest.systemRequest([req(bad)]).interval, 2000, `${bad}`);
    // A consumer still setting up doesn't drag a real one to 0
    compare(TopicRequest.systemRequest([req(0), req(5000)]).interval, 2000);
  }

  function test_interval_helper() {
    compare(TopicRequest.interval(500, 2000), 500);
    compare(TopicRequest.interval(0, 2000), 2000);
    compare(TopicRequest.interval(null, 7), 7);
  }

  function test_lists_are_deduped() {
    const r = TopicRequest.systemRequest([req(2000, ["cpu", "mem"], {
        "diskPaths": ["/", "/home"]
      }), req(2000, ["mem", "gpu"], {
        "diskPaths": ["/"]
      })]);
    compare(r.metrics, ["cpu", "mem", "gpu"]);
    compare(r.diskPaths, ["/", "/home"]);
  }

  function test_history_only_for_graphed_metrics_asked_for() {
    const r = TopicRequest.systemRequest([req(2000, ["cpu", "disk", "net"], {
        "history": true
      }), req(2000, ["mem"])]);
    compare(r.history, ["cpu", "net"], "disk isn't graphed; mem's consumer didn't ask");
  }

  function test_equal_requests_have_equal_keys() {
    const a = JSON.stringify(TopicRequest.systemRequest([req(2000, ["cpu"])]));
    const b = JSON.stringify(TopicRequest.systemRequest([req(0, ["cpu"])]));
    compare(a, b);
  }
}

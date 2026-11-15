import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "BuildOrder"

  function labels(queue) {
    return queue.map(entry => entry.label);
  }

  function queued(entries) {
    let queue = [];
    for (const entry of entries)
      queue = BuildOrder.enqueue(queue, entry);
    return queue;
  }

  // A `first` job goes ahead of the others, and the `first` ones keep their request order
  function test_first_goes_ahead_in_request_order() {
    const queue = queued([
      {
        "label": "a"
      },
      {
        "label": "b"
      },
      {
        "label": "side 1",
        "first": true
      },
      {
        "label": "c"
      },
      {
        "label": "side 2",
        "first": true
      }
    ]);
    compare(labels(queue), ["side 1", "side 2", "a", "b", "c"]);
    compare(BuildOrder.next(queue).label, "side 1");
  }

  // With none `first`, the visible owner's job goes first, else the head
  function test_next_prefers_visible() {
    const queue = queued([
      {
        "label": "hidden",
        "owner": {
          "visible": false
        }
      },
      {
        "label": "shown",
        "owner": {
          "visible": true
        }
      }
    ]);
    compare(BuildOrder.next(queue).label, "shown");
    compare(BuildOrder.next([queue[0]]).label, "hidden");
  }
}

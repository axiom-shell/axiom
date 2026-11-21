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

  // A held entry (its holder's `buildHeld`) is skipped, wherever it stands
  function test_next_skips_held() {
    const held = {
      "buildHeld": true
    };
    const queue = queued([
      {
        "label": "held",
        "holder": held
      },
      {
        "label": "free",
        "holder": {
          "buildHeld": false
        }
      },
      {
        "label": "none"
      }
    ]);
    compare(BuildOrder.next(queue).label, "free");
    held.buildHeld = false;
    compare(BuildOrder.next(queue).label, "held");
  }

  // Every entry held: nothing to run
  function test_next_null_when_all_held() {
    const held = {
      "buildHeld": true
    };
    const queue = queued([
      {
        "label": "a",
        "holder": held
      },
      {
        "label": "b",
        "holder": held,
        "first": true
      }
    ]);
    compare(BuildOrder.next(queue), null);
    compare(BuildOrder.next([]), null);
  }

  // `runnable` counts the entries that aren't held
  function test_runnable_counts_unheld() {
    const held = {
      "buildHeld": true
    };
    const queue = queued([
      {
        "label": "a",
        "holder": held
      },
      {
        "label": "b"
      },
      {
        "label": "c",
        "holder": {
          "buildHeld": false
        }
      }
    ]);
    compare(BuildOrder.runnable(queue), 2);
    compare(BuildOrder.runnable([]), 0);
    held.buildHeld = false;
    compare(BuildOrder.runnable(queue), 3);
  }

  // A held `first` entry is skipped but keeps its place: the others go first, and it is next once released
  function test_held_first_keeps_its_place() {
    const held = {
      "buildHeld": true
    };
    const queue = queued([
      {
        "label": "a"
      },
      {
        "label": "side",
        "first": true,
        "holder": held
      }
    ]);
    compare(labels(queue), ["side", "a"]);
    compare(BuildOrder.next(queue).label, "a");
    held.buildHeld = false;
    compare(BuildOrder.next(queue).label, "side");
  }

  // The holder is the nearest ancestor (from the item itself) with a `buildHeld`
  function test_holderOf_walks_parents() {
    const page = {
      "buildHeld": true,
      "parent": null
    };
    const mid = {
      "parent": page
    };
    const leaf = {
      "parent": mid
    };
    compare(BuildOrder.holderOf(leaf), page);
    compare(BuildOrder.holderOf(page), page);
    compare(BuildOrder.holderOf({
      "parent": null
    }), null);
    compare(BuildOrder.holderOf(null), null);
  }
}

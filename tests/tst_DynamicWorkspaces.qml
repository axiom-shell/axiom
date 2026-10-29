import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "DynamicWorkspaces"

  function ws(id, output, windowCount, active) {
    return {
      "id": id,
      "name": String(id),
      "output": output,
      "windowCount": windowCount,
      "active": active === true,
      "focused": false
    };
  }

  readonly property var bases: ({
      "A": 1,
      "B": 101
    })

  function test_workspaces_add_an_empty_one_after_the_last() {
    const shown = DynamicWorkspaces.workspaces([ws(1, "A", 2, true), ws(2, "A", 1)], {
      "A": 1
    }, 100);
    compare(shown.map(w => w.id), [1, 2, 3]);
    compare(shown[2].windowCount, 0);
    compare(shown[2].output, "A");
  }

  function test_workspaces_keep_an_empty_last_one_alone() {
    const shown = DynamicWorkspaces.workspaces([ws(1, "A", 2), ws(2, "A", 0, true)], {
      "A": 1
    }, 100);
    compare(shown.map(w => w.id), [1, 2], "the active empty one is the one at the end");
  }

  function test_workspaces_of_an_output_without_any() {
    const shown = DynamicWorkspaces.workspaces([ws(1, "A", 1)], bases, 100);
    compare(shown.map(w => w.id), [1, 2, 101], "an output with none gets its first id, empty");
    compare(shown[2].output, "B");
  }

  function test_workspaces_leave_out_special_and_named_ones() {
    const shown = DynamicWorkspaces.workspaces([ws(-98, "A", 1), ws(-1337, "A", 1), ws(1, "A", 1), ws(102, "B", 1)], bases, 100);
    compare(shown.map(w => w.id), [1, 2, 102, 103]);
  }

  function test_workspaces_list_borrowed_ones_after_their_own() {
    const shown = DynamicWorkspaces.workspaces([ws(202, "A", 1), ws(201, "A", 2), ws(1, "A", 1, true), ws(101, "B", 1)], bases, 100);
    compare(shown.map(w => w.id), [1, 201, 202, 2, 101, 102], "an unplugged monitor's on A, then A's empty one");
    compare(shown.map(w => w.output), ["A", "A", "A", "A", "B", "B"]);
  }

  function test_workspaces_borrowed_empty_last_one_ends_the_list() {
    const shown = DynamicWorkspaces.workspaces([ws(1, "A", 1), ws(201, "A", 0, true)], {
      "A": 1
    }, 100);
    compare(shown.map(w => w.id), [1, 201], "the active empty borrowed one is the one at the end");
  }

  function test_compaction_leaves_borrowed_ones_in_place() {
    const plan = DynamicWorkspaces.compaction([
      {
        "name": "A",
        "active": 203,
        "focused": true
      }
    ], [
      {
        "id": "a",
        "workspace": 1
      },
      {
        "id": "b",
        "workspace": 201
      },
      {
        "id": "c",
        "workspace": 203
      }
    ], bases, 100);
    compare(plan.changed, false, "nothing in A's block has a gap, and 201, 203 aren't A's to close");
    compare(plan.moves, []);
  }

  function test_workspaces_stop_at_the_end_of_the_block() {
    const shown = DynamicWorkspaces.workspaces([ws(1, "A", 1), ws(2, "A", 1)], {
      "A": 1
    }, 2);
    compare(shown.map(w => w.id), [1, 2]);
  }

  function test_compaction_without_gaps_changes_nothing() {
    const plan = DynamicWorkspaces.compaction([
      {
        "name": "A",
        "active": 2,
        "focused": true
      }
    ], [
      {
        "id": "a",
        "workspace": 1
      },
      {
        "id": "b",
        "workspace": 2
      }
    ], bases, 100);
    compare(plan.changed, false);
    compare(plan.moves, []);
    compare(plan.focus, []);
  }

  function test_compaction_closes_a_gap_below_the_active_one() {
    // 2 was left empty; the windows of 3 and 4 move down, and the focused
    // output follows its active workspace from 4 to 3
    const plan = DynamicWorkspaces.compaction([
      {
        "name": "A",
        "active": 4,
        "focused": true
      }
    ], [
      {
        "id": "a",
        "workspace": 1
      },
      {
        "id": "c",
        "workspace": 4
      },
      {
        "id": "b",
        "workspace": 3
      }
    ], bases, 100);
    compare(plan.changed, true);
    compare(plan.moves, [
      {
        "id": "b",
        "to": 2
      },
      {
        "id": "c",
        "to": 3
      }
    ], "lowest first, so none lands on one still to be emptied");
    compare(plan.focus, [
      {
        "monitor": "A",
        "id": 3,
        "stay": false
      }
    ]);
  }

  function test_compaction_keeps_the_active_empty_one_in_place() {
    // Active 2 is empty but kept (niri drops it once it's left); 3 is
    // already next to it
    const plan = DynamicWorkspaces.compaction([
      {
        "name": "A",
        "active": 2,
        "focused": true
      }
    ], [
      {
        "id": "a",
        "workspace": 1
      },
      {
        "id": "b",
        "workspace": 3
      }
    ], bases, 100);
    compare(plan.changed, false);
  }

  function test_compaction_brings_a_far_active_empty_one_back() {
    const plan = DynamicWorkspaces.compaction([
      {
        "name": "A",
        "active": 7,
        "focused": true
      }
    ], [
      {
        "id": "a",
        "workspace": 1
      }
    ], bases, 100);
    compare(plan.moves, []);
    compare(plan.focus, [
      {
        "monitor": "A",
        "id": 2,
        "stay": false
      }
    ]);
  }

  function test_compaction_gives_focus_back_to_the_focused_output() {
    // B's active workspace moves; A, focused, gets focus back without
    // focusing its workspace again
    const plan = DynamicWorkspaces.compaction([
      {
        "name": "A",
        "active": 1,
        "focused": true
      },
      {
        "name": "B",
        "active": 103,
        "focused": false
      }
    ], [
      {
        "id": "a",
        "workspace": 1
      },
      {
        "id": "b",
        "workspace": 103
      }
    ], bases, 100);
    compare(plan.moves, [
      {
        "id": "b",
        "to": 101
      }
    ]);
    compare(plan.focus, [
      {
        "monitor": "B",
        "id": 101,
        "stay": false
      },
      {
        "monitor": "A",
        "id": 1,
        "stay": true
      }
    ]);
  }

  function test_compaction_leaves_ids_outside_the_blocks_alone() {
    const plan = DynamicWorkspaces.compaction([
      {
        "name": "A",
        "active": 1,
        "focused": true
      }
    ], [
      {
        "id": "a",
        "workspace": 1
      },
      {
        "id": "s",
        "workspace": -98
      }
    ], bases, 100);
    compare(plan.changed, false, "a special workspace's window stays");
  }
}

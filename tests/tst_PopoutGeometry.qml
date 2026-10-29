import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "PopoutGeometry"

  function rect(x, y, w, h) {
    return {
      "x": x,
      "y": y,
      "width": w,
      "height": h
    };
  }

  function entry(id, kind, footprint, extra) {
    return Object.assign({
      "id": id,
      "kind": kind,
      "pinned": false,
      "resident": false,
      "screen": "DP-1",
      "parentId": "",
      "phase": "open",
      "footprint": footprint
    }, extra);
  }

  function test_ranks() {
    compare(PopoutGeometry.rankOf(entry("d", "dock", [])), 1);
    compare(PopoutGeometry.rankOf(entry("l", "launcher", [])), 5);
    // Pinned ranks lowest, under the dock
    compare(PopoutGeometry.rankOf(entry("m", "menu", [], {
      "pinned": true
    })), 0);
    // A submenu takes its parent's
    compare(PopoutGeometry.rankOf(entry("s", "submenu", [], {
      "parentId": "m"
    }), entry("m", "menu", [])), 4);
  }

  function test_intersects() {
    verify(PopoutGeometry.intersects([rect(0, 0, 10, 10)], [rect(5, 5, 10, 10)]));
    // Meeting along an edge isn't overlapping
    verify(!PopoutGeometry.intersects([rect(0, 0, 10, 10)], [rect(10, 0, 10, 10)]));
    // Any rect of either counts: a fillet square alone
    verify(PopoutGeometry.intersects([rect(0, 0, 10, 10), rect(100, 0, 54, 29)], [rect(140, 20, 50, 50)]));
    verify(!PopoutGeometry.intersects([], [rect(0, 0, 10, 10)]));
  }

  function test_offset() {
    compare(PopoutGeometry.offset([rect(1, 2, 3, 4)], {
      "x": 10,
      "y": 20
    }), [rect(11, 22, 3, 4)]);
  }

  function test_higher_evicts_lower_it_covers() {
    const entries = [entry("osd", "osd", [rect(0, 0, 100, 50)]), entry("dock", "dock", [rect(500, 0, 100, 50)], {
        "resident": true
      })];
    const r = PopoutGeometry.resolve(entries, entry("bar", "bar", [rect(50, 0, 100, 50)]));
    verify(r.allowed);
    compare(r.evict, ["osd"]);
    // The dock elsewhere on the edge stays
    compare(r.yield, []);
  }

  function test_higher_refuses_lower() {
    const entries = [entry("launcher", "launcher", [rect(0, 0, 400, 300)])];
    const r = PopoutGeometry.resolve(entries, entry("osd", "osd", [rect(100, 0, 100, 50)]));
    verify(!r.allowed);
    compare(r.blockedBy, "launcher");
    compare(r.evict, []);
  }

  function test_equal_rank_new_wins() {
    const entries = [entry("menuA", "menu", [rect(0, 0, 100, 100)])];
    const r = PopoutGeometry.resolve(entries, entry("menuB", "menu", [rect(50, 50, 100, 100)]));
    verify(r.allowed);
    compare(r.evict, ["menuA"]);
  }

  function test_residents_yield() {
    const entries = [entry("dock", "dock", [rect(0, 0, 100, 50)], {
        "resident": true
      }), entry("pin", "menu", [rect(200, 0, 100, 50)], {
        "pinned": true,
        "resident": true
      })];
    const r = PopoutGeometry.resolve(entries, entry("osd", "osd", [rect(50, 0, 200, 50)]));
    verify(r.allowed);
    compare(r.evict, []);
    compare(r.yield, ["dock", "pin"]);
  }

  function test_pinned_under_dock() {
    // A pinned menu ranks under the dock: it can't come back over it
    const entries = [entry("dock", "dock", [rect(0, 0, 100, 50)], {
        "resident": true
      })];
    const r = PopoutGeometry.resolve(entries, entry("pin", "menu", [rect(50, 0, 100, 50)], {
      "pinned": true,
      "resident": true
    }));
    verify(!r.allowed);
  }

  function test_ignored_entries() {
    const fp = [rect(0, 0, 100, 100)];
    const entries = [entry("other", "launcher", fp, {
        "screen": "HDMI-A-1"
      }), entry("gone", "launcher", fp, {
        "phase": "closing"
      }), entry("away", "launcher", fp, {
        "phase": "yielded"
      }), entry("self", "menu", fp)];
    const r = PopoutGeometry.resolve(entries, entry("self", "osd", fp));
    verify(r.allowed);
    compare(r.evict, []);
  }

  function test_parent_and_submenu() {
    const parentFp = [rect(0, 0, 200, 200)];
    const entries = [entry("bar:top", "bar", parentFp), entry("sub", "submenu", [rect(200, 0, 150, 100)], {
        "parentId": "bar:top"
      })];
    // A submenu over its own parent is fine
    verify(PopoutGeometry.resolve(entries, entry("sub", "submenu", [rect(150, 0, 150, 100)], {
      "parentId": "bar:top"
    })).allowed);
    // A menu over the submenu closes its parent (the submenu goes with it)
    const r = PopoutGeometry.resolve(entries, entry("menu", "menu", [rect(250, 50, 100, 100)]));
    verify(r.allowed);
    compare(r.evict, ["bar:top"]);
    // An OSD under the submenu is refused: the submenu has the bar's rank
    verify(!PopoutGeometry.resolve(entries, entry("osd", "osd", [rect(250, 50, 50, 50)])).allowed);
  }

  function test_corner_between_bars() {
    // A top bar's popout at the left end and a left bar's at the top end
    // meet only if their fillets do
    const top = entry("bar:top", "bar", [rect(60, 0, 300, 200), rect(6, 0, 54, 29)]);
    verify(PopoutGeometry.resolve([top], entry("bar:left", "bar", [rect(0, 220, 200, 300), rect(0, 520, 29, 54)])).allowed);
    compare(PopoutGeometry.resolve([top], entry("bar:left", "bar", [rect(0, 220, 200, 300), rect(0, 520, 29, 54)])).evict, []);
    compare(PopoutGeometry.resolve([top], entry("bar:left", "bar", [rect(0, 150, 200, 300)])).evict, ["bar:top"]);
  }

  function test_resuming_never_takes_turns() {
    const entries = [entry("dockA", "dock", [rect(0, 0, 100, 50)], {
        "resident": true
      })];
    // A resident coming back won't evict one of its own rank
    verify(!PopoutGeometry.resolve(entries, entry("dockB", "dock", [rect(50, 0, 100, 50)], {
      "resident": true,
      "resuming": true
    })).allowed);
  }

  function test_resumable() {
    const entries = [entry("dock", "dock", [rect(0, 0, 100, 50)], {
        "resident": true,
        "phase": "yielded"
      }), entry("pin", "menu", [rect(50, 0, 100, 50)], {
        "pinned": true,
        "resident": true,
        "phase": "yielded"
      }), entry("pin2", "menu", [rect(500, 0, 100, 50)], {
        "pinned": true,
        "resident": true,
        "phase": "yielded"
      }), entry("osd", "osd", [rect(520, 0, 50, 50)])];
    // The dock comes back first and keeps the pinned menu under it away;
    // the other pinned menu waits for the OSD over it
    compare(PopoutGeometry.resumable(entries), ["dock"]);
  }

  function test_makeWay() {
    const stack = rect(1500, 50, 360, 200);
    compare(PopoutGeometry.makeWay([], "DP-1", stack, "y", 1, 8, 800), 0, "nothing showing");
    const pop = entry("bar:clock", "bar", [rect(1400, 40, 400, 300)]);
    compare(PopoutGeometry.makeWay([pop], "DP-1", stack, "y", 1, 8, 800), 298, "below the popout, a gap past it");
    compare(PopoutGeometry.makeWay([pop], "DP-1", rect(1500, 300, 360, 200), "y", -1, 8, 800), 468, "up, above it");
    const lower = entry("menu:m", "menu", [rect(1600, 350, 300, 100)]);
    compare(PopoutGeometry.makeWay([pop, lower], "DP-1", stack, "y", 1, 8, 800), 408, "past a second popout the first shift ran into");
    compare(PopoutGeometry.makeWay([pop], "DP-1", stack, "y", 1, 8, 100), 100, "capped at the room left");
    compare(PopoutGeometry.makeWay([entry("bar:x", "bar", [rect(1400, 40, 400, 300)], {
        "screen": "HDMI-1"
      })], "DP-1", stack, "y", 1, 8, 800), 0, "another screen");
    compare(PopoutGeometry.makeWay([entry("bar:x", "bar", [rect(1400, 40, 400, 300)], {
        "phase": "closing"
      })], "DP-1", stack, "y", 1, 8, 800), 0, "a closing popout");
  }
}

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

  // A toast ranks one over a dock, whatever else it ranks against
  function test_rank_against() {
    const toast = entry("t", "toast", []);
    const dock = entry("d", "dock", []);
    compare(PopoutGeometry.rankAgainst(toast, null, dock), 2);
    compare(PopoutGeometry.rankAgainst(toast, null, entry("o", "osd", [])), -1);
    compare(PopoutGeometry.rankAgainst(dock, null, toast), 1);
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

  function test_toasts() {
    const toasts = entry("toasts:DP-1", "toast", [rect(1500, 50, 360, 200)], {
      "resident": true
    });
    compare(PopoutGeometry.rankOf(toasts), -1, "under everything");
    compare(PopoutGeometry.resolve([toasts], entry("bar:clock", "bar", [rect(1400, 40, 400, 300)])).yield, ["toasts:DP-1"], "a popout over them: they give way and come back");
    compare(PopoutGeometry.resolve([toasts], entry("bar:clock", "bar", [rect(0, 40, 400, 300)])).yield, [], "beside them: nothing happens");
    verify(!PopoutGeometry.resolve([entry("osd:main:DP-1", "osd", [rect(1500, 100, 300, 60)])], toasts).allowed, "arriving under an OSD: they wait");
    const dock = entry("dock:main:DP-1", "dock", [rect(1500, 100, 300, 60)], {
      "resident": true
    });
    const over = PopoutGeometry.resolve([dock], toasts);
    verify(over.allowed, "a stack over an open dock is allowed");
    compare(over.yield, [dock.id], "and puts it away");
    const under = PopoutGeometry.resolve([toasts], dock);
    verify(!under.allowed, "a dock claiming under a stack is refused");
    compare(under.blockedBy, toasts.id);
    verify(!PopoutGeometry.resolve([toasts], Object.assign({}, dock, {
      "resuming": true
    })).allowed, "and so is one coming back");
    // A dock beside the stack is untouched either way
    const beside = entry("dock:main:DP-1", "dock", [rect(0, 100, 300, 60)], {
      "resident": true
    });
    compare(PopoutGeometry.resolve([beside], toasts).yield, []);
    verify(PopoutGeometry.resolve([toasts], beside).allowed);
    // A yielded stack refuses a dock coming back, not a dock's own claim
    const waiting = Object.assign({}, toasts, {
      "phase": "yielded"
    });
    verify(!PopoutGeometry.resolve([waiting], Object.assign({}, dock, {
      "resuming": true
    })).allowed, "a waiting stack keeps a dock away");
    const own = PopoutGeometry.resolve([waiting], dock);
    verify(own.allowed, "but not a dock showing anew");
    compare(own.yield, []);
    // A dock that magnified into an open stack is refused; one beside is not
    const grown = Object.assign({}, beside, {
      "footprint": [rect(0, 100, 1600, 60)]
    });
    compare(PopoutGeometry.resolve([toasts], grown).blockedBy, toasts.id, "a dock grown into the stack");
  }

  // The dock waits for the stack, and the pairs with a popout stay in rank
  function test_toasts_and_dock_resume() {
    const toasts = entry("toasts:DP-1", "toast", [rect(1500, 50, 360, 200)], {
      "resident": true,
      "phase": "yielded"
    });
    const dock = entry("dock:main:DP-1", "dock", [rect(1500, 100, 300, 60)], {
      "resident": true,
      "phase": "yielded"
    });
    compare(PopoutGeometry.resumable([toasts, dock]), ["toasts:DP-1"], "the dock waits for the stack");
    // A bar popout over both, then released
    const bar = entry("bar:clock", "bar", [rect(1400, 40, 500, 300)]);
    compare(PopoutGeometry.resumable([bar, toasts, dock]), [], "popout open: both wait");
    compare(PopoutGeometry.resumable([toasts, dock]), ["toasts:DP-1"], "popout gone: the stack only");
    // The three-way case: pinned menu, dock and stack overlapping
    const pin = entry("menu:pin", "menu", [rect(1450, 60, 200, 200)], {
      "pinned": true,
      "resident": true,
      "phase": "yielded"
    });
    compare(PopoutGeometry.resumable([pin, dock, toasts]), ["toasts:DP-1"], "the stack only");
    const openStack = Object.assign({}, toasts, {
      "phase": "open"
    });
    compare(PopoutGeometry.resumable([pin, dock, openStack]), [], "the stack shown holds the dock away, and the pinned menu with it");
    const shown = Object.assign({}, pin, {
      "phase": "open"
    });
    compare(PopoutGeometry.resumable([shown, dock, toasts]), [], "no turn-taking with the pinned menu shown");
    // The pinned menu over a waiting stack, the dock claiming anew under both
    const claim = PopoutGeometry.resolve([Object.assign({}, pin, {
        "phase": "open"
      }), toasts], Object.assign({}, dock, {
      "phase": "open"
    }));
    verify(claim.allowed);
    compare(claim.yield, ["menu:pin"], "the claim skips the waiting stack and yields the pinned menu");
    const openDock = Object.assign({}, dock, {
      "phase": "open"
    });
    compare(PopoutGeometry.resumable([pin, toasts, openDock]), ["toasts:DP-1"], "the stack shows over the yielded pinned menu and yields the dock");
    compare(PopoutGeometry.resumable([pin, dock]), ["dock:main:DP-1"], "the stack released: the dock outranks the pinned menu");
  }
  // A free menu ranks as any popout (no underlay): unpinned, as its
  // opener's kind, so a higher popout over it (the launcher) closes it and
  // a lower one it covers is refused; pinned or popped out (held as if
  // pinned), lowest, giving way to a bar popout over it and coming back
  function test_free_menu() {
    const free = entry("menu:tools", "menu", [rect(400, 300, 500, 400)]);
    const bar = entry("bar:clock", "bar", [rect(600, 40, 400, 300)]);
    const refused = PopoutGeometry.resolve([free], bar);
    verify(!refused.allowed, "a bar popout over it is refused");
    compare(refused.blockedBy, "menu:tools");
    compare(PopoutGeometry.resolve([free], entry("launcher:DP-1", "launcher", [rect(500, 200, 600, 400)])).evict, ["menu:tools"], "the launcher closes it");
    const asBar = Object.assign({}, free, {
      "kind": "bar"
    });
    compare(PopoutGeometry.resolve([asBar], bar).evict, ["menu:tools"], "a widget's, a neighbour's popout replaces it");
    const pinned = Object.assign({}, free, {
      "pinned": true,
      "resident": true
    });
    const over = PopoutGeometry.resolve([pinned], bar);
    verify(over.allowed);
    compare(over.yield, ["menu:tools"], "pinned (or popped out), it gives way");
    compare(PopoutGeometry.resumable([Object.assign({}, pinned, {
        "phase": "yielded"
      })]), ["menu:tools"], "and comes back once uncovered");
  }
}

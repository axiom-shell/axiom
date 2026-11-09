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
    verify(PopoutGeometry.resolve([dock], toasts).allowed, "a dock and toasts never collide");
    compare(PopoutGeometry.resolve([toasts], dock).yield, []);
  }
  // A pinned free menu (underlay: drawn under every popout) never
  // collides: a bar popout opens over it and both stay; it never closes
  // what it opens or grows over
  function test_underlay() {
    const free = entry("menu:tools", "menu", [rect(400, 300, 500, 400)], {
      "pinned": true,
      "resident": true,
      "underlay": true
    });
    const bar = entry("bar:clock", "bar", [rect(600, 40, 400, 300)]);
    const over = PopoutGeometry.resolve([free], bar);
    verify(over.allowed, "a bar popout opens over it");
    compare(over.evict, []);
    compare(over.yield, [], "and it stays");
    const under = PopoutGeometry.resolve([bar], Object.assign({}, free, {
      "kind": "bar",
      "pinned": false
    }));
    verify(under.allowed, "engaged, opened under a bar popout, it's granted too");
    compare(under.evict, [], "and closes nothing");
    const sub = entry("menu:tools/submenu", "submenu", [rect(900, 300, 300, 300)], {
      "parentId": "menu:tools"
    });
    compare(PopoutGeometry.resolve([free, sub], entry("bar:net", "bar", [rect(950, 40, 300, 300)])).evict, [], "its submenu neither");
    verify(PopoutGeometry.resolve([free, entry("osd:vol:DP-1", "osd", [rect(950, 300, 300, 60)])], sub).allowed);
  }

  // Unpinned, a free menu (a widget's popout, ranked bar) covered by
  // another bar popout closes, as before; and pinned but no underlay (a
  // floating edge menu) it yields
  function test_free_not_underlay() {
    const free = entry("menu:tools", "bar", [rect(400, 300, 500, 400)]);
    compare(PopoutGeometry.resolve([free], entry("bar:clock", "bar", [rect(600, 40, 400, 300)])).evict, ["menu:tools"]);
    const pinned = Object.assign({}, free, {
      "pinned": true,
      "resident": true
    });
    compare(PopoutGeometry.resolve([pinned], entry("bar:clock", "bar", [rect(600, 40, 400, 300)])).yield, ["menu:tools"]);
  }

  // The overlay opening closes the bar popouts and menus on its screen,
  // pinned ones too, but not a pinned free menu, which it draws over
  function test_closed_by_overlay() {
    const entries = [entry("bar:clock", "bar", [rect(0, 0, 10, 10)]), entry("menu:edge", "menu", [rect(0, 0, 10, 10)], {
        "pinned": true,
        "resident": true,
        "phase": "yielded"
      }), entry("menu:free", "menu", [rect(0, 0, 10, 10)], {
        "pinned": true,
        "resident": true,
        "underlay": true
      }), entry("osd:vol:DP-1", "osd", [rect(0, 0, 10, 10)]), entry("bar:other", "bar", [rect(0, 0, 10, 10)], {
        "screen": "HDMI-A-1"
      })];
    compare(PopoutGeometry.closedByOverlay(entries, "DP-1"), ["bar:clock", "menu:edge"]);
  }
}

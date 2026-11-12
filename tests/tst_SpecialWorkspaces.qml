import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "SpecialWorkspaces"

  function test_validId_data() {
    return [
      {
        "tag": "plain",
        "id": "magic",
        "ok": true
      },
      {
        "tag": "dash and underscore",
        "id": "my-pad_2",
        "ok": true
      },
      {
        "tag": "dot",
        "id": "a.b",
        "ok": true
      },
      {
        "tag": "32 chars",
        "id": "a".repeat(32),
        "ok": true
      },
      {
        "tag": "empty",
        "id": "",
        "ok": false
      },
      {
        "tag": "reserved",
        "id": "special",
        "ok": false
      },
      {
        "tag": "leading dash",
        "id": "-x",
        "ok": false
      },
      {
        "tag": "space",
        "id": "my pad",
        "ok": false
      },
      {
        "tag": "semicolon",
        "id": "a;b",
        "ok": false
      },
      {
        "tag": "comma",
        "id": "a,b",
        "ok": false
      },
      {
        "tag": "33 chars",
        "id": "a".repeat(33),
        "ok": false
      },
      {
        "tag": "non-ascii",
        "id": "Ä",
        "ok": false
      },
      {
        "tag": "not a string",
        "id": null,
        "ok": false
      }
    ];
  }

  function test_validId(data) {
    compare(SpecialWorkspaces.validId(data.id), data.ok);
  }

  function special(name, count, open) {
    return {
      "name": name,
      "id": -98,
      "open": open === true,
      "output": open === true ? "DP-1" : "",
      "windowCount": count,
      "urgent": false,
      "windows": []
    };
  }

  readonly property var sites: [
    {
      "path": ["Keybinds", "binds"],
      "key": "argument",
      "when": {
        "action": ["toggleSpecial", "moveToSpecial"]
      },
      "usedBy": "Used by keybind {0}",
      "name": "key"
    },
    {
      "path": ["HotCorners", "items"],
      "key": "argument",
      "when": {
        "action": ["toggleSpecial"]
      },
      "usedBy": "Used by hot corner {0}",
      "name": "corner",
      "nameLabels": {
        "topLeft": "Top left"
      }
    }
  ]

  function test_references() {
    const config = {
      "Keybinds": {
        "binds": [
          {
            "key": "SUPER + V",
            "action": "toggleSpecial",
            "argument": "magic"
          },
          {
            "key": "SUPER + M",
            "action": "moveToSpecial",
            "argument": "notes"
          },
          {
            "key": "SUPER + E",
            "action": "exec",
            "argument": "magic"
          },
          {
            "key": "SUPER + X",
            "action": "toggleSpecial",
            "argument": ""
          },
          {
            "key": "SUPER + Y",
            "action": "toggleSpecial"
          }
        ]
      },
      "HotCorners": {
        "items": [
          {
            "corner": "topLeft",
            "action": "toggleSpecial",
            "argument": "magic"
          },
          {
            "corner": "topRight",
            "action": "moveToSpecial",
            "argument": "magic"
          }
        ]
      }
    };
    compare(SpecialWorkspaces.references(config, sites), [
      {
        "id": "magic",
        "usedBy": "Used by keybind {0}",
        "name": "SUPER + V",
        "translate": false
      },
      {
        "id": "notes",
        "usedBy": "Used by keybind {0}",
        "name": "SUPER + M",
        "translate": false
      },
      {
        "id": "magic",
        "usedBy": "Used by hot corner {0}",
        "name": "Top left",
        "translate": true
      }
    ], "a hot corner by its title; only the actions `when` names, with a non-empty id");
    compare(SpecialWorkspaces.references({}, sites), [], "no sections");
    compare(SpecialWorkspaces.references({
      "Keybinds": {
        "binds": "x"
      }
    }, sites), [], "not a list");
    compare(SpecialWorkspaces.references(config, []), []);
    compare(SpecialWorkspaces.references(null, null), []);
  }

  function test_list() {
    const entries = [
      {
        "id": "notes",
        "icon": "edit",
        "text": "Notes"
      },
      {
        "id": "idle",
        "icon": "",
        "text": ""
      }
    ];
    const refs = [
      {
        "id": "magic",
        "usedBy": "Used by keybind {0}",
        "name": "SUPER + V"
      },
      {
        "id": "notes",
        "usedBy": "Used by keybind {0}",
        "name": "SUPER + N"
      },
      {
        "id": "magic",
        "usedBy": "Used by hot corner {0}",
        "name": "topLeft"
      }
    ];
    const rows = SpecialWorkspaces.list(entries, [special("zed", 2), special("", 4), special("notes", 1), special("alpha", 0), special("bad name", 1)], refs);
    compare(rows.map(r => r.id), ["notes", "idle", "magic", "alpha", "bad name", "zed"], "entries, then referenced, then live by id; never the unnamed one");
    compare(rows[0].label, "Notes");
    compare(rows[0].icon, "edit");
    compare(rows[0].configured, true);
    compare(rows[0].windowCount, 1);
    compare(rows[0].refs.length, 1);
    compare(rows[1].configured, true);
    compare(rows[1].special, null);
    compare(rows[2].configured, false, "referenced only");
    compare(rows[2].refs.length, 2);
    compare(rows[3].configured, false, "live only");
    compare(rows[3].editable, true);
    compare(rows[4].editable, false, "an invalid live id");
    compare(SpecialWorkspaces.list([], [], []), []);
    compare(SpecialWorkspaces.list(null, null, null), []);
    compare(SpecialWorkspaces.list([
      {
        "id": "a"
      },
      {
        "id": "a"
      }
    ], [], []).length, 1, "no duplicate rows");
  }

  function test_blockersAndDeletable() {
    const free = {
      "configured": true,
      "windowCount": 0,
      "refs": []
    };
    compare(SpecialWorkspaces.blockers(free), []);
    compare(SpecialWorkspaces.deletable(free), true);
    const busy = {
      "configured": true,
      "windowCount": 2,
      "refs": [
        {
          "usedBy": "Used by keybind {0}",
          "name": "SUPER + V"
        }
      ]
    };
    compare(SpecialWorkspaces.blockers(busy), [
      {
        "kind": "windows",
        "count": 2
      },
      {
        "kind": "ref",
        "usedBy": "Used by keybind {0}",
        "name": "SUPER + V",
        "translate": false
      }
    ], "windows first, then each reference");
    compare(SpecialWorkspaces.deletable(busy), false);
    compare(SpecialWorkspaces.deletable({
      "configured": false,
      "windowCount": 0,
      "refs": []
    }), false, "not configured: nothing to delete");
    compare(SpecialWorkspaces.deletable({
      "configured": true,
      "windowCount": 0,
      "refs": [
        {
          "usedBy": "x",
          "name": "y"
        }
      ]
    }), false, "a reference alone blocks");
    compare(SpecialWorkspaces.deletable(null), false);
  }

  function test_cells() {
    const rows = SpecialWorkspaces.list([
      {
        "id": "term"
      },
      {
        "id": "zed"
      }
    ], [special("zed", 1), special("open", 0, true), special("closed", 0), special("alpha", 2)], []);
    const specials = [special("zed", 1), special("open", 0, true), special("closed", 0), special("alpha", 2)];
    compare(SpecialWorkspaces.cells(rows, specials, "off"), []);
    compare(SpecialWorkspaces.cells(rows, specials, "occupied").map(c => c.name), ["zed", "alpha", "open"], "windows or open, in the list's order");
    const all = SpecialWorkspaces.cells(rows, specials, "all");
    compare(all.map(c => c.name), ["term", "zed", "alpha", "closed", "open"], "every row, the list's order");
    compare(all[0], {
      "name": "term",
      "id": 0,
      "open": false,
      "output": "",
      "windowCount": 0,
      "urgent": false,
      "windows": []
    }, "a listed id with no state");
    compare(SpecialWorkspaces.cells(rows, specials, "bogus"), []);
    compare(SpecialWorkspaces.cells(null, null, "all"), []);
  }

  function test_cellsUnnamed() {
    const unnamed = (count, open) => special("", count, open);
    const rows = SpecialWorkspaces.list([
      {
        "id": "term"
      }
    ], [], []);
    compare(SpecialWorkspaces.cells(rows, [special("a", 0), unnamed(0)], "all").map(c => c.name), ["term"], "not padded into all");
    compare(SpecialWorkspaces.cells(SpecialWorkspaces.list([], [special("a", 1)], []), [special("a", 1), unnamed(2)], "occupied").map(c => c.name), ["a", ""], "shown with windows, last");
    compare(SpecialWorkspaces.cells([], [unnamed(0)], "occupied").map(c => c.name), [], "occupied needs windows or open");
    compare(SpecialWorkspaces.cells([], [unnamed(0, true)], "all").map(c => c.name), [""], "shown while open");
    compare(SpecialWorkspaces.cells(rows, [unnamed(1), special("a", 0)], "all").map(c => c.name), ["term", ""], "last in all too");
  }

  function test_entryFor() {
    const entries = [
      {
        "id": "a",
        "icon": "x"
      },
      {
        "id": "a",
        "icon": "y"
      },
      {
        "id": "",
        "text": "Notes"
      }
    ];
    compare(SpecialWorkspaces.entryFor(entries, "a").icon, "x");
    compare(SpecialWorkspaces.entryFor(entries, "b"), null);
    compare(SpecialWorkspaces.entryFor(entries, ""), null, "a blank-id row never labels the unnamed one");
    compare(SpecialWorkspaces.entryFor(null, "a"), null);
  }

  function shown(kind, text, lead, tail) {
    return {
      "kind": kind,
      "text": text,
      "lead": lead,
      "tail": tail
    };
  }

  function test_content() {
    const entry = {
      "id": "m",
      "icon": "ico",
      "text": "Magic"
    };
    compare(SpecialWorkspaces.content(entry, "m", "icon", true, false), shown("text", "ico", "", false));
    compare(SpecialWorkspaces.content(null, "m", "icon", true, false), shown("icons", "", "", false));
    compare(SpecialWorkspaces.content(null, "m", "icon", false, false), shown("glyph", "star", "", false));
    compare(SpecialWorkspaces.content(entry, "m", "name", false, false), shown("text", "Magic", "", false));
    compare(SpecialWorkspaces.content(null, "m", "name", false, false), shown("name", "m", "", false));
  }

  function test_contentUnnamed() {
    compare(SpecialWorkspaces.content(null, "", "name", false, false), shown("glyph", "star", "", false), "a star, never empty text");
    compare(SpecialWorkspaces.content(null, "", "both", true, false), shown("glyph", "star", "", false));
    compare(SpecialWorkspaces.content(null, "", "icon", true, false), shown("icons", "", "", false), "the apps' icons as for any");
    compare(SpecialWorkspaces.content(null, "", "icon", false, false), shown("glyph", "star", "", false));
  }

  function test_contentBoth() {
    const entry = {
      "id": "m",
      "icon": "ico",
      "text": "Magic"
    };
    compare(SpecialWorkspaces.content(entry, "m", "both", true, false), shown("text", "Magic", "ico", false), "its icon before its text, never app icons");
    compare(SpecialWorkspaces.content(null, "m", "both", false, false), shown("name", "m", "star", false), "a star and the id");
    compare(SpecialWorkspaces.content({
      "icon": "",
      "text": "T"
    }, "m", "both", false, false), shown("text", "T", "star", false));
  }

  function test_contentSplit() {
    const entry = {
      "id": "m",
      "icon": "ico",
      "text": "Magic"
    };
    compare(SpecialWorkspaces.content(null, "m", "icon", true, true), shown("glyph", "star", "", true), "the label is a star, the apps' icons follow the divider");
    compare(SpecialWorkspaces.content(entry, "m", "icon", true, true), shown("text", "ico", "", true));
    compare(SpecialWorkspaces.content(null, "m", "icon", false, true), shown("glyph", "star", "", false), "no windows, no divider");
    compare(SpecialWorkspaces.content(entry, "m", "both", true, true), shown("text", "Magic", "ico", true));
    compare(SpecialWorkspaces.content(null, "m", "name", true, true), shown("name", "m", "", true));
  }
}

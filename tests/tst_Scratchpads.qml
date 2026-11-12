import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "Scratchpads"

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

  function test_configuredNames() {
    const listed = [
      {
        "name": "notes"
      },
      {
        "name": " magic "
      },
      {
        "name": "  "
      },
      {
        "name": ""
      }
    ];
    const binds = [
      {
        "action": "toggleSpecial",
        "argument": "term"
      },
      {
        "action": "toggleSpecial",
        "argument": "notes"
      },
      {
        "action": "toggleSpecial",
        "argument": " "
      },
      {
        "action": "exec",
        "argument": "other"
      }
    ];
    compare(Scratchpads.configuredNames(listed, binds), ["notes", "magic", "term"], "the list first, then binds; no duplicates, blanks or other actions");
    compare(Scratchpads.configuredNames([], []), []);
  }

  function test_cells() {
    const specials = [special("zed", 1), special("open", 0, true), special("closed", 0), special("alpha", 2)];
    compare(Scratchpads.cells(specials, [], "off"), []);
    compare(Scratchpads.cells(specials, [], "occupied").map(c => c.name), ["alpha", "open", "zed"], "windows or open, the rest by name");
    const all = Scratchpads.cells(specials, ["term", "zed"], "all");
    compare(all.map(c => c.name), ["term", "zed", "alpha", "closed", "open"], "configured order first, then alphabetical");
    compare(all[0], {
      "name": "term",
      "id": 0,
      "open": false,
      "output": "",
      "windowCount": 0,
      "urgent": false,
      "windows": []
    }, "a configured name with no state");
  }

  function test_cellsUnnamed() {
    const unnamed = (count, open) => special("", count, open);
    const idle = [special("a", 0), unnamed(0)];
    compare(Scratchpads.cells(idle, ["term"], "all").map(c => c.name), ["term", "a"], "not padded into all");
    compare(Scratchpads.cells([special("a", 1), unnamed(2)], [], "occupied").map(c => c.name), ["a", ""], "shown with windows, last");
    compare(Scratchpads.cells(idle, [], "occupied").map(c => c.name), [], "occupied needs windows or open");
    compare(Scratchpads.cells([unnamed(0, true)], [], "all").map(c => c.name), [""], "shown while open");
    compare(Scratchpads.cells([unnamed(1), special("a", 0)], ["a"], "all").map(c => c.name), ["a", ""], "last in all too");
  }

  function test_entryFor() {
    const listed = [
      {
        "name": "a",
        "icon": "x"
      },
      {
        "name": "a",
        "icon": "y"
      }
    ];
    compare(Scratchpads.entryFor(listed, "a").icon, "x");
    compare(Scratchpads.entryFor(listed, "b"), null);
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
      "name": "m",
      "icon": "ico",
      "text": "Magic"
    };
    compare(Scratchpads.content(entry, "m", "icon", true, false), shown("text", "ico", "", false));
    compare(Scratchpads.content(null, "m", "icon", true, false), shown("icons", "", "", false));
    compare(Scratchpads.content(null, "m", "icon", false, false), shown("glyph", "star", "", false));
    compare(Scratchpads.content(entry, "m", "name", false, false), shown("text", "Magic", "", false));
    compare(Scratchpads.content(null, "m", "name", false, false), shown("name", "m", "", false));
  }

  function test_contentUnnamed() {
    compare(Scratchpads.content(null, "", "name", false, false), shown("glyph", "star", "", false), "a star, never empty text");
    compare(Scratchpads.content(null, "", "both", true, false), shown("glyph", "star", "", false));
    compare(Scratchpads.content(null, "", "icon", true, false), shown("icons", "", "", false), "the apps' icons as for any");
    compare(Scratchpads.content(null, "", "icon", false, false), shown("glyph", "star", "", false));
  }

  function test_contentBoth() {
    const entry = {
      "name": "m",
      "icon": "ico",
      "text": "Magic"
    };
    compare(Scratchpads.content(entry, "m", "both", true, false), shown("text", "Magic", "ico", false), "its icon before its text, never app icons");
    compare(Scratchpads.content(null, "m", "both", false, false), shown("name", "m", "star", false), "a star and the name");
    compare(Scratchpads.content({
      "icon": "",
      "text": "T"
    }, "m", "both", false, false), shown("text", "T", "star", false));
  }

  function test_contentSplit() {
    const entry = {
      "name": "m",
      "icon": "ico",
      "text": "Magic"
    };
    compare(Scratchpads.content(null, "m", "icon", true, true), shown("glyph", "star", "", true), "the label is a star, the apps' icons follow the divider");
    compare(Scratchpads.content(entry, "m", "icon", true, true), shown("text", "ico", "", true));
    compare(Scratchpads.content(null, "m", "icon", false, true), shown("glyph", "star", "", false), "no windows, no divider");
    compare(Scratchpads.content(entry, "m", "both", true, true), shown("text", "Magic", "ico", true));
    compare(Scratchpads.content(null, "m", "name", true, true), shown("name", "m", "", true));
  }
}

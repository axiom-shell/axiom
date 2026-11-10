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

  function test_content() {
    const entry = {
      "name": "m",
      "icon": "ico",
      "text": "Magic"
    };
    compare(Scratchpads.content(entry, "m", "icon", true), {
      "kind": "text",
      "text": "ico"
    });
    compare(Scratchpads.content(null, "m", "icon", true), {
      "kind": "icons",
      "text": ""
    });
    compare(Scratchpads.content(null, "m", "icon", false), {
      "kind": "glyph",
      "text": "star"
    });
    compare(Scratchpads.content(entry, "m", "name", false), {
      "kind": "text",
      "text": "Magic"
    });
    compare(Scratchpads.content(null, "m", "name", false), {
      "kind": "name",
      "text": "m"
    });
  }
}

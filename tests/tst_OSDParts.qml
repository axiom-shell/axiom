import QtQuick
import QtTest
import qs.components.methods

// OSDParts: the row, the parts' order and their deadlines
TestCase {
  name: "OSDParts"

  // Tiles as OSDEngine.tileOf gives them, for the row
  function tile(on, hidden) {
    return {
      "on": on,
      "notable": on,
      "hidden": hidden === true
    };
  }

  function test_rowTypes() {
    const types = ["capsLock", "numLock", "dnd", "wifi"];
    const tiles = {
      "capsLock": tile(true),
      "numLock": tile(true),
      "dnd": tile(false),
      "wifi": tile(false, true)
    };
    compare(OSDParts.rowTypes(types, tiles, "notable", []), ["capsLock", "numLock"], "the lock keys on");
    compare(OSDParts.rowTypes(types, tiles, "notable", ["dnd"]), ["capsLock", "numLock", "dnd"], "the change, in its place");
    compare(OSDParts.rowTypes(types, tiles, "notable", ["wifi"]), ["capsLock", "numLock", "wifi"], "a hidden one as it changes");
    compare(OSDParts.rowTypes(types, tiles, "all", []), ["capsLock", "numLock", "dnd"], "not hidden ones");
    compare(OSDParts.rowTypes(types, tiles, "changed", ["numLock"]), ["numLock"]);
    compare(OSDParts.rowTypes(types, tiles, "changed", ["dnd", "numLock"]), ["numLock", "dnd"], "every one kept, in the OSD's order");
    compare(OSDParts.rowTypes(types, tiles, "changed", []), []);
    compare(OSDParts.rowTypes([], tiles, "all", []), []);
  }

  function test_partOrder() {
    compare(OSDParts.partOrder([], "level", false), ["level"]);
    compare(OSDParts.partOrder([], "status", false), ["status"]);
    compare(OSDParts.partOrder(["level"], "card", false), ["level", "card"], "the card always last");
    compare(OSDParts.partOrder(["level"], "status", false), ["level", "status"], "the icons past the bars");
    compare(OSDParts.partOrder(["status"], "level", false), ["level", "status"], "the bars by the edge, the icons moving out");
    compare(OSDParts.partOrder(["status", "card"], "level", false), ["level", "status", "card"], "the bars inside the icons and the card");
    compare(OSDParts.partOrder(["level"], "card", true), ["level", "card"], "holding still: the card past them all");
    compare(OSDParts.partOrder(["status"], "level", true), ["status", "level"], "holding still: the bars after the icons, nothing moving");
    compare(OSDParts.partOrder(["status", "card"], "level", true), ["status", "level", "card"], "holding still: after the box, still inside the card");
    compare(OSDParts.partOrder(["level", "status"], "status", false), ["level", "status"], "already shown");
    compare(OSDParts.partOrder(["status", "level"], "card", false), ["status", "level", "card"], "an order holding still left is kept");
    compare(OSDParts.partOrder(["level"], "status", false, true), ["status", "level"], "icons inside: by the edge, the bars moving out");
    compare(OSDParts.partOrder(["status"], "level", false, true), ["status", "level"], "icons inside: the bars past them");
    compare(OSDParts.partOrder(["level", "card"], "status", true, true), ["level", "status", "card"], "icons inside, holding still: after the bars");
  }

  function test_partsDue() {
    compare(OSDParts.partsDue({}, 1000, 750), {
      "due": [],
      "next": 0
    });
    compare(OSDParts.partsDue({
      "level": 1000,
      "card": 0
    }, 1000, 750), {
      "due": ["level"],
      "next": 0
    });
    compare(OSDParts.partsDue({
      "level": 1000,
      "card": 1500
    }, 1000, 750), {
      "due": [],
      "next": 1500
    }, "held for the card: they close together");
    compare(OSDParts.partsDue({
      "level": 1000,
      "card": 1500
    }, 1500, 750).due.sort(), ["card", "level"]);
    compare(OSDParts.partsDue({
      "level": 1000,
      "card": 3000
    }, 1000, 750), {
      "due": ["level"],
      "next": 3000
    }, "apart: each on its own");
  }

  function test_sharedDeadlines() {
    compare(OSDParts.sharedDeadlines({}), {});
    compare(OSDParts.sharedDeadlines({
      "level": 1000,
      "status": 2500,
      "card": 0
    }), {
      "level": 2500,
      "status": 2500,
      "card": 0
    }, "the bars and the icons share the latest");
    compare(OSDParts.sharedDeadlines({
      "level": 1000,
      "card": 4000
    }), {
      "level": 1000,
      "card": 4000
    }, "a card doesn't hold the bars");
    compare(OSDParts.sharedDeadlines({
      "level": 5000,
      "status": 3000,
      "card": 4000
    }), {
      "level": 5000,
      "status": 5000,
      "card": 4000
    }, "nor do they hold the card");
    compare(OSDParts.sharedDeadlines({
      "level": 0,
      "status": 3000
    }), {
      "level": 0,
      "status": 3000
    }, "a closed part stays closed");
  }
}

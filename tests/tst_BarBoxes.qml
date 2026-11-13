import QtQuick
import QtTest
import qs.components.methods

// A widget's items as boxes of their own (BarBoxes)
TestCase {
  name: "BarBoxes"

  function test_items_from_options() {
    const options = {
      "cpu": "showCpu",
      "mem": "showMemory",
      "gpu": "showGpu"
    };
    compare(BarBoxes.fromOptions(options, {
      "showCpu": true,
      "showMemory": false,
      "showGpu": true
    }), ["cpu", "gpu"]);
    // An option left out is off
    compare(BarBoxes.fromOptions(options, {}), []);
    compare(BarBoxes.fromOptions(null, {
      "showCpu": true
    }), []);
  }

  function test_sectionModel() {
    const itemsOf = e => e.type === "multi" ? ["a", "b"] : [];
    const m = BarBoxes.sectionModel([
      {
        "type": "time",
        "visible": false
      },
      {
        "type": "multi",
        "properties": {
          "x": 1
        }
      },
      {
        "type": "battery"
      }
    ], itemsOf);
    compare(m.length, 3);
    compare(m[0].type, "multi");
    compare(m[0].box, "a");
    compare(m[1].box, "b");
    compare(m[0].configIndex, 1);
    compare(m[2].type, "battery");
    compare(m[2].configIndex, 2);
    compare(m[2].properties, {});
    compare(m[2].autoColors, {});
    compare(m[2].layout, {});
    verify(Utils.deepEqual(JSON.parse(JSON.stringify(m)), m));
    compare(BarBoxes.sectionModel(undefined, itemsOf), []);
  }

  function test_expand_one_entry_per_item() {
    const entries = [
      {
        "id": "clock",
        "type": "Time",
        "configIndex": 0
      },
      {
        "id": "stats",
        "type": "LockKeys",
        "configIndex": 1
      }
    ];
    const out = BarBoxes.expand(entries, e => e.type === "LockKeys" ? ["caps", "num"] : []);
    compare(out.map(e => e.type), ["Time", "LockKeys", "LockKeys"]);
    compare(out.map(e => e.box ?? ""), ["", "caps", "num"]);
    // Still one widget to the bar editor
    compare(out.map(e => e.configIndex), [0, 1, 1]);
    // The entry itself is left as it was
    compare(entries[1].box, undefined);
  }

  function test_one_item_stays_whole() {
    const entries = [
      {
        "id": "stats",
        "configIndex": 0
      }
    ];
    compare(BarBoxes.expand(entries, () => ["cpu"]), entries);
    compare(BarBoxes.expand(entries, () => null), entries);
  }
}

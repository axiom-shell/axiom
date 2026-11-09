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

  function test_expand_one_entry_per_item() {
    const entries = [
      {
        "id": "clock",
        "type": "Time",
        "configIndex": 0
      },
      {
        "id": "stats",
        "type": "SystemStats",
        "configIndex": 1
      }
    ];
    const out = BarBoxes.expand(entries, e => e.type === "SystemStats" ? ["cpu", "mem"] : []);
    compare(out.map(e => e.type), ["Time", "SystemStats", "SystemStats"]);
    compare(out.map(e => e.box ?? ""), ["", "cpu", "mem"]);
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

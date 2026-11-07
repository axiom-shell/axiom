import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "DeviceBatteries"

  function dev(address, battery, connected) {
    return {
      "address": address,
      "battery": battery,
      "connected": connected !== false
    };
  }

  function test_level() {
    compare(DeviceBatteries.level(50, 20, 5), "none");
    compare(DeviceBatteries.level(20, 20, 5), "low", "at the level is low");
    compare(DeviceBatteries.level(5, 20, 5), "critical");
    compare(DeviceBatteries.level(0, 20, 5), "critical");
  }

  function test_start() {
    // The start (or a resync): taken as it is, never said
    const s = DeviceBatteries.step(null, [dev("A", 10), dev("B", 3), dev("C", -1), dev("D", 50, false)], 20, 5);
    compare(s.drops, []);
    compare(s.last, {
      "A": "low",
      "B": "critical"
    }, "no battery and disconnected left out");
  }

  function test_drops() {
    let last = DeviceBatteries.step(null, [dev("A", 30)], 20, 5).last;
    // Falling to low: once
    let s = DeviceBatteries.step(last, [dev("A", 20)], 20, 5);
    compare(s.drops, [
      {
        "address": "A",
        "level": "low"
      }
    ]);
    s = DeviceBatteries.step(s.last, [dev("A", 15)], 20, 5);
    compare(s.drops, [], "still low: said once");
    // Then critical: once
    s = DeviceBatteries.step(s.last, [dev("A", 5)], 20, 5);
    compare(s.drops, [
      {
        "address": "A",
        "level": "critical"
      }
    ]);
    s = DeviceBatteries.step(s.last, [dev("A", 6)], 20, 5);
    compare(s.drops, [], "back above critical but low: nothing");
    s = DeviceBatteries.step(s.last, [dev("A", 4)], 20, 5);
    compare(s.drops, [
      {
        "address": "A",
        "level": "critical"
      }
    ], "re-armed once it rose to low");
    // Straight from none to critical: critical alone
    s = DeviceBatteries.step({
      "B": "none"
    }, [dev("B", 2)], 20, 5);
    compare(s.drops, [
      {
        "address": "B",
        "level": "critical"
      }
    ]);
  }

  function test_rearmed() {
    let s = DeviceBatteries.step({
      "A": "low"
    }, [dev("A", 50)], 20, 5);
    compare(s.last, {
      "A": "none"
    });
    s = DeviceBatteries.step(s.last, [dev("A", 18)], 20, 5);
    compare(s.drops.length, 1, "recovered (charged), then low again: said again");

    // Disconnected: forgotten; connecting again while low says it
    s = DeviceBatteries.step(s.last, [dev("A", 18, false)], 20, 5);
    compare(s.last, {});
    s = DeviceBatteries.step(s.last, [dev("A", 18)], 20, 5);
    compare(s.drops, [
      {
        "address": "A",
        "level": "low"
      }
    ], "a reconnect while low");
    // A battery reported only now (it comes in after Connected)
    s = DeviceBatteries.step({}, [dev("C", -1)], 20, 5);
    s = DeviceBatteries.step(s.last, [dev("C", 12)], 20, 5);
    compare(s.drops.length, 1);
  }
}

import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "DndHold"

  function test_on() {
    compare(DndHold.on(true, false, false), true, "manual on");
    compare(DndHold.on(false, true, false), true, "held, not overridden");
    compare(DndHold.on(false, true, true), false, "held and overridden");
    compare(DndHold.on(false, false, false), false, "nothing held");
    compare(DndHold.on(true, true, true), true, "manual on and overridden");
  }

  function test_byHand() {
    compare(DndHold.byHand(false, true, false), {
      "manual": false,
      "override": true
    }, "off while a rule holds it overrides");
    compare(DndHold.byHand(false, true, true), {
      "manual": false,
      "override": false
    }, "off while already overridden");
    compare(DndHold.byHand(false, false, false), {
      "manual": false,
      "override": false
    }, "off with nothing held");
    compare(DndHold.byHand(true, true, false), {
      "manual": true,
      "override": false
    }, "on is yours and stays after the rule");
  }
}

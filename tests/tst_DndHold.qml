import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "DndHold"

  function test_on() {
    for (let bits = 0; bits < 8; bits++) {
      const manual = (bits & 1) !== 0, held = (bits & 2) !== 0, overridden = (bits & 4) !== 0;
      compare(DndHold.on(manual, held, overridden), manual || (held && !overridden), `manual ${manual} held ${held} overridden ${overridden}`);
    }
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

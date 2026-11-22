import QtQuick
import QtTest
import qs.components.methods

// The painter's order of the backing window's shapes (PaintOrder)
TestCase {
  name: "PaintOrder"

  function test_order() {
    const names = ["base", "frame", "bar", "merge", "surface", "submenu", "toast"];
    for (let i = 1; i < names.length; i++)
      verify(PaintOrder.of(names[i - 1]) < PaintOrder.of(names[i]), names[i - 1] + " under " + names[i]);
    compare(PaintOrder.levels.map(l => l.name), names);
  }

  function test_every_level_says_why() {
    for (const l of PaintOrder.levels) {
      verify(l.why.length > 0, l.name + " has no why");
      verify(Number.isInteger(l.level), l.name + " level is not an integer");
    }
  }

  function test_unknown_name_is_nan() {
    verify(isNaN(PaintOrder.of("nowhere")));
  }

  // An eraser never sits on a shape's level, so it ties only with erasers
  function test_erasers_never_on_a_level() {
    const levels = PaintOrder.levels.map(l => l.level);
    for (const level of levels) {
      const at = level - PaintOrder.eraserOffset;
      verify(!Number.isInteger(at), "eraser at " + at);
      verify(!levels.includes(at));
    }
  }
}

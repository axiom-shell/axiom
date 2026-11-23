import QtQuick
import QtTest
import qs.components.methods

// The painter's order of the backing window's shapes (PaintOrder)
TestCase {
  name: "PaintOrder"

  function test_order() {
    const names = ["base", "frame", "bar", "cornerJoin", "surface", "submenu", "toast"];
    for (let i = 1; i < names.length; i++)
      verify(PaintOrder.rankOf(names[i - 1]) < PaintOrder.rankOf(names[i]), names[i - 1] + " under " + names[i]);
    compare(PaintOrder.ranks.map(r => r.name), names);
  }

  function test_every_rank_says_why() {
    for (const r of PaintOrder.ranks) {
      verify(r.why.length > 0, r.name + " has no why");
      verify(Number.isInteger(r.rank), r.name + " rank is not an integer");
    }
  }

  function test_unknown_name_is_nan() {
    verify(isNaN(PaintOrder.rankOf("nowhere")));
  }

  // An eraser never sits on a shape's rank, so it ties only with erasers
  function test_erasers_never_on_a_rank() {
    const ranks = PaintOrder.ranks.map(r => r.rank);
    for (const rank of ranks) {
      const at = rank - PaintOrder.eraserOffset;
      verify(!Number.isInteger(at), "eraser at " + at);
      verify(!ranks.includes(at));
    }
  }
}

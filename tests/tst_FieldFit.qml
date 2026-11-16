import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "FieldFit"

  readonly property var t: ({
      "gap": 8,
      "labelLeast": 160,
      "controlLeast": 120,
      "controlMax": 260,
      "controlShare": 0.42,
      "inlineFrom": 420
    })

  function test_switch_is_always_beside() {
    const p = FieldFit.place("switch", 200, 300, 40, t);
    verify(p.inline);
  }

  function test_fixed_fits_beside_a_short_label() {
    const p = FieldFit.place("fixed", 300, 35, 142, t);
    verify(p.inline);
    verify(p.notesBelow, "narrow: the description goes under the line");
    compare(p.align, "end");
  }

  function test_fixed_stacks_under_a_long_label() {
    verify(!FieldFit.place("fixed", 300, 200, 142, t).inline, "142 + 8 + 160 = 310");
  }

  function test_fixed_edge() {
    verify(!FieldFit.place("fixed", 184, 35, 142, t).inline);
    verify(FieldFit.place("fixed", 185, 35, 142, t).inline);
  }

  function test_flex_narrow_short_label() {
    const p = FieldFit.place("flex", 300, 40, 0, t);
    verify(p.inline);
    compare(p.controlWidth, 126);
    verify(p.notesBelow);
    verify(!p.fill);
  }

  function test_flex_stacks_when_the_label_does_not_fit() {
    verify(!FieldFit.place("flex", 250, 140, 0, t).inline, "120 + 8 + 140 = 268");
  }

  function test_flex_long_label_wraps_beside() {
    verify(FieldFit.place("flex", 300, 300, 0, t).inline, "160 + 8 + 126 = 294");
  }

  function test_flex_wide_is_todays_width() {
    const p = FieldFit.place("flex", 540, 40, 0, t);
    verify(p.inline);
    compare(p.controlWidth, 227);
    verify(!p.notesBelow);
  }

  function test_flex_without_label_stacks_and_fills() {
    const p = FieldFit.place("flex", 540, 0, 0, t);
    verify(!p.inline);
    verify(p.fill);
    compare(p.controlWidth, -1);
  }

  function test_slider_needs_travel() {
    verify(!FieldFit.place("slider", 300, 40, 0, t).inline);
    const p = FieldFit.place("slider", 420, 40, 0, t);
    verify(p.inline);
    compare(p.controlWidth, 176);
  }

  function test_fill_and_block() {
    const f = FieldFit.place("fill", 300, 40, 0, t);
    verify(f.inline);
    compare(f.controlWidth, -1);
    verify(f.fill);
    const b = FieldFit.place("block", 540, 40, 0, t);
    verify(!b.inline);
    verify(b.fill);
  }

  function test_fixed_without_label_sits_at_the_end() {
    const p = FieldFit.place("fixed", 300, 0, 142, t);
    verify(!p.inline);
    compare(p.align, "end");
  }

  function test_stacked_fixed_starts() {
    compare(FieldFit.place("fixed", 300, 200, 142, t).align, "start");
  }

  function test_zero_width() {
    verify(!FieldFit.place("flex", 0, 40, 0, t).inline);
    verify(!FieldFit.place("switch", 0, 40, 0, t).inline);
  }

  function test_least() {
    compare(FieldFit.least("fixed", 40, 142, t), 142);
    compare(FieldFit.least("flex", 40, 0, t), 120);
    compare(FieldFit.least("switch", 60, 40, t), 108);
  }

  function test_pair_fits() {
    verify(!FieldFit.pairFits(280, 8, 120, 142), "136 < 142");
    verify(FieldFit.pairFits(300, 8, 120, 120));
    verify(FieldFit.pairFits(540, 8, 120, 142));
  }
}

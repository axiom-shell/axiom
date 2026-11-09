import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "TextBand"

  function test_onXHeight() {
    verify(TextBand.onXHeight("gaming"));
    verify(TextBand.onXHeight("Gaming"), "a capital among lowercase sits as the lowercase does");
    verify(TextBand.onXHeight("vpn.batk.me"));
    verify(TextBand.onXHeight("Mon 12:30"));
    verify(!TextBand.onXHeight("12:30"), "figures centre on their own height");
    verify(!TextBand.onXHeight("00%"));
    verify(!TextBand.onXHeight("CPU"));
    verify(!TextBand.onXHeight("—"));
    verify(!TextBand.onXHeight("音楽"), "a script without case");
    verify(!TextBand.onXHeight(""));
  }

  function test_height() {
    compare(TextBand.height("gaming", 8, 11), 8);
    compare(TextBand.height("Gaming", 8, 11), 8, "the same band as without the capital: it doesn't move");
    compare(TextBand.height("gym", 8, 11), 8, "descenders don't move it either");
    compare(TextBand.height("12:30", 8, 11), 11);
  }

  function test_padding() {
    // Inter at 15 px: ascent 14.53, a 19 px line, x-height 8, figures 11
    const x = TextBand.padding(14.53125, 19, 8);
    compare(x.top, -1, "lowercase moves up, by whole pixels");
    compare(x.bottom, 1);
    compare(x.top + x.bottom, 0, "the Text keeps its size");
    fuzzyCompare(x.offset, 0.03125, 0.0001, "the band's middle is left that far below the box's");
    // The box's middle is then the band's (4 px above the baseline), but
    // for the offset
    fuzzyCompare(19 / 2 + x.offset, x.top + 14.53125 - 4, 0.0001);
    const figures = TextBand.padding(14.53125, 19, 11);
    compare(figures.top, 0, "under half a pixel off: not moved");
    compare(figures.bottom, 0);
    fuzzyCompare(figures.offset, -0.46875, 0.0001, "the band's middle is above the box's");
    fuzzyCompare(19 / 2 + figures.offset, figures.top + 14.53125 - 5.5, 0.0001);
    // Inter at 20 px: ascent 19.375, a 25 px line, figures 15
    const big = TextBand.padding(19.375, 25, 15);
    compare(big.top, 1, "figures more than half a pixel high move down a whole one");
    compare(big.bottom, -1);
    fuzzyCompare(big.offset, 0.375, 0.0001);
    compare(TextBand.padding(10, 14, 6), {
      "top": 0,
      "bottom": 0,
      "offset": 0
    }, "already centred");
    // Two lines (38 px): the first band's top to the last baseline,
    // 14.53 - 8 to 19 + 14.53, centred in the box but for the offset
    const two = TextBand.padding(14.53125, 19, 8);
    fuzzyCompare((two.top + 14.53125 - 8 + two.top + 19 + 14.53125) / 2, 38 / 2 + two.offset, 0.0001, "two lines centre as a block");
  }
}

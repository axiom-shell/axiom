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
    compare(x.top, 0);
    fuzzyCompare(x.bottom, 2.0625, 0.0001, "the box grows below, so its middle rises to the x-height's");
    // The box's middle is then the band's: 4 px above the baseline
    fuzzyCompare((19 + x.bottom) / 2, 14.53125 - 4, 0.0001);
    const figures = TextBand.padding(14.53125, 19, 11);
    compare(figures.top, 0.9375, "a band taller than the box's middle grows it above");
    compare(figures.bottom, 0);
    compare(TextBand.padding(10, 14, 6), {
      "top": 0,
      "bottom": 0
    }, "already centred");
  }
}

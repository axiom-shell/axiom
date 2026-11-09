import QtQuick
import QtTest
import qs.components.methods

// A display style's graphic: the style it draws as, and how far across the
// bar it reaches (ValueGraphics)
TestCase {
  name: "ValueGraphics"

  function test_resolved_style() {
    compare(ValueGraphics.resolvedStyle("stacked", true, true, 0.5), "label", "stacked on a vertical bar");
    compare(ValueGraphics.resolvedStyle("stacked", false, true, 0.5), "stacked");
    compare(ValueGraphics.resolvedStyle("sparkline", false, false, 0.5), "fill", "no history");
    compare(ValueGraphics.resolvedStyle("sparkline", false, false, -1), "label", "no history, no value");
    compare(ValueGraphics.resolvedStyle("ring", false, true, -1), "label", "no value");
    compare(ValueGraphics.resolvedStyle("ticker", false, false, -1), "ticker", "a ticker needs none");
  }

  function test_stacked_fit() {
    compare(ValueGraphics.stackedFit(30, 14), 1, "fits a 30 px bar at 14 px");
    fuzzyCompare(ValueGraphics.stackedFit(20, 14), 20 / (1.68 * 14), 1e-9, "shrinks on a thin bar");
    compare(ValueGraphics.stackedFit(0, 14), 1, "no size known");
  }

  function test_across() {
    // A 26 px bar at a 14 px font
    fuzzyCompare(ValueGraphics.across("ring", false, 26, 14), 16.12, 1e-9, "the ring: 0.62 of the thickness");
    fuzzyCompare(ValueGraphics.across("ring", true, 26, 14), 16.12, 1e-9, "on a vertical bar too");
    fuzzyCompare(ValueGraphics.across("sparkline", false, 26, 14), 15.6, 1e-9, "the sparkline: inset 0.2 either side");
    compare(ValueGraphics.across("sparkline", true, 26, 14), 26, "inset along a vertical bar: the whole thickness across");
    fuzzyCompare(ValueGraphics.across("stacked", false, 30, 14), 23.52, 1e-9, "stacked: two lines, 1.68 of the font");
    fuzzyCompare(ValueGraphics.across("stacked", false, 20, 14), 20, 1e-9, "fitted to a thin bar: its thickness");
    for (const style of ["label", "icon", "fill", "segments", "pill", "ticker", ""])
      compare(ValueGraphics.across(style, false, 26, 14), 0, `${style}: a line at most`);
  }
}

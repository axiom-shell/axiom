pragma ComponentBehavior: Bound
import QtQuick
import qs.components.methods

// The padding that centres a Text on its letters' band (TextBand: the
// x-height with lowercase in it, a figure's height without) rather than on
// its line box, so anything placing the Text by its box (centred in a cell,
// a row, a pill or a button, beside an icon, turned along a vertical bar)
// centres what reads. It moves the lines inside the box, by whole pixels,
// and keeps the box's size (one side's padding is the other's negative).
// Bind the Text's topPadding / bottomPadding to `top` / `bottom`
// (StyledLabel does), and where the host places the Text itself, take
// `offset` off its position before rounding it:
//   readonly property TextBandPadding _band: TextBandPadding { font: label.font; text: label.text; contentHeight: label.contentHeight }
QtObject {
  id: root

  // The Text's font, its text as it reads (plain: styled text's tags left
  // out), its contentHeight (its lines, padding left out) and its lineCount
  property font font
  property string text: ""
  property real contentHeight: 0
  property int lineCount: 1
  // Off: no padding (a Text that's drawn as an icon at times)
  property bool enabled: true

  readonly property var _padding: TextBand.padding(_fontMetrics.ascent, root.contentHeight / Math.max(1, root.lineCount), TextBand.height(root.text, _x.tightBoundingRect.height, _figure.tightBoundingRect.height))
  readonly property real top: root.enabled && root.text !== "" ? root._padding.top : 0
  readonly property real bottom: root.enabled && root.text !== "" ? root._padding.bottom : 0
  // How far the band's middle is left below the box's (under half a pixel:
  // the lines move by whole ones)
  readonly property real offset: root.enabled && root.text !== "" ? root._padding.offset : 0

  // The bands as drawn at this size (hinted, whole pixels)
  readonly property FontMetrics _fontMetrics: FontMetrics {
    font: root.font
  }
  readonly property TextMetrics _x: TextMetrics {
    font: root.font
    text: "x"
  }
  readonly property TextMetrics _figure: TextMetrics {
    font: root.font
    text: "0"
  }
}

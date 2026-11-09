pragma ComponentBehavior: Bound
import QtQuick
import qs.components.methods

// The padding that centres a Text on its letters' band (TextBand: the
// x-height with lowercase in it, a figure's height without) rather than on
// its line box, so anything placing the Text by its box (centred in a cell,
// a row, a pill or a button, beside an icon, turned along a vertical bar)
// centres what reads. It moves the lines inside the box, by whole pixels,
// and keeps the box's size (one side's padding is the other's negative).
// Set `label` to the Text and bind its topPadding / bottomPadding to
// `top` / `bottom` (StyledLabel does), and where the host places the Text
// itself, take `offset` off its position before rounding it:
//   readonly property TextBandPadding _band: TextBandPadding { label: textLabel; text: textLabel.text }
QtObject {
  id: root

  // The Text it pads, and its text as it reads (plain: styled text's tags
  // left out)
  required property Text label
  property string text: ""
  // The text whose case picks the band: its own, or its line's where it
  // shares one with another Text
  property string bandText: root.text
  // Off: no padding (a Text that's drawn as an icon at times)
  property bool enabled: true

  readonly property var _padding: TextBand.padding(root._line.ascent, root._line.height, TextBand.height(root.bandText, _x.tightBoundingRect.height, _figure.tightBoundingRect.height))
  readonly property real top: root.enabled && root.text !== "" ? root._padding.top : 0
  readonly property real bottom: root.enabled && root.text !== "" ? root._padding.bottom : 0
  // How far the band's middle is left below the box's (under half a pixel:
  // the lines move by whole ones)
  readonly property real offset: root.enabled && root.text !== "" ? root._padding.offset : 0

  // The label's first line's ascent as laid out (TextBand.lineAscent: a
  // fallback font's taller one moves its baseline down) and one line's
  // height, read off it once each layout is done. Not bound: its
  // baselineOffset holds the padding this sets, so a binding through it
  // loops, and nor are they read in its layout's signals, which come
  // while it lays out (its contentHeight not yet new) and again inside
  // the padding's own write. Both are set at once, only when one changes,
  // so the padding moves once, and the layout that causes sets nothing
  property var _line: ({
      "ascent": 0,
      "height": 0
    })

  function _measure() {
    const label = root.label;
    const ascent = TextBand.lineAscent(label.baselineOffset, label.topPadding, label.bottomPadding, label.height, label.contentHeight, label.verticalAlignment);
    const height = label.contentHeight / Math.max(1, label.lineCount);
    if (ascent !== root._line.ascent || height !== root._line.height)
      root._line = {
        "ascent": ascent,
        "height": height
      };
  }

  readonly property Connections _layout: Connections {
    target: root.label

    function onBaselineOffsetChanged() {
      Qt.callLater(root._measure);
    }
    function onContentHeightChanged() {
      Qt.callLater(root._measure);
    }
    function onLineCountChanged() {
      Qt.callLater(root._measure);
    }
    function onHeightChanged() {
      Qt.callLater(root._measure);
    }
    function onVerticalAlignmentChanged() {
      Qt.callLater(root._measure);
    }
  }

  // The bands as drawn at this size (hinted, whole pixels)
  readonly property TextMetrics _x: TextMetrics {
    font: root.label.font
    text: "x"
  }
  readonly property TextMetrics _figure: TextMetrics {
    font: root.label.font
    text: "0"
  }

  Component.onCompleted: Qt.callLater(root._measure)
}

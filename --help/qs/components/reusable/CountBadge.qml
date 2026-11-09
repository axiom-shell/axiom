pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// A small pill holding a count (or any short label), for a button's or
// an icon's corner: StyledRectButton's badge, the notification bell's.
// Pops in and out by `shown`, and bumps when its count changes.
PopInRectangle {
  id: root

  property string text: ""
  property color textColor: Theme.background
  // Its size follows: a bar's badge takes the bar's text size
  property int textSize: Appearance.fontSizeBy(-4)

  // Each side a pixel longer when its parity differs from the ink's, so
  // the ink's centre lands on a whole pixel (half a pixel off leans the
  // count by one)
  implicitWidth: _evenTo(Math.max(_baseHeight, Math.ceil(label.implicitWidth) + Math.round(textSize * 0.6)), _inkWidth)
  implicitHeight: _evenTo(_baseHeight, _inkHeight)
  radius: height / 2
  color: Theme.error
  onTextChanged: pulse()

  // The glyphs' own box, from the baseline: the line's ascent and descent
  // aren't even about the digits, so centring the text's line box left
  // the count off centre
  TextMetrics {
    id: ink
    font: label.font
    text: root.text
  }

  readonly property int _baseHeight: Math.round(textSize * 1.4)
  readonly property int _inkWidth: Math.round(ink.tightBoundingRect.width)
  readonly property int _inkHeight: Math.round(ink.tightBoundingRect.height)

  function _evenTo(size: int, inkSize: int): int {
    return (size - inkSize) % 2 === 0 ? size : size + 1;
  }

  // Placed by its ink, at whole pixels: the ink's left and top edges sit
  // (side - ink) / 2 in, a whole number by the parity above. The line's
  // ascent can be fractional, so the baseline is what's put on a whole
  // pixel, not the line's top
  StyledText {
    id: label
    x: Math.round((root.width - root._inkWidth) / 2 - ink.tightBoundingRect.x)
    y: Math.round((root.height - root._inkHeight) / 2 - ink.tightBoundingRect.y) - label.baselineOffset
    text: root.text
    textSize: root.textSize
    textColor: root.textColor
  }
}

pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// Text in the shell's font, size and foreground color; optionally turned
// for a vertical bar.
Text {
  id: root

  // -- Public API --
  property bool isVertical: false

  // -- Configurable Appearance --
  property color textColor: Theme.foreground
  property string textFamily: Appearance.fontFamily
  property int textSize: Appearance.fontSize

  // -- Implementation --
  color: textColor
  rotation: isVertical ? -90 : 0
  font.family: textFamily
  font.pixelSize: textSize
}

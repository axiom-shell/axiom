pragma ComponentBehavior: Bound
import QtQuick

// A StyledText centred on its letters (TextBandPadding) rather than on its
// line box, which holds the descent and sits lowercase a pixel or two low:
// a label placed by its box, beside an icon or centred in a pill, chip,
// button or row. Its size is a StyledText's (the padding only moves its
// lines, by whole pixels), and wrapped it centres its lines as a block.
// Centred by anchors, it takes the half pixel the lines couldn't move off
// its place too; a host placing it by hand reads `bandOffset`.
StyledText {
  id: root

  readonly property TextBandPadding _band: TextBandPadding {
    label: root
    text: root.textFormat === Text.PlainText ? root.text : root.text.replace(/<[^>]*>/g, "")
  }
  // How far its letters' middle is below its box's (under half a pixel)
  readonly property real bandOffset: _band.offset

  topPadding: _band.top
  bottomPadding: _band.bottom
  anchors.verticalCenterOffset: -_band.offset
}

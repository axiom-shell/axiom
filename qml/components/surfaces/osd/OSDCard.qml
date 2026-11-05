pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.components.reusable

// The frame of an OSD's cards (OSDMediaCard, OSDStatusCard): a square
// picture on the left (`picture`), a title and a faint line under it,
// and optionally an icon at the end saying what it's doing.
Item {
  id: root

  // The square on the left (a cover, a device's icon)
  property Component picture
  property string title: ""
  property string subtitle: ""
  // An icon at the end, or "" for none
  property string status: ""

  readonly property int pictureSize: Widget.px(48)
  // The text's width: its own, the longer line's, between a least (a
  // short title doesn't make a stub of a card) and a most (past it the
  // title ends in "…" and the faint line wraps). A Text's implicit width
  // ignores its eliding and wrapping, so this reads the lines' own widths
  // (the subtitle's by its text, not its `visible`, which reads false
  // while the card's slot is folded)
  readonly property int minTextWidth: Widget.px(160)
  readonly property int maxTextWidth: Widget.px(400)
  readonly property int textWidth: Math.round(Math.max(root.minTextWidth, Math.min(root.maxTextWidth, Math.max(titleText.implicitWidth, root.subtitle !== "" ? subtitleText.implicitWidth : 0))))
  // The most lines the faint line wraps to (the last ends in "…")
  readonly property int subtitleLines: 3
  // Its least height (one faint line), and the margin above and below
  // what shows (the picture, or the text when it's taller)
  readonly property int _minHeight: Widget.px(64)
  readonly property real _margin: (root._minHeight - root.pictureSize) / 2
  // The text's height: one title line and the faint line as it wraps
  // (read by its text, not its `visible`, as textWidth does)
  readonly property real _textHeight: titleText.implicitHeight + (root.subtitle !== "" ? subtitleText.implicitHeight : 0)
  // The empty margin round what shows across `vertical` edges' depth
  // (its width) or else its height (round the picture or the text): a
  // host spacing it by what shows reads it
  function inset(vertical) {
    return vertical ? Widget.spacing * 2 : (root.implicitHeight - Math.max(root.pictureSize, root._textHeight)) / 2;
  }
  // Its width with the text at its most, and its height with the faint
  // line wrapped to its most lines
  readonly property real maxWidth: root.implicitWidth - root.textWidth + root.maxTextWidth
  readonly property real maxHeight: Math.max(root._minHeight, Math.ceil(titleText.implicitHeight + subtitleMetrics.height * root.subtitleLines + root._margin * 2))
  // What shows across `vertical` edges' depth at its largest, margins left
  // out: the room a host keeps for it
  function maxShown(vertical) {
    return vertical ? root.maxWidth - root.inset(true) * 2 : root.maxHeight - root._margin * 2;
  }

  implicitWidth: row.implicitWidth + Widget.spacing * 4
  implicitHeight: Math.max(root._minHeight, Math.ceil(root._textHeight + root._margin * 2))

  FontMetrics {
    id: subtitleMetrics
    font: subtitleText.font
  }

  RowLayout {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: parent.left
    anchors.leftMargin: Widget.spacing * 2
    spacing: Widget.spacing * 3

    Loader {
      Layout.preferredWidth: root.pictureSize
      Layout.preferredHeight: root.pictureSize
      sourceComponent: root.picture
    }

    // A Column, not a Layout: the faint line wraps at the text's width,
    // set here, so its height holds while the card's slot is folded
    Column {
      Layout.preferredWidth: root.textWidth
      Layout.preferredHeight: root._textHeight

      StyledText {
        id: titleText
        width: root.textWidth
        text: root.title
        textSize: Appearance.fontSizeLarge
        font.weight: Font.Medium
        elide: Text.ElideRight
        maximumLineCount: 1
      }

      StyledText {
        id: subtitleText
        width: root.textWidth
        text: root.subtitle
        textColor: Theme.foregroundAlt
        wrapMode: Text.Wrap
        elide: Text.ElideRight
        maximumLineCount: root.subtitleLines
        visible: text !== ""
      }
    }

    StyledIcon {
      Layout.alignment: Qt.AlignVCenter
      visible: root.status !== ""
      text: root.status
      textSize: Appearance.fontSizeBy(8)
    }
  }
}

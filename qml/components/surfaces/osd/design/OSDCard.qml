pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import Quickshell.Widgets

import qs.config
import qs.components.reusable

// An OSD's card: a square picture on the left, a title and a faint line
// under it, and optionally an icon at the end saying what it's doing.
// Shows a system's card (`card`, OSDEngine.cardOf's: its icon on the
// accent, or on the warning colour with `tone` "warning", or its `image`
// cropped in its place; the title; its role, translated, and its detail
// as the faint line), and takes a click when it's `clickable`. A system's
// own card design (systems/<Type>/design/, Now playing's) is one of these
// setting its `title`, `subtitle`, `status` and `picture` itself.
Item {
  id: root

  // The card shown (OSDEngine.cardOf's), null for none; and the change
  // that brought it (for a design of a system's own)
  property var card: null
  property var change: null

  // A click on a card that takes one (card.clickable)
  signal clicked

  // Its role as its system gives it, English (declared there),
  // translated here
  readonly property string _role: (root.card?.role ?? "") !== "" ? I18n.tr(root.card.role) : ""

  // The square on the left (a cover, a device's icon)
  property Component picture: cardPicture
  property string title: root.card?.title ?? ""
  property string subtitle: [root._role, root.card?.detail ?? ""].filter(part => part !== "").join(" · ")
  // An icon at the end, or "" for none
  property string status: ""

  readonly property int pictureSize: Widget.px(48)
  // The text's width: its own, the longer line's, between a least (a
  // short title doesn't make a stub of a card) and a most (past it the
  // title ends in "…" and the faint line wraps). A Text's implicit width
  // ignores its eliding, so this reads the title's own; the faint line's
  // is measured from its text by the font (a wrapping Text's implicit
  // width followed its wrapped lines, so the card stayed as narrow as the
  // title and the line wrapped at that). Both read the text, not
  // `visible`, which reads false while the card's slot is folded
  readonly property int minTextWidth: Widget.px(160)
  readonly property int maxTextWidth: Widget.px(400)
  readonly property int textWidth: Math.round(Math.max(root.minTextWidth, Math.min(root.maxTextWidth, Math.max(titleText.implicitWidth, root.subtitle !== "" ? Math.ceil(subtitleMetrics.advanceWidth(root.subtitle)) : 0))))
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
  // line wrapped to its most lines (a Text's line is its font's height
  // rounded up)
  readonly property real maxWidth: root.implicitWidth - root.textWidth + root.maxTextWidth
  readonly property real maxHeight: Math.max(root._minHeight, Math.ceil(titleText.implicitHeight + Math.ceil(subtitleMetrics.height) * root.subtitleLines + root._margin * 2))
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
        // A zero-width break after each / - _, so a path or an id wraps
        // to fill the line: line breaking allows none before a digit
        // ("9a5f-200d" stayed whole and went to the next line)
        text: root.subtitle.replace(/([\/_-])/g, "$1\u200B")
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

  // A card's own picture: its icon on the accent (the warning colour for
  // a refusal or a critical battery), or its image cropped to the square
  Component {
    id: cardPicture

    Rectangle {
      radius: Widget.radius
      color: root.card?.tone === "warning" ? Theme.warning : Theme.accent

      StyledIcon {
        anchors.centerIn: parent
        visible: !shot.visible
        text: root.card?.icon ?? ""
        textSize: Appearance.fontSizeBy(8)
        textColor: Theme.background
      }

      // A picture in its place (a screenshot's), cropped to the square
      ClippingRectangle {
        id: shot
        anchors.fill: parent
        radius: Widget.radius
        color: Theme.backgroundAlt
        visible: (root.card?.image ?? "") !== ""

        Image {
          anchors.fill: parent
          source: root.card?.image ?? ""
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          // Decoded at its size, not the screen's
          sourceSize.width: root.pictureSize * 2
          sourceSize.height: root.pictureSize * 2
        }
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    enabled: root.card?.clickable === true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}

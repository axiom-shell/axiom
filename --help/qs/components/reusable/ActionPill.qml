pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell

import qs.config

// A wide action or toggle tile, as in Android's quick settings: an icon
// well beside a name and a status line. Coloured as ActionTile is
// (`active` fills it with `activeColor`, hover takes `tone`, `countdown`
// runs a bar down). With `opens`, the well toggles (`clicked`) and the
// rest opens the detail (`opened`), marked by a chevron; without, the whole
// pill is `clicked`.
Rectangle {
  id: root

  property string icon: ""
  property string label: ""
  property string status: ""
  property bool active: false
  property color activeColor: Theme.accent
  property color tone: root.activeColor
  property int countdown: 0
  // There's a detail to open
  property bool opens: false

  signal clicked
  signal opened

  readonly property bool hot: area.containsMouse || wellArea.containsMouse
  readonly property color contentColor: root.active ? Theme.background : root.hot ? root.tone : Theme.foreground
  readonly property real _wellSize: Math.max(0, Math.min(root.height - Widget.spacing * 2, Appearance.fontSize * 2.6))
  // Room for the name beside the well
  readonly property bool _textShown: root.width - root._wellSize - Widget.spacing * 3 >= Appearance.fontSize * 3
  // Lines wrap where the pill already has the height (it never grows for
  // them): the name takes up to two, leaving the status one, and the
  // status what's left after the name's, three lines in all
  readonly property real _room: root.height - Widget.spacing * 2
  readonly property bool _statusShown: root.status !== "" && root.height >= Appearance.fontSize * 3
  readonly property int _nameLines: Math.max(1, Math.min(2, Math.floor((root._room - (root._statusShown ? statusMetrics.height : 0)) / nameMetrics.height)))
  readonly property int _statusLines: Math.max(1, Math.min(3 - nameText.lineCount, Math.floor((root._room - nameText.lineCount * nameMetrics.height) / statusMetrics.height)))

  radius: Widget.radius
  color: Appearance.fill(root.active ? root.activeColor : root.hot ? Theme.backgroundHighlight : Theme.backgroundAlt)
  border.color: root.active ? root.activeColor : root.hot ? root.tone : Theme.border
  border.width: Appearance.borderWidth
  clip: true

  ColorGlide on color {}
  ColorGlide on border.color {}

  // The rest of the pill: opens, or toggles without a detail
  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.opens ? root.opened() : root.clicked()
  }

  RowLayout {
    anchors.fill: parent
    anchors.margins: Widget.spacing
    spacing: Widget.spacing

    Rectangle {
      id: well
      Layout.preferredWidth: root._wellSize
      Layout.preferredHeight: root._wellSize
      Layout.alignment: Qt.AlignVCenter
      Layout.fillWidth: !root._textShown
      radius: Math.min(Widget.radius * 1.5, width / 2)
      color: root.active ? Qt.rgba(0, 0, 0, 0.12) : wellArea.containsMouse ? Qt.alpha(root.tone, 0.16) : Appearance.fill(Theme.background)

      ColorGlide on color {}

      StyledIcon {
        anchors.centerIn: parent
        text: root.icon
        textColor: root.contentColor
        textSize: Math.min(well.width, well.height) * 0.5
        fill: root.hot || root.active ? 1 : 0
      }

      // The well toggles
      MouseArea {
        id: wellArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
      }
    }

    ColumnLayout {
      visible: root._textShown
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
      spacing: 0

      StyledText {
        id: nameText
        Layout.fillWidth: true
        text: root.label
        wrapMode: root._nameLines > 1 ? Text.Wrap : Text.NoWrap
        maximumLineCount: root._nameLines
        elide: Text.ElideRight
        font.bold: true
        textColor: root.contentColor
        textSize: Appearance.fontSizeBy(-1)
      }
      StyledText {
        id: statusText
        Layout.fillWidth: true
        visible: root._statusShown
        text: root.status
        wrapMode: root._statusLines > 1 ? Text.Wrap : Text.NoWrap
        maximumLineCount: root._statusLines
        elide: Text.ElideRight
        textColor: root.contentColor
        opacity: 0.75
        textSize: Appearance.fontSizeBy(-2)
      }
    }

    FontMetrics {
      id: nameMetrics
      font: nameText.font
    }
    FontMetrics {
      id: statusMetrics
      font: statusText.font
    }

    StyledIcon {
      visible: root.opens && root._textShown
      text: "chevron_right"
      textColor: root.contentColor
      opacity: 0.75
    }
  }

  // Time left while active
  CountdownBar {
    running: root.active
    duration: root.countdown
  }

  LazyLoader {
    active: root.hot && !root._textShown && root.label !== ""
    StyledToolTip {
      target: root
      text: root.label
    }
  }
}

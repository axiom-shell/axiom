pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell

import qs.config

// A wide action or toggle tile, as in Android's quick settings: an icon
// well beside a name and a status line. Coloured as ActionTile is
// (`active` fills it with the `activeTone`, hover gives its well the
// tone's container, `countdown` runs a bar down). With `opens`, the well toggles (`clicked`) and the
// rest opens the detail (`opened`), marked by a chevron; without, the whole
// pill is `clicked`.
Rectangle {
  id: root

  property string icon: ""
  property string label: ""
  property string status: ""
  property bool active: false
  // accent | error: the fill while active, and the container the well takes
  // while hovered
  property string activeTone: "accent"
  property int countdown: 0
  // There's a detail to open
  property bool opens: false

  signal clicked
  signal opened

  readonly property bool hot: area.containsMouse || wellArea.containsMouse
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

  ActionTone {
    id: actionTone
    activeTone: root.activeTone
    active: root.active
    hot: root.hot
  }

  radius: Style.radius
  color: root.active ? actionTone.activeColor : Style.fill
  border.color: root.active || root.hot ? actionTone.activeColor : Style.borderSubtle
  border.width: Style.hairline
  clip: true

  ColorGlide on color {}
  ColorGlide on border.color {}

  StateLayer {
    hovered: root.hot
    pressed: area.pressed
    onAccent: root.active
  }

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
      radius: actionTone.wellRadius(width)
      color: root.active ? Style.stateOnAccentHover : wellArea.containsMouse ? actionTone.containerFill : Style.surfaceHighest

      ColorGlide on color {}

      StyledIcon {
        anchors.centerIn: parent
        text: root.icon
        textColor: actionTone.contentColor
        textSize: Math.max(Style.iconXs, Math.min(well.width, well.height) * 0.5) // fitted: the glyph is half its well
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

      StyledLabel {
        id: nameText
        Layout.fillWidth: true
        text: root.label
        role: "label"
        overflow: "wrap"
        maxLines: root._nameLines
        textColor: actionTone.labelColor
      }
      StyledLabel {
        id: statusText
        Layout.fillWidth: true
        visible: root._statusShown
        text: root.status
        role: "caption"
        overflow: "wrap"
        maxLines: root._statusLines
        textColor: actionTone.mutedColor
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
      textColor: actionTone.mutedColor
    }
  }

  // Time left while active
  CountdownBar {
    running: root.active
    fillColor: Style.inkOf(root.activeTone).graphic
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

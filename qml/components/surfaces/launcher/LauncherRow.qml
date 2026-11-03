pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.components.reusable
import qs.config

// One launcher result (a LauncherManager row): an icon or glyph, the title
// (with a command's usage after it), a description line and a hint chip.
// Its height is set by the launcher, which sizes the list by rows.
Item {
  id: root

  // Set by the launcher from LauncherManager.results[index]
  property var modelData: ({})
  required property int index
  property bool current: false
  // Off until the pointer really moves (see LauncherPanel.pointerAt)
  property bool pointerActive: true

  // The pointer's scene position
  signal hovered(point pos)
  signal clicked

  readonly property bool _image: !!modelData.image
  // An emoji is its own picture: bigger, on no tile
  readonly property bool _emoji: modelData.kind === "emoji"
  readonly property color _titleColor: current ? Theme.accent : Theme.foreground

  // Rows are reused as the results change: one showing a different result
  // than before dips and comes back, icon and text together. Not on its
  // first, which the list's `add` fades in.
  readonly property string _resultKey: (modelData.kind ?? "") + "\n" + (modelData.title ?? "")
  property bool _placed: false
  Component.onCompleted: Qt.callLater(() => root._placed = true)
  on_ResultKeyChanged: {
    if (root._placed && Appearance.animations)
      refresh.restart();
  }

  NumberAnimation {
    id: refresh
    target: content
    property: "opacity"
    from: 0.6
    to: 1
    duration: Appearance.animFast
    easing.type: Appearance.easing
  }

  // Selection pill with an accent bar
  Rectangle {
    anchors.fill: parent
    anchors.leftMargin: Widget.smallPadding
    anchors.rightMargin: Widget.smallPadding
    radius: Widget.radius
    color: root.current ? Qt.alpha(Theme.accent, 0.14) : area.containsMouse && root.pointerActive ? Theme.backgroundHighlight : Qt.alpha(Theme.backgroundHighlight, 0)
    ColorGlide on color {}

    Rectangle {
      width: Widget.px(3)
      height: parent.height * 0.5
      radius: 2
      anchors.left: parent.left
      anchors.leftMargin: Widget.spacing
      anchors.verticalCenter: parent.verticalCenter
      color: Theme.accent
      opacity: root.current ? 1 : 0
      Glide on opacity {}
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onPositionChanged: mouse => root.hovered(mapToItem(null, mouse.x, mouse.y))
    onClicked: root.clicked()
  }

  RowLayout {
    id: content
    anchors.fill: parent
    anchors.leftMargin: Widget.padding * 2
    anchors.rightMargin: Widget.padding * 2
    spacing: Widget.padding

    Item {
      Layout.preferredWidth: LauncherConfig.iconSize
      Layout.preferredHeight: LauncherConfig.iconSize
      Layout.alignment: Qt.AlignVCenter

      Image {
        anchors.fill: parent
        visible: root._image
        source: root._image ? root.modelData.image : ""
        sourceSize: Qt.size(width * 2, height * 2)
        asynchronous: true
        // Pictures (wallpapers, copied images) fill their tile; icons keep
        // their shape
        fillMode: root.modelData.kind === "option" || root.modelData.kind === "clipboard" ? Image.PreserveAspectCrop : Image.PreserveAspectFit
      }

      Rectangle {
        anchors.fill: parent
        visible: !root._image
        radius: Widget.radius
        color: root._emoji ? "transparent" : root.current ? Qt.alpha(Theme.accent, 0.18) : Theme.backgroundAlt
        ColorGlide on color {}

        StyledIcon {
          anchors.centerIn: parent
          text: root.modelData.glyph ?? ""
          textSize: Math.round(LauncherConfig.iconSize * (root._emoji ? 0.8 : 0.55))
          textColor: root.modelData.armed ? Theme.error : root._titleColor
        }
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
      spacing: 1

      RowLayout {
        Layout.fillWidth: true
        spacing: Widget.spacing * 2

        StyledText {
          Layout.fillWidth: usage.text === ""
          text: root.modelData.title ?? ""
          // Titles are clipboard text, window titles, file names: never markup
          textFormat: Text.PlainText
          textColor: root._titleColor
          font.weight: Font.Medium
          elide: Text.ElideRight
          ColorGlide on color {}
        }

        StyledText {
          id: usage
          Layout.fillWidth: true
          visible: text !== ""
          text: root.modelData.usage ?? ""
          textFormat: Text.PlainText
          textColor: Theme.foregroundInactive
          textSize: Appearance.fontSizeBy(-2)
          elide: Text.ElideRight
        }
      }

      StyledText {
        Layout.fillWidth: true
        visible: LauncherConfig.showDescriptions && text !== ""
        text: root.modelData.subtitle ?? ""
        textFormat: Text.PlainText
        textColor: Theme.foregroundAlt
        textSize: Appearance.fontSizeBy(-2)
        elide: Text.ElideRight
      }
    }

    Rectangle {
      Layout.alignment: Qt.AlignVCenter
      Layout.maximumWidth: root.width * 0.4
      visible: hint.text !== ""
      implicitWidth: hint.implicitWidth + Widget.smallPadding * 2
      implicitHeight: hint.implicitHeight + Widget.smallPadding
      radius: Widget.radius
      color: root.modelData.armed ? Theme.error : Theme.backgroundAlt

      StyledText {
        id: hint
        anchors.fill: parent
        anchors.leftMargin: Widget.smallPadding
        anchors.rightMargin: Widget.smallPadding
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: root.modelData.hint ?? ""
        textColor: root.modelData.armed ? Theme.background : Theme.foregroundAlt
        textSize: Appearance.fontSizeBy(-3)
        elide: Text.ElideRight
      }
    }
  }
}

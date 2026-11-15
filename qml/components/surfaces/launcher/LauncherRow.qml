pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.components.reusable
import qs.config
import qs.services.apps

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

  // A file's thumbnail once FileSearchManager has it (asked for only while
  // this row shows the file), in place of its type's icon
  readonly property string _thumbKey: modelData.thumb ? FileSearchManager.thumbnailKey(modelData.thumb, modelData.mtime) : ""
  property string _wantedKey: ""
  readonly property string _thumbnail: _thumbKey ? FileSearchManager.thumbnails[_thumbKey] ?? "" : ""
  on_ThumbKeyChanged: _want()
  Component.onDestruction: {
    if (root._wantedKey)
      FileSearchManager.unwant(root._wantedKey);
  }
  function _want() {
    if (root._wantedKey)
      FileSearchManager.unwant(root._wantedKey);
    root._wantedKey = root._thumbKey;
    if (root._thumbKey)
      FileSearchManager.want(root._thumbKey, root.modelData.thumb);
  }

  readonly property string _source: _thumbnail || (modelData.image ?? "")
  readonly property bool _image: _source !== ""
  // An emoji is its own picture: bigger, on no tile
  readonly property bool _emoji: modelData.kind === "emoji"
  readonly property color _titleColor: current ? Style.onAccentContainer : Style.text

  // Rows are reused as the results change: one showing a different result
  // than before dips and comes back, icon and text together. Not on its
  // first, which the list's `add` fades in.
  readonly property string _resultKey: (modelData.kind ?? "") + "\n" + (modelData.title ?? "")
  property bool _placed: false
  Component.onCompleted: {
    root._want();
    Qt.callLater(() => root._placed = true);
  }
  on_ResultKeyChanged: {
    if (root._placed && Appearance.animations)
      refresh.restart();
  }

  NumberAnimation {
    id: refresh
    target: content
    property: "opacity"
    from: 0.6 // style-exempt: a refreshed row fades back in from this level
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
    color: root.current ? Style.accentContainer : "transparent"
    ColorGlide on color {}

    StateLayer {
      hovered: area.containsMouse && root.pointerActive && !root.current
    }

    Rectangle {
      width: Widget.px(3)
      height: parent.height * 0.5
      radius: 2
      anchors.left: parent.left
      anchors.leftMargin: Widget.spacing
      anchors.verticalCenter: parent.verticalCenter
      color: Style.accent
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
        source: root._source
        sourceSize: Qt.size(width * 2, height * 2)
        asynchronous: true
        // Pictures (wallpapers, copied images, thumbnails) fill their
        // tile; icons keep their shape
        fillMode: root._thumbnail || root.modelData.crop ? Image.PreserveAspectCrop : Image.PreserveAspectFit
      }

      Rectangle {
        anchors.fill: parent
        visible: !root._image
        radius: Widget.radius
        color: root._emoji ? "transparent" : root.modelData.armed ? Style.errorContainer : Style.surfaceHighest
        ColorGlide on color {}

        StyledIcon {
          anchors.centerIn: parent
          text: root.modelData.glyph ?? ""
          textSize: Math.max(Style.iconXs, Math.round(LauncherConfig.iconSize * (root._emoji ? 0.8 : 0.55))) // fitted: the glyph fills its tile (Launcher.iconSize)
          textColor: root.modelData.armed ? Style.inkErrorContainer.icon : root.current ? Style.inkHighest.accent : Style.inkHighest.icon
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

        StyledLabel {
          Layout.fillWidth: usage.text === ""
          Layout.maximumWidth: parent.width
          text: root.modelData.title ?? ""
          // Titles are clipboard text, window titles, file names: never markup
          textFormat: Text.PlainText
          textColor: root._titleColor
          role: "label"
          ColorGlide on color {}
        }

        StyledLabel {
          id: usage
          Layout.fillWidth: true
          visible: text !== ""
          text: root.modelData.usage ?? ""
          textFormat: Text.PlainText
          textColor: root.current ? Style.inkAccentContainer.muted : Style.textMuted
          role: "caption"
          overflow: "line"
        }
      }

      StyledLabel {
        Layout.fillWidth: true
        visible: LauncherConfig.showDescriptions && text !== ""
        text: root.modelData.subtitle ?? ""
        textFormat: Text.PlainText
        textColor: root.current ? Style.inkAccentContainer.muted : Style.textMuted
        role: "caption"
        overflow: "line"
      }
    }

    Rectangle {
      Layout.alignment: Qt.AlignVCenter
      Layout.maximumWidth: root.width * 0.4
      visible: hint.text !== ""
      implicitWidth: hint.implicitWidth + Widget.smallPadding * 2
      implicitHeight: hint.implicitHeight + Widget.smallPadding
      radius: Widget.radius
      color: root.modelData.armed ? Style.error : Style.surfaceHighest

      StyledLabel {
        id: hint
        anchors.fill: parent
        anchors.leftMargin: Widget.smallPadding
        anchors.rightMargin: Widget.smallPadding
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: root.modelData.hint ?? ""
        textColor: root.modelData.armed ? Style.onError : Style.inkHighest.muted
        role: "micro"
      }
    }
  }
}

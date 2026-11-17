pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// A custom widget's List row across the list: a tile of an icon or a
// thumbnail over its text over its subtext, a LevelMeter of its value under
// them when the row has a `rowMax` (forecast days, a row of drives). The
// colours come from the list, as CustomListRow's.
Item {
  id: root

  property string rowText: ""
  property string rowIcon: ""
  property string rowSubtext: ""
  // A source url ("" none)
  property string rowImage: ""
  property real rowNumber: 0
  property real rowMax: 0
  property bool clickable: false
  property color iconTint: Style.textMuted
  property color meterFill: Style.toneFill("accent")

  signal activated

  StateLayer {
    anchors.fill: parent
    radius: Style.radius
    hovered: area.containsMouse && root.clickable
    pressed: area.pressed && root.clickable
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    enabled: root.clickable
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Widget.spacing / 2
    spacing: Widget.spacing / 2

    Item {
      Layout.fillWidth: true
      Layout.fillHeight: true

      StyledIcon {
        visible: root.rowImage === "" && root.rowIcon !== ""
        anchors.centerIn: parent
        text: root.rowIcon
        textColor: root.iconTint
        textSize: Math.max(Style.typeMicro, Math.min(parent.width, parent.height) * 0.6) // fitted: the tile's box
      }

      Thumbnail {
        visible: root.rowImage !== ""
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height)
        height: width
        source: root.rowImage
      }
    }

    StyledLabel {
      visible: text !== ""
      Layout.fillWidth: true
      horizontalAlignment: Text.AlignHCenter
      role: "label"
      overflow: "line"
      text: root.rowText
    }

    StyledLabel {
      visible: text !== ""
      Layout.fillWidth: true
      horizontalAlignment: Text.AlignHCenter
      role: "caption"
      overflow: "line"
      text: root.rowSubtext
    }

    LevelMeter {
      visible: root.rowMax > 0
      Layout.fillWidth: true
      Layout.preferredHeight: Widget.px(6)
      thickness: Widget.px(4)
      share: root.rowMax > 0 ? root.rowNumber / root.rowMax : 0
      fillColor: root.meterFill
    }
  }
}

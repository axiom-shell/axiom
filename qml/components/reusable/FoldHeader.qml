pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// A fold's clickable header (FoldingCard, FoldingSection): a SectionHeading
// with its description only while unfolded, an optional line above it, the
// unsaved-edits dot while folded with `marked`, and a chevron. A click
// emits `toggled`, unless it isn't `foldable`.
Item {
  id: root

  property string title
  property string description
  // A line above the title (the section, in search results)
  property string section
  property bool collapsed: false
  property bool foldable: true
  property bool marked: false

  signal toggled

  Layout.fillWidth: true
  implicitHeight: header.implicitHeight

  MouseArea {
    id: headerArea
    anchors.fill: parent
    enabled: root.foldable
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.toggled()
  }

  RowLayout {
    id: header
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: Widget.spacing

    ColumnLayout {
      Layout.fillWidth: true
      spacing: 2

      StyledText {
        wrapMode: Text.WordWrap
        visible: root.section !== ""
        text: root.section
        opacity: 0.6
        textSize: Appearance.fontSizeBy(-2)
        Layout.fillWidth: true
      }

      SectionHeading {
        title: root.title
        description: root.collapsed ? "" : root.description
      }
    }

    UnsavedDot {
      shown: root.collapsed && root.marked
      Layout.alignment: Qt.AlignTop
      Layout.topMargin: Appearance.fontSize / 2
    }

    StyledIcon {
      visible: root.foldable
      text: "expand_more"
      textColor: headerArea.containsMouse ? Theme.accent : Theme.foregroundAlt
      textSize: Appearance.fontSizeBy(4)
      rotation: root.collapsed ? -90 : 0
      Layout.alignment: Qt.AlignTop

      Glide on rotation {}
    }
  }
}

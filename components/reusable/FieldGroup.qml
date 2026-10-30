pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// A titled group of fields, as on the settings page (editor inspectors)
StyledContainer {
  id: root
  property string title
  property string description
  // Items beside the heading (a status chip, a button)
  property alias headerExtras: headerRow.data
  default property alias content: groupColumn.data

  Layout.fillWidth: true
  Layout.alignment: Qt.AlignTop
  implicitHeight: groupColumn.implicitHeight + Widget.padding * 2

  ColumnLayout {
    id: groupColumn
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.margins: Widget.padding
    spacing: Widget.spacing * 1.5

    RowLayout {
      id: headerRow
      Layout.fillWidth: true
      spacing: Widget.spacing

      SectionHeading {
        title: root.title
        description: root.description
      }
    }

    // Between the heading and the fields, as on a settings card
    StyledSeparator {
      visible: root.title !== ""
      Layout.fillWidth: true
      separatorHeight: 1
      opacity: 0.6
    }
  }
}

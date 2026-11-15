pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.methods
import qs.components.reusable

// Custom widgets page: the paths of an output with the value at each, what an
// element binds to (the Data tab's list; the element column's Data panel,
// where a click binds one: `pickable`). `paths` is [{ path, type, value }]
// (CustomWidgetData.flatten or bindChoices); the first `maxRows` are built, by
// count: a new sample of the same shape rebuilds nothing.
ColumnLayout {
  id: root

  property var paths: []
  property int maxRows: 200
  // A row can be clicked: `picked(path)`
  property bool pickable: false

  signal picked(string path)

  spacing: Widget.spacing

  Repeater {
    model: Math.min(root.paths.length, root.maxRows)

    Item {
      id: row
      required property int index
      readonly property var entry: root.paths[row.index] ?? ({})
      Layout.fillWidth: true
      implicitHeight: line.implicitHeight

      StateLayer {
        visible: root.pickable
        hovered: area.containsMouse
        pressed: area.pressed
      }

      RowLayout {
        id: line
        anchors.fill: parent
        spacing: Widget.spacing

        StyledLabel {
          Layout.preferredWidth: Appearance.fontSize * 12
          text: row.entry.path ?? ""
          textFamily: "monospace"
          role: "caption"
          elide: Text.ElideMiddle // style-exempt: middle
        }
        StyledLabel {
          Layout.fillWidth: true
          text: row.entry.type === "array" ? I18n.tr("a list of {0}", row.entry.value) : row.entry.type === "object" ? "{…}" : CustomWidgetData.asText(row.entry.value)
          tone: "muted"
          overflow: "line"
        }
      }

      MouseArea {
        id: area
        anchors.fill: parent
        enabled: root.pickable
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.picked(row.entry.path ?? "")
      }
    }
  }

  StyledText {
    visible: root.paths.length > root.maxRows
    text: I18n.tr("…and {0} more", root.paths.length - root.maxRows)
    tone: "muted"
  }
}

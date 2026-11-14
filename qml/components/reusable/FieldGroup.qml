pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.methods

// A titled group of fields, as on the settings page (editor inspectors): a
// boxed card of its own.
Surface {
  id: root
  property string title
  property string description
  // Items beside the heading (a status chip, a button)
  property alias headerExtras: headerRow.data
  default property alias content: groupColumn.data

  // The Surface it sits on: the page (or none) takes it as a surface-tone
  // card, any other is a pane, where the card is one tone up
  readonly property var _host: InkHost.find(root.parent)
  readonly property bool _boxed: !root._host || root._host.tone === "page"

  Layout.fillWidth: true
  Layout.alignment: Qt.AlignTop
  tone: root._boxed ? "surface" : "raised"
  implicitHeight: groupColumn.implicitHeight + Style.space3 * 2

  ColumnLayout {
    id: groupColumn
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.margins: Style.space3
    spacing: Style.space2

    RowLayout {
      id: headerRow
      Layout.fillWidth: true
      spacing: Widget.spacing

      SectionHeading {
        title: root.title
        description: root.description
      }
    }
  }
}

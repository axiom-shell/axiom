pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.methods

// A titled group of fields, as on the settings page (editor inspectors): a
// boxed card of its own on the page, flat inside a pane (no fill or border: the
// pane's own); `pageCard` keeps it boxed inside the settings page's own card.
Surface {
  id: root
  property string title
  property string description
  // Items beside the heading (a status chip, a button)
  property alias headerExtras: headerRow.data
  // A settings page's hand-built card: boxed whatever it sits on (the page's
  // card around the cards is itself a Surface), as a FoldingCard is
  property bool pageCard: false
  default property alias content: groupColumn.data

  // The Surface it sits on: the page (or none) takes it as a surface-tone
  // card, any other is a pane, where the group is flat, on the pane's own fill
  readonly property var _host: InkHost.find(root.parent)
  readonly property bool _boxed: root.pageCard || !root._host || root._host.tone === "page"

  Layout.fillWidth: true
  Layout.alignment: Qt.AlignTop
  tone: root._boxed ? "surface" : root._host.tone
  implicitHeight: groupColumn.implicitHeight + (root._boxed ? Style.space3 * 2 : Style.space3)

  // Flat inside a pane: no fill, border or side margins; `color` returns to
  // Surface's own binding on leaving the state
  states: State {
    when: !root._boxed
    PropertyChanges {
      root.color: "transparent"
      root.outlined: false
      groupColumn.anchors.leftMargin: 0
      groupColumn.anchors.rightMargin: 0
    }
  }

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

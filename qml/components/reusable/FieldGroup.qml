pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.methods

// A titled group of fields, as on the settings page (editor inspectors): a
// boxed card of its own on the page, flat inside a pane (no fill or border: the
// pane's own); `pageCard` keeps it boxed inside the settings page's own card.
// Children stack with no gap, as a settings card's rows do (a row pads itself,
// FormRow); a non-row child that follows another takes its own
// `Layout.topMargin: Style.space2`. A flat group adds no space around itself:
// the column it sits in spaces it (Style.space2, the settings page's card gap).
// A `pageCard` is hand-built content (no rows): its children keep `headerGap`
// between them.
Surface {
  id: root
  property string title
  property string description
  // Items beside the heading (a status chip, a button)
  property alias headerExtras: headerRow.data
  // The space between the heading and the first field
  property real headerGap: Style.space2
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
  implicitHeight: groupColumn.implicitHeight + (root._boxed ? Style.space3 * 2 : 0)

  // Flat inside a pane: no fill, border or side margins; `color` returns to
  // Surface's own binding on leaving the state
  states: State {
    when: !root._boxed
    PropertyChanges {
      root.color: "transparent"
      root.outlined: false
      groupColumn.anchors.topMargin: 0
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
    spacing: root.pageCard ? root.headerGap : 0

    RowLayout {
      id: headerRow
      Layout.fillWidth: true
      Layout.bottomMargin: root.pageCard ? 0 : root.headerGap
      spacing: Widget.spacing

      SectionHeading {
        title: root.title
        description: root.description
      }
    }
  }
}

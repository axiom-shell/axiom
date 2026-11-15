pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable
import qs.components.content.base
import qs.components.content.parts

// A tool page's pane (docs/recipes/tool-page.md): a TitledCard whose title is
// the kind of pane (never the selection's name), with, in this order, a
// `pinned` list above its tabs (`tabModel`), a `toolbar`, the scrolling body
// (children) and a fixed `footer`. While `emptyKind` is set the body shows
// that empty state instead: "none" (nothing yet, with the way to add), "select"
// (nothing selected) or "results" (a search or filter matched nothing).
TitledCard {
  id: root

  // A ToolBar
  property alias toolbar: toolbarHolder.data
  property var tabModel: []
  property int tabIndex: 0
  // Tab indices with unsaved edits (a dot after their label)
  property var tabMarked: []
  // Fixed content above the tabs, scrolling inside past `pinnedShare` of the
  // pane's height
  property alias pinned: pinnedColumn.data
  property real pinnedShare: 0.4
  // "" | "none" | "select" | "results"
  property string emptyKind: ""
  property string emptyIcon: ""
  property string emptyText: ""
  property string emptyHint: ""
  property string emptyActionText: ""
  // The page's own children (its selection-keyed Loaders): the scrolling body
  default property alias paneContent: paneBody.data

  signal tabClicked(int index)
  signal emptyTriggered

  readonly property string _emptyIcon: root.emptyIcon !== "" ? root.emptyIcon : root.emptyKind === "select" ? "touch_app" : root.emptyKind === "results" ? "search_off" : ""

  // Through the base's aliases (a plain child would land in `paneContent`)
  headerExtras: [
    Item {
      id: pinnedArea
      Layout.fillWidth: true
      Layout.fillHeight: false
      // From the pane's height and the rows, never from the content's own rect
      implicitHeight: Math.min(pinnedColumn.implicitHeight, Math.round(root.height * root.pinnedShare))
      Layout.preferredHeight: pinnedArea.implicitHeight
      // Never hidden (its rows would all read hidden and it would stay so):
      // with nothing showing in it, a negative margin takes back the gap
      // the column puts after it
      Layout.bottomMargin: pinnedColumn.implicitHeight > 0 ? 0 : -Widget.spacing

      StyledScrollView {
        anchors.fill: parent
        contentPadding: 0
        // A bar only while the capped list overflows
        showScrollBar: pinnedColumn.implicitHeight > pinnedArea.height

        ColumnLayout {
          id: pinnedColumn
          width: parent?.width ?? 0
          spacing: Widget.spacing / 2
        }
      }
    },
    // The pinned area's edge, drawn only while its list is cut
    StyledSeparator {
      objectName: "pinnedEdge"
      Layout.fillWidth: true
      Layout.topMargin: -Widget.spacing / 2
      visible: pinnedColumn.implicitHeight > pinnedArea.height
    },
    StyledTabBar {
      id: tabStrip
      visible: root.tabModel.length > 0
      // The toolbar holder is never hidden (its child would read hidden
      // forever) and a Layout item cannot be shorter than 0: with nothing
      // showing in it, a negative margin here takes back its gap
      Layout.bottomMargin: toolbarHolder.visible && toolbarHolder.visibleChildren.length === 0 ? -Widget.spacing : 0
      scrollable: true
      tabs: root.tabModel
      marked: root.tabMarked
      currentIndex: root.tabIndex
      onTabClicked: index => root.tabClicked(index)
    },
    ColumnLayout {
      id: toolbarHolder
      Layout.fillWidth: true
      Layout.fillHeight: false
      visible: children.length > 0
      spacing: 0
    }
  ]

  bodyContent: [
    Loader {
      id: emptyLoader
      active: root.emptyKind !== ""
      visible: active
      Layout.fillWidth: true
      Layout.preferredHeight: root.bodyHeight

      sourceComponent: Item {
        EmptyState {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: parent.top
          anchors.topMargin: Math.max(Style.space4, Math.round(root.bodyHeight / 3) - Style.iconXl)
          width: Math.min(parent.width, implicitWidth)
          icon: root._emptyIcon
          text: root.emptyText
          hint: root.emptyHint
          actionText: root.emptyActionText
          onTriggered: root.emptyTriggered()
        }
      }
    },
    ColumnLayout {
      id: paneBody
      visible: root.emptyKind === ""
      Layout.fillWidth: true
      spacing: root.contentSpacing
    }
  ]
}

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// A fold's clickable header (FoldingCard, FoldingSection): a SectionHeading
// with its description only while unfolded, an optional line above it, the
// unsaved-edits dot while folded with `marked`, a status chip (`status`,
// kept while folded) centred on the chevron, and the chevron. The trigger is
// the host's whole header, a button (a Pressable: tint on hover, ring on
// keyboard focus, Space or Enter fold it, a Tab stop): `reach*` say how far
// it extends past this item (the host's padding), so the band covers the
// card or the row, not only the text. A click emits `toggled`, unless it
// isn't `foldable`.
Item {
  id: root

  property string title
  property string description
  // A line above the title (the section, in search results)
  property string section
  property bool collapsed: false
  property bool foldable: true
  property bool marked: false
  // A StatusChip's word and tone; no chip while empty
  property string status
  property string statusTone: "neutral"
  // The trigger's rounding (the host's shape: it tints as its parent)
  property real radius: Style.radiusInner
  // How far the trigger reaches past the header on each side
  property real reachLeft: 0
  property real reachRight: 0
  property real reachTop: 0
  property real reachBottom: 0
  // The trigger's bottom corners square (an open card's header band)
  property bool squareBottom: false

  signal toggled

  Layout.fillWidth: true
  implicitHeight: header.implicitHeight

  Pressable {
    id: press
    objectName: "foldTrigger"
    enabled: root.foldable
    tabStop: root.foldable
    squareBottom: root.squareBottom
    anchors.leftMargin: -root.reachLeft
    anchors.rightMargin: -root.reachRight
    anchors.topMargin: -root.reachTop
    anchors.bottomMargin: -root.reachBottom
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
        role: "caption"
        tone: "muted"
        overflow: "wrap"
        visible: root.section !== ""
        text: root.section
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

    // One row, so the chip is centred on the chevron's box (separately
    // top-aligned, the taller chevron sat lower)
    RowLayout {
      visible: root.foldable || root.status !== ""
      spacing: Widget.spacing
      Layout.alignment: Qt.AlignTop
      Layout.fillWidth: false

      StatusChip {
        visible: root.status !== ""
        text: root.status
        tone: root.statusTone
        Layout.alignment: Qt.AlignVCenter
      }

      FoldChevron {
        visible: root.foldable
        open: !root.collapsed
        hot: press.hovered || press.activeFocus
        Layout.alignment: Qt.AlignVCenter
      }
    }
  }
}

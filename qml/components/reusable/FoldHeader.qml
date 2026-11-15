pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// A fold's clickable header (FoldingCard, FoldingSection): a SectionHeading
// with its description only while unfolded, an optional line above it, the
// unsaved-edits dot while folded with `marked`, a status chip (`status`,
// kept while folded) centred on the chevron, and the chevron. A click
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
  // A StatusChip's word and tone; no chip while empty
  property string status
  property string statusTone: "neutral"
  // Kept for FoldingCard until it passes a tone
  property color statusColor: "transparent"
  // The chip's tone: statusTone, else the tone statusColor names. Until PR 3
  // passes tones; PR 3 deletes it with statusColor
  readonly property string _chipTone: {
    if (root.statusTone !== "neutral")
      return root.statusTone;
    const c = root.statusColor;
    if (Qt.colorEqual(c, Theme.success) || Qt.colorEqual(c, Style.successText)) // style-exempt: a legacy colour matched to its tone
      return "success";
    if (Qt.colorEqual(c, Theme.warning) || Qt.colorEqual(c, Style.warningText)) // style-exempt: a legacy colour matched to its tone
      return "warning";
    if (Qt.colorEqual(c, Theme.error) || Qt.colorEqual(c, Style.errorText)) // style-exempt: a legacy colour matched to its tone
      return "error";
    if (Qt.colorEqual(c, Theme.accent)) // style-exempt: a legacy colour matched to its tone
      return "accent";
    return "neutral";
  }

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
        tone: root._chipTone
        Layout.alignment: Qt.AlignVCenter
      }

      StyledIcon {
        visible: root.foldable
        text: "expand_more"
        tone: headerArea.containsMouse ? "accent" : "muted"
        rotation: root.collapsed ? -90 : 0
        Layout.alignment: Qt.AlignVCenter

        Glide on rotation {}
      }
    }
  }
}

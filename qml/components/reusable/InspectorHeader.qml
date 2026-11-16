pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// The top of an editor's inspector (bar widget, overlay module or cell):
// the thing's icon in a well (accent-filled when `filled`), its name and
// where it is, then its actions (children, a page's state toggles) and
// the standard ones (duplicate, revert, remove, close: each shown by its
// `can…` flag); under them, while
// `showsLinks`, a wrapping row of links to where related things are set
// (`links`), all over a faint divider
ColumnLayout {
  id: root

  property string icon
  property bool filled: true
  property string title
  property string subtitle
  default property alias actions: row.data
  property alias links: linkRow.data
  // Set by the host, from whether any link leads anywhere (not from the
  // links' `visible`, false while this row is hidden)
  property bool showsLinks: false

  // The standard actions, each a StyledIconButton after the children; the
  // tooltips default to the generic words
  property bool canDuplicate: false
  property string duplicateTooltip: I18n.tr("Duplicate")
  property bool revertable: false
  property string revertTooltip: I18n.tr("Revert")
  // Remove shows while `canRemove`; with a `removeBlockedReason` it is
  // disabled and says why
  property bool canRemove: false
  property string removeBlockedReason: ""
  property string removeTooltip: I18n.tr("Remove")
  property bool closable: false
  property string closeTooltip: I18n.tr("Close")

  signal duplicate
  signal revert
  signal remove
  signal close

  Layout.fillWidth: true
  spacing: Widget.spacing

  // A caller's children go after everything declared in `row`, so the
  // standard actions are a sibling after it
  RowLayout {
    Layout.fillWidth: true
    // Two lines of text never taller than the row (a big font)
    Layout.preferredHeight: Math.max(Widget.height + Widget.padding, titles.implicitHeight)
    spacing: Widget.spacing

    Surface {
      Layout.preferredWidth: Widget.height + Widget.px(4)
      Layout.preferredHeight: Widget.height + Widget.px(4)
      tone: root.filled ? "accentContainer" : "highest"

      StyledIcon {
        anchors.centerIn: parent
        text: root.icon
        size: "md"
        tone: root.filled ? "text" : "accent"
      }
    }

    ColumnLayout {
      id: titles
      Layout.fillWidth: true
      spacing: 0

      StyledLabel {
        text: root.title
        role: "title"
        overflow: "line"
        Layout.fillWidth: true
      }

      StyledLabel {
        id: subtitleText
        text: root.subtitle
        role: "caption"
        tone: "muted"
        overflow: "line"
        // A path, a command or a model: its ends say the most
        elide: Text.ElideMiddle // style-exempt: middle
        Layout.fillWidth: true

        HoverHandler {
          id: subtitleHover
        }
      }
    }

    RowLayout {
      id: row
      spacing: Widget.spacing
    }

    RowLayout {
      id: standard
      spacing: Widget.spacing

      StyledIconButton {
        visible: root.canDuplicate
        iconText: "content_copy"
        tooltipText: root.duplicateTooltip
        onClicked: root.duplicate()
      }
      StyledIconButton {
        visible: root.revertable
        iconText: "undo"
        tooltipText: root.revertTooltip
        onClicked: root.revert()
      }
      StyledIconButton {
        visible: root.canRemove || root.removeBlockedReason !== ""
        enabled: root.removeBlockedReason === ""
        kind: "danger"
        iconText: "delete"
        tooltipText: root.removeBlockedReason !== "" ? root.removeBlockedReason : root.removeTooltip
        onClicked: root.remove()
      }
      StyledIconButton {
        visible: root.closable
        iconText: "close"
        tooltipText: root.closeTooltip
        onClicked: root.close()
      }
    }
  }

  // The whole subtitle, while it is elided
  TruncationTip {
    target: subtitleText
    text: root.subtitle
    hovered: subtitleHover.hovered
    maxWidth: Widget.textPx(320)
  }

  Flow {
    id: linkRow
    visible: root.showsLinks
    Layout.fillWidth: true
    spacing: Widget.spacing * 2
  }

  StyledSeparator {
    Layout.fillWidth: true
  }
}

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components.reusable
import qs.config

// Title row of a TitledCard, with Save and Discard (shown while `dirty`,
// Discard only with `canReset`) buttons for whichever service owns the panel's pending edits. Items
// placed inside sit just after the title (`trailingTools` sit at the right, before the buttons). The title elides and the buttons
// drop to icons when the row is too narrow.
Item {
  id: root
  property string title
  // An accent icon before the title (md; lg with `iconSize`), and a count
  // after it (hidden below 0)
  property string icon: ""
  property string iconSize: "md"
  property int count: -1
  property bool dirty: false
  // Hide both buttons for panels with nothing to save
  property bool showActions: true
  // Save stays visible while dirty but is disabled when false
  property bool canSave: true
  // Discard shows while dirty only when true (SaveResetActions.canReset)
  property bool canReset: true
  property string saveLabel: I18n.tr("Save")
  // What the panel is for, shown on hovering a "?" after the title
  property string help: ""
  // Controls beside the title
  default property alias extras: extrasRow.data
  // Controls at the right, just before Save and Discard
  property alias trailingTools: trailingToolsRow.data

  signal save
  signal reset

  Layout.fillWidth: true
  Layout.preferredHeight: Math.max(Widget.height + Widget.padding, headerRow.implicitHeight)

  RowLayout {
    id: headerRow
    anchors.fill: parent
    spacing: Widget.spacing

    StyledIcon {
      visible: root.icon !== ""
      text: root.icon
      size: root.iconSize
      tone: "accent"
    }

    StyledLabel {
      id: titleText
      Layout.fillWidth: true
      // Shrinks to elide, but doesn't push the extras away from it. In
      // whole pixels: the layout rounds a width it grows down, and a title
      // a fraction short elides its last letters
      Layout.preferredWidth: Math.ceil(implicitWidth)
      Layout.maximumWidth: Math.ceil(implicitWidth)
      role: "headline"
      text: root.title

      HoverHandler {
        id: titleHover
      }
    }

    // The whole title, while the row is too narrow for it
    LazyLoader {
      active: titleHover.hovered && titleText.truncated
      StyledToolTip {
        target: titleText
        text: root.title
        maxWidth: Widget.textPx(320)
      }
    }

    StyledText {
      id: countText
      visible: root.count >= 0
      role: "caption"
      tone: "muted"
      text: String(root.count)
    }

    // `help`: a "?" telling it on hover
    StyledIcon {
      id: helpIcon
      visible: root.help !== ""
      text: "help"
      tone: helpArea.containsMouse ? "accent" : "faint"
      size: "sm"

      MouseArea {
        id: helpArea
        anchors.fill: parent
        anchors.margins: -Widget.px(4)
        hoverEnabled: true
      }

      LazyLoader {
        active: helpArea.containsMouse
        StyledToolTip {
          target: helpIcon
          text: root.help
          maxWidth: Widget.textPx(320)
        }
      }
    }

    RowLayout {
      id: extrasRow
      visible: children.length > 0
      spacing: Widget.spacing / 2
    }

    Item {
      Layout.fillWidth: true
    }

    RowLayout {
      id: trailingToolsRow
      visible: children.length > 0
      spacing: Widget.spacing / 2
    }

    // With tools at the right the Save / Discard slot keeps its full size
    // while they are hidden, so the tools' right edge never moves with
    // `dirty`, the title or `compact`'s width
    Item {
      id: actionsSlot
      visible: root.showActions
      Layout.preferredWidth: trailingToolsRow.visible ? Math.ceil(actions.compact ? Widget.height * 2 + actions.spacing : actions.fullWidth) : actions.implicitWidth
      Layout.preferredHeight: actions.implicitHeight
      implicitWidth: actions.implicitWidth

      SaveResetActions {
        id: actions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        dirty: root.dirty
        canSave: root.canSave
        canReset: root.canReset
        saveLabel: root.saveLabel
        compact: root.width < titleText.implicitWidth + (helpIcon.visible ? helpIcon.implicitWidth + headerRow.spacing : 0) + (root.icon !== "" ? Style.iconSize(root.iconSize) + headerRow.spacing : 0) + (countText.visible ? countText.implicitWidth + headerRow.spacing : 0) + (extrasRow.visible ? extrasRow.implicitWidth + headerRow.spacing : 0) + (trailingToolsRow.visible ? trailingToolsRow.implicitWidth + headerRow.spacing : 0) + headerRow.spacing + fullWidth
        onSave: root.save()
        onReset: root.reset()
      }
    }
  }
}

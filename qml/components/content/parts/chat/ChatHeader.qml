pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.reusable

// The chat's top row: the conversation list toggle, the title, the
// preset/model chip and a new-chat button, all one height
RowLayout {
  id: root

  // The conversation list is docked beside the chat (no toggle needed)
  property bool listDocked: false
  property bool listOpen: false
  property bool pickerOpen: false

  readonly property int rowHeight: Widget.iconButton

  signal toggleList
  signal togglePicker

  spacing: Widget.spacing

  FlatIconButton {
    visible: !root.listDocked
    size: root.rowHeight
    iconText: "history"
    iconColor: root.listOpen ? Style.accent : Style.text
    tooltipText: I18n.tr("Conversations")
    onClicked: root.toggleList()
  }

  StyledLabel {
    Layout.fillWidth: true
    Layout.alignment: Qt.AlignVCenter
    Layout.leftMargin: root.listDocked ? Widget.spacing : 0
    text: ChatManager.conversation.title || I18n.tr("New conversation")
    role: "title"
  }

  // Preset and model
  Surface {
    id: chip
    Layout.alignment: Qt.AlignVCenter
    Layout.maximumWidth: Widget.textPx(220)
    implicitWidth: chipRow.implicitWidth + Widget.padding * 1.5
    implicitHeight: root.rowHeight
    tone: root.pickerOpen ? "accentContainer" : "highest"
    radius: height / 2

    StateLayer {
      hovered: chipHover.hovered
    }

    RowLayout {
      id: chipRow
      anchors.fill: parent
      anchors.leftMargin: Widget.padding
      anchors.rightMargin: Widget.padding * 0.5
      spacing: Widget.spacing

      StyledIcon {
        Layout.alignment: Qt.AlignVCenter
        text: ChatManager.preset.icon || "chat"
        size: "sm"
        textColor: chip.ink.accent
      }
      StyledLabel {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        text: ChatManager.model || I18n.tr("No model")
        role: "caption"
        overflow: "line"
        textColor: chip.ink.text
      }
      StyledIcon {
        Layout.alignment: Qt.AlignVCenter
        text: root.pickerOpen ? "expand_less" : "expand_more"
        size: "sm"
        textColor: chip.ink.muted
      }
    }

    HoverHandler {
      id: chipHover
      cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
      onTapped: root.togglePicker()
    }
  }

  FlatIconButton {
    size: root.rowHeight
    iconText: "edit_square"
    iconColor: Style.text
    tooltipText: I18n.tr("New conversation")
    onClicked: ChatManager.newConversation(ChatManager.preset.name)
  }
}

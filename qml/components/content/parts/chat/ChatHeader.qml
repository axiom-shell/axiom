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
    iconColor: root.listOpen ? Theme.accent : Theme.foreground
    tooltipText: I18n.tr("Conversations")
    onClicked: root.toggleList()
  }

  StyledText {
    Layout.fillWidth: true
    Layout.alignment: Qt.AlignVCenter
    Layout.leftMargin: root.listDocked ? Widget.spacing : 0
    text: ChatManager.conversation.title || I18n.tr("New conversation")
    font.bold: true
    elide: Text.ElideRight
  }

  // Preset and model
  Rectangle {
    Layout.alignment: Qt.AlignVCenter
    Layout.maximumWidth: Widget.px(220)
    implicitWidth: chip.implicitWidth + Widget.padding * 1.5
    implicitHeight: root.rowHeight
    radius: height / 2
    color: root.pickerOpen || chipHover.hovered ? Theme.backgroundHighlight : Theme.backgroundAlt
    border.color: root.pickerOpen ? Theme.accent : Theme.border
    border.width: 1

    ColorGlide on color {}

    RowLayout {
      id: chip
      anchors.fill: parent
      anchors.leftMargin: Widget.padding
      anchors.rightMargin: Widget.padding * 0.5
      spacing: Widget.spacing

      StyledIcon {
        Layout.alignment: Qt.AlignVCenter
        text: ChatManager.preset.icon || "chat"
        textColor: Theme.accent
        textSize: Appearance.fontSize
      }
      StyledText {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        text: ChatManager.model || I18n.tr("No model")
        textSize: Appearance.fontSizeBy(-2)
        elide: Text.ElideMiddle
      }
      StyledIcon {
        Layout.alignment: Qt.AlignVCenter
        text: root.pickerOpen ? "expand_less" : "expand_more"
        textColor: Theme.foregroundAlt
        textSize: Appearance.fontSize
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
    iconColor: Theme.foreground
    tooltipText: I18n.tr("New conversation")
    onClicked: ChatManager.newConversation(ChatManager.preset.name)
  }
}

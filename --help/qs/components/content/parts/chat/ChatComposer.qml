pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.reusable

// Where a message is written: attached images, the text, then a toolbar
// with the attach buttons, the keys and send (stop while a reply streams).
// Chat.sendKey picks Enter or Ctrl+Enter to send.
ColumnLayout {
  id: root

  readonly property bool ctrlEnter: ChatConfig.sendKey === "ctrlEnter"
  // The key hints need room beside the buttons
  readonly property bool showHints: root.width >= 320

  function focusInput() {
    area.input.forceActiveFocus();
  }

  function _send() {
    if (ChatManager.busy)
      return;
    if (ChatManager.send(area.text))
      area.text = "";
  }

  spacing: Widget.spacing / 2

  StyledContainer {
    Layout.fillWidth: true
    implicitHeight: box.implicitHeight + Widget.spacing * 3
    backgroundColor: Theme.backgroundAlt
    borderColor: area.input.activeFocus ? Theme.accent : Theme.border
    borderWidth: 1
    borderRadius: Widget.radius + 2

    ColorGlide on borderColor {
      duration: Appearance.animNormal
    }

    ColumnLayout {
      id: box
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Widget.spacing * 1.5
      anchors.rightMargin: Widget.spacing * 1.5
      spacing: Widget.spacing

      Flow {
        visible: ChatManager.attachments.length > 0 || ChatManager.attaching
        Layout.fillWidth: true
        Layout.topMargin: Widget.spacing / 2
        spacing: Widget.spacing / 2

        Repeater {
          model: ChatManager.attachments.length
          delegate: AttachmentChip {
            required property int index
            attachment: ChatManager.attachments[index]
            removable: true
            onRemoved: ChatManager.detach(index)
          }
        }

        Rectangle {
          visible: ChatManager.attaching
          width: Widget.px(56)
          height: Widget.px(56)
          radius: Widget.radius / 2
          color: Theme.backgroundHighlight

          StyledIcon {
            anchors.centerIn: parent
            text: "hourglass_empty"
            textColor: Theme.foregroundAlt
          }
        }
      }

      StyledTextArea {
        id: area
        Layout.fillWidth: true
        Layout.maximumHeight: Appearance.fontSize * 12
        expandable: true
        newlineOnEnter: root.ctrlEnter
        horizontalMargin: Widget.spacing
        verticalMargin: Widget.spacing
        minHeight: 0
        backgroundColor: "transparent"
        borderColor: "transparent"
        borderWidth: 0
        placeholderText: I18n.tr("Message {0}…", ChatManager.preset.name)
        onAccepted: root._send()
      }

      // Attach buttons, the keys, send
      RowLayout {
        Layout.fillWidth: true
        spacing: Widget.spacing / 2

        FlatIconButton {
          enabled: !ChatManager.attaching
          iconText: "content_paste"
          tooltipText: I18n.tr("Paste image")
          onClicked: ChatManager.attachClipboard()
        }

        FlatIconButton {
          enabled: !ChatManager.attaching
          iconText: "screenshot_region"
          tooltipText: I18n.tr("Screenshot a region")
          onClicked: ChatManager.attachScreenshot()
        }

        Item {
          Layout.fillWidth: true
        }

        KeyHint {
          visible: root.showHints
          Layout.alignment: Qt.AlignVCenter
          Layout.rightMargin: Widget.spacing
          key: root.ctrlEnter ? "Ctrl ↵" : "↵"
          label: I18n.tr("send")
        }
        KeyHint {
          visible: root.showHints
          Layout.alignment: Qt.AlignVCenter
          Layout.rightMargin: Widget.spacing * 2
          key: root.ctrlEnter ? "↵" : "⇧ ↵"
          label: I18n.tr("new line")
        }

        Rectangle {
          id: sendButton
          readonly property bool canSend: ChatManager.busy || area.text.trim() !== "" || ChatManager.attachments.length > 0
          Layout.alignment: Qt.AlignVCenter
          implicitWidth: Widget.iconButton
          implicitHeight: Widget.iconButton
          radius: height / 2
          color: ChatManager.busy ? Theme.backgroundHighlight : canSend ? Theme.accent : Theme.backgroundHighlight
          opacity: canSend ? 1 : 0.5

          ColorGlide on color {
            duration: Appearance.animNormal
          }

          StyledIcon {
            anchors.centerIn: parent
            text: ChatManager.busy ? "stop" : "arrow_upward"
            fill: 1
            textColor: ChatManager.busy ? Theme.foreground : sendButton.canSend ? Theme.background : Theme.foregroundAlt
            textSize: Appearance.fontSizeBy(2)
          }

          TapHandler {
            onTapped: ChatManager.busy ? ChatManager.stop() : root._send()
          }
          HoverHandler {
            cursorShape: sendButton.canSend ? Qt.PointingHandCursor : Qt.ArrowCursor
          }
        }
      }
    }
  }

  // A problem with the last send or attachment
  StyledText {
    visible: ChatManager.notice !== ""
    Layout.fillWidth: true
    Layout.leftMargin: Widget.spacing
    text: ChatManager.notice
    textColor: Theme.warning
    textSize: Appearance.fontSizeBy(-3)
    elide: Text.ElideRight
  }
}

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.components.reusable

// A live notification's inline reply (when its app offers one): a field
// with the app's placeholder and a send button; Enter or the button sends
// the text through the notification and emits sent. Its host gives the
// window the keyboard while `typing`.
RowLayout {
  id: root

  // A live Notification, or null
  required property var notification

  signal sent

  readonly property bool typing: entry.input.activeFocus

  function send() {
    const text = entry.text.trim();
    if (text === "" || !root.notification)
      return;
    root.notification.sendInlineReply(text);
    entry.text = "";
    root.sent();
  }

  Layout.fillWidth: true
  spacing: Widget.spacing / 2

  StyledTextEntry {
    id: entry
    Layout.fillWidth: true
    Layout.preferredHeight: Widget.height
    placeholderText: root.notification?.inlineReplyPlaceholder || I18n.tr("Reply")
    onAccepted: root.send()
  }

  StyledIconButton {
    Layout.fillWidth: false
    Layout.fillHeight: false
    Layout.alignment: Qt.AlignVCenter
    Layout.preferredWidth: Widget.iconButton
    Layout.preferredHeight: Widget.iconButton
    iconText: "send"
    iconSize: Appearance.fontSizeBy(-2)
    borderRadius: width / 2
    enabled: entry.text.trim() !== ""
    tooltipText: I18n.tr("Send")
    onClicked: root.send()
  }
}

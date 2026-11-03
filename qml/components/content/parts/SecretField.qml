pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.components.reusable

// A secret typed inline (a password, a key, a passphrase): a field
// hiding its text and, after it, the button that submits it. Enter
// submits too, Escape cancels (the field leaves it to its parents
// otherwise). VpnRow's secrets, WifiJoinForm's password and DriveRow's
// passphrase.
RowLayout {
  id: root

  property alias text: entry.text
  property alias input: entry.input
  property string placeholderText: ""
  // The field's height, -1 for its own
  property real entryHeight: -1
  // The button after the field (hidden for all but a form's last field)
  property bool buttonShown: true
  // Whether the button can submit (it's dimmed otherwise)
  property bool canSubmit: entry.text !== ""
  property string buttonIcon: "link"
  property string buttonTip: I18n.tr("Connect")
  // Take the keyboard once built
  property bool focusOnShow: false

  // Enter, or the button
  signal submitted
  signal cancelled

  Layout.fillWidth: true
  spacing: Widget.spacing

  StyledTextEntry {
    id: entry
    Layout.fillWidth: true
    Layout.preferredHeight: root.entryHeight
    placeholderText: root.placeholderText
    input.echoMode: TextInput.Password
    input.wrapMode: Text.NoWrap
    onAccepted: root.submitted()
    // The field leaves Escape to its parents
    Keys.onEscapePressed: root.cancelled()
    Component.onCompleted: {
      if (root.focusOnShow)
        Qt.callLater(() => entry.input.forceActiveFocus());
    }
  }

  StyledRectButton {
    visible: root.buttonShown
    size: Widget.iconButton
    enabled: root.canSubmit
    opacity: enabled ? 1 : 0.5
    iconText: root.buttonIcon
    iconColor: Theme.accent
    backgroundColor: "transparent"
    borderHoverColor: Theme.accent
    tooltipText: root.buttonTip
    onClicked: root.submitted()
  }
}

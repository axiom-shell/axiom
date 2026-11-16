pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// An entry and the button that submits it, typed inline: a name to add, a
// value to set, a secret (a password, a key, a passphrase: `secret` hides
// the text and keeps input methods out, StyledTextEntry's rule). Enter
// submits too, Escape cancels (the field leaves it to its parents
// otherwise). The button is icon-only unless `buttonText` is set. Callers:
// WifiJoinForm's password, DriveRow's passphrase.
RowLayout {
  id: root

  property alias text: entry.text
  property alias placeholderText: entry.placeholderText
  // The TextInput, for focus
  property alias input: entry.input
  // Hides what's typed
  property bool secret: false
  // The button's label (none: icon alone) and icon, and its tooltip
  property string buttonText: ""
  property string buttonIcon: ""
  property string buttonTip: ""
  // Whether the button can submit (it's dimmed otherwise)
  property bool canSubmit: entry.text !== ""
  // Take the keyboard once built
  property bool focusOnShow: false

  // Enter, or the button
  signal submitted
  // Escape
  signal cancelled

  Layout.fillWidth: true
  spacing: Widget.spacing

  StyledTextEntry {
    id: entry
    Layout.fillWidth: true
    input.wrapMode: Text.NoWrap
    onAccepted: {
      if (root.canSubmit)
        root.submitted();
    }
    // The field leaves Escape to its parents
    Keys.onEscapePressed: root.cancelled()
    Component.onCompleted: {
      if (root.focusOnShow)
        Qt.callLater(() => entry.input.forceActiveFocus());
    }
  }

  // Imperatively: the alias'd TextInput ignores a declarative echoMode
  Binding {
    target: entry.input
    property: "echoMode"
    value: root.secret ? TextInput.Password : TextInput.Normal
  }

  StyledIconButton {
    visible: root.buttonText === ""
    kind: "text"
    size: Widget.iconButton
    enabled: root.canSubmit
    iconText: root.buttonIcon
    iconColor: Style.accent
    tooltipText: root.buttonTip
    onClicked: root.submitted()
  }

  StyledTextButton {
    visible: root.buttonText !== ""
    kind: "tonal"
    text: root.buttonText
    iconText: root.buttonIcon
    enabled: root.canSubmit
    tooltipText: root.buttonTip
    onClicked: root.submitted()
  }
}

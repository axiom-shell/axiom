pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// An entry and the button that submits it, typed inline: a name to add, a
// value to set, a secret (a password, a key, a passphrase: `secret` hides
// the text and keeps input methods out, StyledTextEntry's rule). Enter
// submits too; Escape is `cancelled` only with `escapeCancels`, else it goes
// on to the parents (an overlay's close). `typed` is the field's: text typed
// since it took focus. The button is icon-only unless `buttonText` is set. Callers:
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
  // Escape is `cancelled` and stops here; off, it goes on to the parents
  property bool escapeCancels: false
  // Typed in since the field took focus (StyledTextEntry.typed)
  property alias typed: entry.typed
  // Take the keyboard once built
  property bool focusOnShow: false

  // Enter, or the button
  signal submitted
  // Escape, with `escapeCancels`
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
    // onPressed, not onEscapePressed: connecting that accepts Escape
    Keys.onPressed: event => {
      if (event.key !== Qt.Key_Escape)
        return;
      event.accepted = root.escapeCancels;
      if (root.escapeCancels)
        root.cancelled();
    }
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

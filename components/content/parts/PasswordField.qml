pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.services.session
import qs.components.reusable

// The lock screen's password field: what the Password module draws, and
// LockSurface's own when no Password module shows. Only an `active` field
// (the target screen's, on a real lock) talks to AuthManager and holds the
// keyboard; any other is inert, so a preview or a stray copy can't
// authenticate. PAM's messages show under it, and a failure shakes it.
Item {
  id: root

  property bool active: false
  // Shown in the empty field ("" for Enter password...)
  property string placeholder: ""
  property bool centered: true
  // PAM's prompts, failures and errors under the field
  property bool showMessages: true
  // A slot with no room under the field: messages show in it (see
  // PasswordEntry), and a shorter field
  property bool inlineMessage: false
  property real fieldHeight: Widget.height + Widget.padding
  readonly property real messageRoom: field.messageRoom

  implicitHeight: field.implicitHeight

  function takeFocus() {
    if (root.active)
      field.input.forceActiveFocus();
  }

  Component.onCompleted: {
    if (root.active)
      AuthManager.clearMessage();
    root.takeFocus();
  }
  onActiveChanged: root.takeFocus()

  // Typing always lands here: the lock surface takes every key, and no
  // other lock screen module takes text
  FocusKeeper {
    active: root.active
    holder: field.input
    onReclaim: root.takeFocus()
  }

  Connections {
    target: AuthManager
    enabled: root.active

    function onAuthenticationFailed(reason) {
      field.input.text = "";
      root.takeFocus();
      field.shake();
    }

    function onAuthenticationError(error) {
      field.input.text = "";
      root.takeFocus();
    }
  }

  PasswordEntry {
    id: field
    width: parent.width
    anchors.verticalCenter: parent.verticalCenter
    placeholder: root.placeholder || I18n.tr("Enter password...")
    centered: root.centered
    fieldHeight: root.fieldHeight
    inlineMessage: root.inlineMessage
    reserveMessage: root.showMessages
    readOnly: !root.active
    enabled: !root.active || !AuthManager.isAuthenticating
    message: root.active && root.showMessages ? AuthManager.message : ""
    messageIsError: AuthManager.messageIsError
    busy: root.active && AuthManager.isAuthenticating

    // An inert field lets Escape through (the preview closes on it)
    Keys.onEscapePressed: event => {
      if (!root.active) {
        event.accepted = false;
        return;
      }
      input.text = "";
      AuthManager.clearMessage();
    }

    Keys.onPressed: event => {
      if (event.key === Qt.Key_C && event.modifiers & Qt.ControlModifier) {
        input.text = "";
        AuthManager.clearMessage();
        event.accepted = true;
      }
    }

    onAccepted: {
      if (root.active && input.text.length > 0 && !AuthManager.isAuthenticating) {
        AuthManager.authenticate(input.text);
        input.text = "";
      }
    }
  }
}

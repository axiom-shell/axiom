pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

import qs.config
import qs.services.session
import qs.components.reusable

// The greeter's login box: who logs in (a list of the system's users to
// pick from or type over, or typed only) and the password, with greetd's
// messages under it. What the Login module draws, and GreeterSurface's own
// when no Login module shows. Only an `active` box (the target screen's,
// in the real greeter) talks to GreetdManager and holds the keyboard; any
// other shows the user running the shell and is inert.
Item {
  id: root

  property bool active: false
  // "list": pick a user or type one | "typed": an empty field to type in
  property string userField: "list"
  property bool showAvatar: true
  // Shown in the empty password field ("" for Enter password...)
  property string placeholder: ""
  property bool centered: true
  property bool showMessages: true
  // A slot with no room under the password: messages show in it (see
  // PasswordEntry)
  property bool inlineMessage: false
  readonly property real messageRoom: password.messageRoom
  // The message line kept under the password, which the fields and the
  // avatar line up above
  readonly property real _below: root.showMessages && !root.inlineMessage ? password.messageRoom : 0

  readonly property var user: root.active ? GreetdManager.selectedUser : ({
      "name": Quickshell.env("USER") ?? "",
      "realName": General.displayName
    })
  readonly property string avatar: root.active && root.showAvatar && root.user?.name ? GreetdManager.avatarOf(root.user.name) : ""
  readonly property bool busy: root.active && GreetdManager.busy
  // greetd asked something besides the password (a one-time code)
  readonly property string prompt: root.active ? GreetdManager.prompt : ""

  // A field's full height; a slot too short for one gets it shrunk to fit
  readonly property real rowHeight: Widget.height + Widget.padding
  readonly property real fieldHeight: root.height > 0 ? Math.min(root.rowHeight, root.height) : root.rowHeight
  // The user above the password when there's room for both, else side by
  // side (a one-row slot)
  readonly property bool stacked: root.height <= 0 || root.height >= root.rowHeight * 2 + Widget.spacing

  implicitHeight: column.implicitHeight

  function takeFocus() {
    if (!root.active)
      return;
    if (root.user)
      password.input.forceActiveFocus();
    else
      userPicker.input.forceActiveFocus();
  }

  Component.onCompleted: Qt.callLater(root.takeFocus)
  onActiveChanged: root.takeFocus()

  // Typing always lands in the box: the greeter's window takes every key,
  // and no other greeter module takes text
  FocusKeeper {
    active: root.active
    holder: password.input
    keeps: item => item === userPicker.input
    onReclaim: root.takeFocus()
  }

  Connections {
    target: root.active ? GreetdManager : null

    function onFailed() {
      password.input.text = "";
      password.shake();
      root.takeFocus();
    }
  }

  RowLayout {
    id: column
    width: parent.width
    anchors.verticalCenter: parent.verticalCenter
    spacing: Widget.spacing * 2

    ClippingRectangle {
      visible: root.avatar !== "" && avatarImage.status === Image.Ready
      Layout.preferredWidth: root.stacked ? users.implicitHeight - root._below : root.fieldHeight
      Layout.preferredHeight: Layout.preferredWidth
      Layout.alignment: Qt.AlignTop
      radius: width / 2
      color: Theme.backgroundAlt

      Image {
        id: avatarImage
        anchors.fill: parent
        source: root.avatar
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize: Qt.size(width * 2, height * 2)
      }
    }

    GridLayout {
      id: users
      Layout.fillWidth: true
      columns: root.stacked ? 1 : 2
      rowSpacing: Widget.spacing
      columnSpacing: Widget.spacing

      StyledComboEntry {
        id: userPicker
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.preferredHeight: root.fieldHeight
        Layout.alignment: Qt.AlignTop
        icon: "person"
        editable: true
        readOnly: !root.active
        placeholderText: I18n.tr("User")
        options: root.active && root.userField === "list" ? GreetdManager.users.map(user => ({
              "value": user.name,
              "label": user.realName !== user.name ? I18n.tr("{0} ({1})", user.realName, user.name) : user.name
            })) : []
        value: root.user?.name ?? ""
        onPicked: value => {
          GreetdManager.selectUser(value);
          password.input.text = "";
          if (value)
            password.input.forceActiveFocus();
        }
      }

      PasswordEntry {
        id: password
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        fieldHeight: root.fieldHeight
        inlineMessage: root.inlineMessage
        reserveMessage: root.showMessages
        placeholder: root.prompt || root.placeholder || I18n.tr("Enter password...")
        centered: root.centered
        reveal: root.active && root.prompt !== "" && GreetdManager.promptEcho
        readOnly: !root.active
        enabled: !root.busy
        message: root.active && root.showMessages ? GreetdManager.message : ""
        messageIsError: root.active && GreetdManager.messageIsError
        busy: root.busy

        // An inert field lets Escape through (the preview closes on it)
        Keys.onEscapePressed: event => {
          if (!root.active) {
            event.accepted = false;
            return;
          }
          input.text = "";
          GreetdManager.cancel();
        }

        onAccepted: {
          if (!root.active || root.busy)
            return;
          if (!GreetdManager.selectedUser) {
            userPicker.input.forceActiveFocus();
            return;
          }
          GreetdManager.submit(input.text);
          input.text = "";
        }
      }
    }
  }
}

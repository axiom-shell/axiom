pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.config

// A password field with what an authenticator shows under it: a message,
// a sliding bar while it checks, and a shake when it fails, and that Caps
// Lock is on while nothing else is said (the field's own hint). It knows no
// authenticator: the lock screen's PasswordField and the polkit prompt
// wire it to theirs (`accepted`, `shake()`).
Item {
  id: root

  // The TextInput, for focus and text
  readonly property TextField input: entry.input
  property string placeholder: ""
  property bool centered: true
  property bool readOnly: false
  // Shows what's typed instead of dots
  property bool reveal: false
  property string message: ""
  property bool messageIsError: false
  property bool wrapMessage: false
  // Checking: the sliding bar shows
  property bool busy: false
  // The field's own height (the greeter's login box shrinks it to a short
  // slot)
  property real fieldHeight: Widget.height + Widget.padding
  // The message line's room is kept while it's empty, so the field doesn't
  // move when one shows
  property bool reserveMessage: false
  // A slot with no room under the field: the message shows in the empty
  // field (it's emptied after a failure) instead, and only the field takes
  // room
  property bool inlineMessage: false
  // The message line says Caps Lock is on while it has nothing else to say
  // (off where the host shows no messages: the line would push the field)
  property bool capsMessage: true
  // What a message line under the field takes, shown or not (for a host
  // deciding on inlineMessage)
  readonly property real messageRoom: body.spacing + messageMetrics.height

  // What the line says: the message, else the Caps Lock warning
  readonly property bool _capsWarning: root.capsMessage && root.message === "" && entry.capsHintShown
  readonly property string _line: root._capsWarning ? I18n.tr("Caps Lock is on") : root.message
  readonly property color _lineColor: root._capsWarning ? Theme.warning : root.messageIsError ? Theme.error : Theme.foregroundAlt

  signal accepted

  implicitHeight: body.implicitHeight

  function shake() {
    shakeAnimation.restart();
  }

  Column {
    id: body
    width: parent.width
    anchors.verticalCenter: parent.verticalCenter
    spacing: Widget.padding / 2

    StyledTextEntry {
      id: entry
      width: parent.width
      height: root.fieldHeight
      placeholderText: root.inlineMessage && root._line !== "" ? root._line : root.placeholder
      input.passwordCharacter: "•"
      input.passwordMaskDelay: 0
      input.horizontalAlignment: root.centered ? Text.AlignHCenter : Text.AlignLeft
      readOnly: root.readOnly
      onAccepted: root.accepted()
    }

    // Imperatively: the alias'd TextInput ignores a declarative echoMode
    Binding {
      target: entry.input
      property: "echoMode"
      value: root.reveal ? TextInput.Normal : TextInput.Password
    }

    // An inline message in its color
    Binding {
      when: root.inlineMessage && root._line !== ""
      target: entry.input
      property: "placeholderTextColor"
      value: root._lineColor
    }

    StyledText {
      id: messageText
      width: parent.width
      visible: !root.inlineMessage && (root._line !== "" || root.reserveMessage)
      // A space keeps a reserved line's height
      text: root._line || " "
      textColor: root._lineColor
      textSize: Appearance.fontSizeBy(-2)
      horizontalAlignment: root.centered ? Text.AlignHCenter : Text.AlignLeft
      wrapMode: root.wrapMessage ? Text.WordWrap : Text.NoWrap
      elide: root.wrapMessage ? Text.ElideNone : Text.ElideRight
    }
  }

  FontMetrics {
    id: messageMetrics
    font: messageText.font
  }

  // Checking: a bar sliding along the field's bottom edge, over it, so
  // nothing moves when it shows
  Item {
    id: busyTrack
    readonly property real inset: Math.min(entry.radius, entry.height / 2)
    x: body.x + busyTrack.inset
    y: body.y + entry.y + entry.height - height - Appearance.borderWidth - 1
    width: entry.width - busyTrack.inset * 2
    height: Widget.px(3)
    visible: root.busy
    clip: true

    StyledContainer {
      width: parent.width * 0.3
      height: parent.height
      radius: height / 2
      backgroundColor: Theme.accent

      SequentialAnimation on x {
        loops: Animation.Infinite
        running: root.busy && Appearance.animations

        NumberAnimation {
          from: 0
          to: busyTrack.width * 0.7
          duration: Appearance.animSlow * 3
          easing.type: Easing.InOutQuad
        }
        NumberAnimation {
          from: busyTrack.width * 0.7
          to: 0
          duration: Appearance.animSlow * 3
          easing.type: Easing.InOutQuad
        }
      }
    }
  }

  SequentialAnimation {
    id: shakeAnimation

    NumberAnimation {
      target: body
      property: "x"
      to: 20
      duration: Appearance.animFast
    }
    NumberAnimation {
      target: body
      property: "x"
      to: -20
      duration: Appearance.animFast
    }
    NumberAnimation {
      target: body
      property: "x"
      to: 20
      duration: Appearance.animFast
    }
    NumberAnimation {
      target: body
      property: "x"
      to: 0
      duration: Appearance.animFast
    }
  }
}

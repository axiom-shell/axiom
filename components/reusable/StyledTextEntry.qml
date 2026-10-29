pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.config

// A single-line text field in a StyledContainer. It writes every keystroke
// back to `text`: push values in and act on textEdited (see AGENTS.md pitfalls).
// `clearable` (search boxes) adds an X at the right while it holds text,
// which empties it as a typed edit and keeps the focus in it; with
// `escapeClears`, Escape does too (passed on when it's already empty).
StyledContainer {
  id: root

  // --- Public API ---
  property string text: ""
  property alias placeholderText: textField.placeholderText
  property alias input: textField
  property alias readOnly: textField.readOnly

  signal accepted
  // Typed (or put in by the input method): never a value pushed in through
  // `text`. What a field that writes config acts on, rather than its text
  // changing while it has focus, which a value pushed in does too
  signal textEdited
  // Typed in since it took focus. An owner that commits on focus loss
  // checks it, so text it was left showing (what it edits switched under
  // it) isn't written onto what it edits now, and clears it once it has
  // committed or pushed a value in
  property bool typed: false
  // An X at the right, while there's text, that clears it
  property bool clearable: false
  // Escape clears it too, or goes on to the parent when it's empty
  property bool escapeClears: false
  readonly property bool _clearShown: root.clearable && !root.readOnly && textField.text !== ""

  // Empties the field as if typed (textEdited), keeping its focus.
  // TextInput.clear(), not an assignment, which would drop the field's
  // `text: root.text` binding and leave later pushes unshown
  function clear() {
    textField.clear();
    root.typed = true;
    root.textEdited();
    textField.forceActiveFocus();
  }

  implicitHeight: textField.implicitHeight + Widget.padding * 2
  borderColor: textField.activeFocus ? Theme.accent : Theme.border
  backgroundColor: Theme.backgroundAlt

  Behavior on borderColor {
    ColorAnimation {
      duration: Appearance.animNormal
      easing.type: Easing.InOutQuad
    }
  }

  TextField {
    id: textField
    anchors.fill: parent
    anchors.leftMargin: Widget.padding
    anchors.rightMargin: root._clearShown ? clearButton.width + clearButton.inset + Widget.spacing : Widget.padding
    verticalAlignment: TextInput.AlignVCenter
    text: root.text
    onTextChanged: root.text = text
    // TextInput emits textEdited before textChanged: `text` is brought up
    // to date first, or a handler reading it gets the text before the edit
    onTextEdited: {
      root.text = text;
      root.typed = true;
      root.textEdited();
    }
    onActiveFocusChanged: {
      if (activeFocus)
        root.typed = false;
    }
    // onPressed, not onEscapePressed: connecting that would accept Escape
    // on every entry, and a caller's own input.Keys handler shares this
    // object. Untouched (passed on) unless it clears
    Keys.onPressed: event => {
      if (event.key === Qt.Key_Escape && root.escapeClears && textField.text !== "") {
        root.clear();
        event.accepted = true;
      }
    }

    // --- Core Properties ---
    color: Theme.foreground
    font.family: Appearance.fontFamily
    font.pixelSize: Appearance.fontSize
    selectByMouse: true
    selectedTextColor: Theme.background
    selectionColor: Theme.accent
    wrapMode: Text.Wrap

    // --- Placeholder Properties ---
    placeholderTextColor: Qt.alpha(Theme.foreground, 0.5)

    onAccepted: root.accepted()

    background: Rectangle {
      color: "transparent"
    }

    cursorDelegate: Rectangle {
      width: 2
      color: Theme.accent
      visible: textField.activeFocus

      // Blinking animation
      SequentialAnimation on opacity {
        loops: Animation.Infinite
        running: textField.activeFocus
        // Cursor blink: a behaviour timing, not motion, so not scaled
        PropertyAnimation {
          to: 1
          duration: 500
        }
        PropertyAnimation {
          to: 0
          duration: 500
        }
      }
    }
  }

  FlatIconButton {
    id: clearButton
    visible: root._clearShown
    // Inset from the border all round, so its hover fill never covers it
    readonly property real inset: Appearance.borderWidth + Widget.px(4)
    size: Math.min(Widget.iconButton, root.height - inset * 2)
    anchors.right: parent.right
    anchors.rightMargin: inset
    anchors.verticalCenter: parent.verticalCenter
    focusPolicy: Qt.NoFocus
    iconText: "close"
    iconSize: Appearance.fontSizeBy(1)
    tooltipText: I18n.tr("Clear")
    onClicked: root.clear()
  }
}

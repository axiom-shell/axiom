pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.config

// A single-line text field in a StyledContainer. It writes every keystroke
// back to `text`: push values in and act on textEdited (see docs/dev/core/qml-pitfalls.md).
// `clearable` (search boxes) adds an X at the right while it holds text,
// which empties it as a typed edit and keeps the focus in it; with
// `escapeClears`, Escape does too (passed on when it's already empty).
// A field hiding its text (a password) warns while Caps Lock is on, by
// itself: CapsLockHint at the right, loaded only while it has focus.
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
  // Caps Lock is on while it takes hidden text (PasswordEntry's message
  // line says so too)
  readonly property bool capsHintShown: root._capsHint?.shown === true
  readonly property real _capsRoom: root._capsHint?.visible ? capsHint.width + Widget.spacing : 0
  readonly property CapsLockHint _capsHint: capsHint.item as CapsLockHint

  // Empties the field as if typed (textEdited), keeping its focus.
  // TextInput.clear(), not an assignment, which would drop the field's
  // `text: root.text` binding and leave later pushes unshown
  function clear() {
    textField.clear();
    root.typed = true;
    root.textEdited();
    textField.forceActiveFocus();
  }

  // A combo's height (Widget.height), growing as long text wraps; the
  // TextField's own padding is zeroed, so the box's is the only one
  implicitHeight: Math.max(Widget.height, textField.contentHeight + Widget.spacing * 2)
  borderColor: textField.activeFocus ? Theme.accent : Theme.border
  backgroundColor: Theme.backgroundAlt

  ColorGlide on borderColor {
    duration: Appearance.animNormal
  }

  TextField {
    id: textField
    anchors.fill: parent
    anchors.leftMargin: Widget.padding
    anchors.rightMargin: (root._clearShown ? clearButton.width + clearButton.inset + Widget.spacing : Widget.padding) + root._capsRoom
    verticalAlignment: TextInput.AlignVCenter
    topPadding: 0
    bottomPadding: 0
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

    cursorDelegate: TextCursor {}
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

  // Only while hidden text is typed into it: the key is polled while a
  // hint exists
  Loader {
    id: capsHint
    active: textField.echoMode !== TextInput.Normal && textField.activeFocus && !root.readOnly
    anchors.right: root._clearShown ? clearButton.left : parent.right
    anchors.rightMargin: root._clearShown ? Widget.spacing : clearButton.inset + Widget.px(2)
    anchors.verticalCenter: parent.verticalCenter
    sourceComponent: CapsLockHint {}
  }
}

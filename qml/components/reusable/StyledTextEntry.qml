pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.config
import qs.components.methods

// A single-line text field in a FieldFrame (a caller makes it
// frameless with `color: "transparent"; outlined: false`). It writes every keystroke
// back to `text`: push values in and act on textEdited (see docs/dev/core/qml-pitfalls.md).
// `clearable` (search boxes) adds an X at the right while it holds text,
// which empties it as a typed edit and keeps the focus in it; with
// `escapeClears`, Escape does too (passed on when it's already empty).
// A field hiding its text (`input.echoMode` not Normal: a password, a key,
// a passphrase) warns while Caps Lock is on, by itself: CapsLockHint at the
// right, loaded only while it has focus, and keeps every input method out
// (sensitive, no prediction, hidden; bullets with no delay on the last key).
FieldFrame {
  id: root

  // --- Public API ---
  property string text: ""
  property alias placeholderText: textField.placeholderText
  property alias input: textField
  property alias readOnly: textField.readOnly
  // Holds a secret: no input method sees or predicts it (sensitive, no
  // prediction, hidden hints). By default whatever hides its text; a field
  // that can reveal what it holds (PasswordEntry) sets it true
  property bool sensitive: textField.echoMode !== TextInput.Normal

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
  active: textField.activeFocus

  TextField {
    id: textField
    renderType: TextRender.typeFor(TextRender.zoomAt(parent), false, 0)
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
    color: root.ink.text
    font.family: Appearance.fontFamily
    font.pixelSize: Style.typeBody
    selectByMouse: true
    selectedTextColor: Style.inkAccent.text
    selectionColor: Style.accent
    wrapMode: Text.Wrap
    // No input method sees or predicts hidden text (input sources: a
    // password types through the compositor's layout alone). A caller that
    // adds to the hints (digits) assigns over this
    inputMethodHints: root.sensitive ? (Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhHiddenText) : Qt.ImhNone
    passwordCharacter: "•"
    passwordMaskDelay: 0

    // --- Placeholder Properties ---
    placeholderTextColor: root.ink.faint

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
    readonly property real inset: Style.hairline + Widget.px(4)
    size: Math.min(Widget.iconButton, root.height - inset * 2)
    anchors.right: parent.right
    anchors.rightMargin: inset
    anchors.verticalCenter: parent.verticalCenter
    focusPolicy: Qt.NoFocus
    iconText: "close"
    iconSize: Style.iconSm
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

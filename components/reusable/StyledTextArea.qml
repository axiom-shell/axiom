pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.config

// A multi-line text field in a StyledContainer, optionally growing with its
// text. Pushed-in values follow the StyledTextEntry pattern (textEdited).
// `singleLine` makes it a one-line value that wraps instead (a command): no
// line breaks, Enter submits, Tab moves on.
StyledContainer {
  id: root

  // --- Public API ---
  property string text: ""
  property alias placeholderText: textInput.placeholderText
  property alias input: textInput
  property alias readOnly: textInput.readOnly
  property bool expandable: false
  // Expandable only: Enter is a new line and Ctrl+Enter submits, instead
  // of Enter submitting and Shift+Enter being a new line
  property bool newlineOnEnter: false
  // One line of text, wrapped to show it whole: typed or pasted line
  // breaks become spaces, a box one line tall is as tall as a
  // StyledTextEntry
  property bool singleLine: false
  // Expandable only: grows to this many lines, then scrolls (0: no cap)
  property int maxLines: 0
  readonly property real lineHeight: metrics.lineSpacing
  // Space around the text
  property int horizontalMargin: Widget.padding
  property int verticalMargin: root.singleLine ? Math.max(0, Math.round((Widget.height - root.lineHeight) / 2)) : Widget.padding
  property int minHeight: root.singleLine ? Widget.height : Widget.height + Widget.padding

  signal accepted
  // Typed (or put in by the input method): never a value pushed in through
  // `text` (as StyledTextEntry's)
  signal textEdited

  implicitHeight: {
    if (!expandable)
      return textInput.implicitHeight + root.verticalMargin * 2;

    const shown = root.maxLines > 0 ? Math.min(textInput.contentHeight, root.maxLines * root.lineHeight) : textInput.contentHeight;
    return Math.max(root.minHeight, Math.ceil(shown) + root.verticalMargin * 2);
  }

  borderColor: textInput.activeFocus ? Theme.accent : Theme.border
  backgroundColor: Theme.backgroundAlt

  Behavior on borderColor {
    ColorAnimation {
      duration: Appearance.animNormal
      easing.type: Appearance.easing
    }
  }

  Behavior on implicitHeight {
    NumberAnimation {
      duration: Appearance.animNormal
      easing.type: Appearance.easing
    }
  }

  FontMetrics {
    id: metrics
    font: textInput.font
  }

  Flickable {
    id: flickable
    anchors.fill: parent
    anchors.leftMargin: root.horizontalMargin
    anchors.rightMargin: root.horizontalMargin
    anchors.topMargin: root.verticalMargin
    anchors.bottomMargin: root.verticalMargin

    contentWidth: textInput.contentWidth
    contentHeight: textInput.contentHeight
    clip: true

    // Scrolls only past `maxLines`: a field that fits leaves the wheel to
    // the page around it
    interactive: root.expandable && flickable.contentHeight > flickable.height

    TextArea {
      id: textInput
      width: flickable.width
      // The margins above are the only space around the text: the style's
      // own padding would push it off-centre
      padding: 0
      text: root.text
      // A change that isn't `text` arriving was made in the field itself
      // (TextEdit has no textEdited of its own)
      onTextChanged: {
        if (text === root.text)
          return;
        // A pasted line break becomes a space. Through `root.text`, not
        // `text`: assigning that would drop its binding, and a value pushed
        // in later (a reset, a suggestion) would never show
        if (root.singleLine && /[\r\n]/.test(text)) {
          const at = cursorPosition;
          root.text = text.replace(/\r\n|\r|\n/g, " ");
          cursorPosition = Math.min(at, text.length);
        } else {
          root.text = text;
        }
        root.textEdited();
      }

      // --- Core Properties ---
      color: Theme.foreground
      font.family: Appearance.fontFamily
      font.pixelSize: Appearance.fontSize
      selectByMouse: true
      selectedTextColor: Theme.background
      selectionColor: Theme.accent
      wrapMode: root.expandable ? TextEdit.Wrap : TextEdit.NoWrap
      // Past `maxLines`, the line being typed stays in view
      onCursorRectangleChanged: {
        const top = cursorRectangle.y;
        const bottom = top + cursorRectangle.height;
        if (top < flickable.contentY)
          flickable.contentY = top;
        else if (bottom > flickable.contentY + flickable.height)
          flickable.contentY = bottom - flickable.height;
      }

      // --- Placeholder Properties ---
      placeholderTextColor: Qt.alpha(Theme.foreground, 0.5)

      // Handle Enter/Return key
      Keys.onPressed: event => {
        // One line: Tab moves on, as from a StyledTextEntry, rather than
        // typing a tab
        if (root.singleLine && (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)) {
          const next = textInput.nextItemInFocusChain(event.key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier));
          if (next)
            next.forceActiveFocus(event.key === Qt.Key_Tab ? Qt.TabFocusReason : Qt.BacktabFocusReason);
          event.accepted = true;
          return;
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          if (root.singleLine) {
            // Never a new line
            root.accepted();
            event.accepted = true;
          } else if (root.expandable && root.newlineOnEnter) {
            // Ctrl+Enter submits; Enter (with or without Shift) is a new line
            if (event.modifiers & Qt.ControlModifier) {
              root.accepted();
              event.accepted = true;
            } else {
              event.accepted = false;
            }
          } else if (root.expandable && (event.modifiers & Qt.ShiftModifier)) {
            // Shift+Enter in expandable mode: a new line
            event.accepted = false;
          } else {
            // Enter submits
            root.accepted();
            event.accepted = true;
          }
        }
      }

      background: Rectangle {
        color: "transparent"
      }

      // An accent bar, blinking while focused
      cursorDelegate: Rectangle {
        width: 2
        color: Theme.accent
        visible: textInput.activeFocus

        SequentialAnimation on opacity {
          loops: Animation.Infinite
          running: textInput.activeFocus
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
  }
}

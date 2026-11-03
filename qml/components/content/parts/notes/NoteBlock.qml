pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods
import qs.components.reusable

// One block of a NoteEditor: a paragraph, or a task line with its checkbox.
// While focused it edits the raw Markdown; otherwise it shows it rendered
// (a click there edits at about that spot, or opens a link). It reads its
// block from the editor on load() (not by binding), so typing never
// rebuilds anything.
Item {
  id: root

  required property int index
  required property var editor

  property string kind: "text"
  property bool checked: false
  property int depth: 0
  readonly property alias field: textEdit
  readonly property bool isTask: root.kind === "task"
  readonly property bool shown: !(root.isTask && root.checked && !root.editor.showCompleted)
  // The editor's find match, when it's in this block
  readonly property var _match: root.editor.findMatch?.block === root.index ? root.editor.findMatch : null
  // Edited (or showing a find match) as raw Markdown; otherwise rendered
  readonly property bool editing: textEdit.activeFocus || root._match !== null

  // The rendered layer's text: a paragraph as Markdown, a task's text with
  // its inline formatting only (a leading "#" or "1." stays literal)
  readonly property string _markdown: root.isTask ? textEdit.text.replace(/^(\s*)(#|>|[-*+]\s|\d+[.)]\s)/, "$1\\$2") : textEdit.text
  // Blank lines before and after a paragraph, which Markdown drops: a gap
  readonly property var _lines: textEdit.text.split("\n")
  readonly property bool _blankBefore: root._lines.length > 1 && root._lines[0].trim() === "" && textEdit.text.trim() !== ""
  readonly property bool _blankAfter: root._lines.length > 1 && root._lines[root._lines.length - 1].trim() === "" && textEdit.text.trim() !== ""

  visible: root.shown
  width: parent?.width ?? 0
  implicitHeight: !root.shown ? 0 : root.editing ? textEdit.implicitHeight : textEdit.text.trim() === "" ? textEdit.lineHeight : rendered.implicitHeight

  function load() {
    const block = root.editor.doc.blocks[root.index];
    if (!block)
      return;
    root.kind = block.kind;
    root.checked = NoteMarkdown.isChecked(block);
    root.depth = block.kind === "task" ? Math.floor(block.indent.replace(/\t/g, "  ").length / 2) : 0;
    if (textEdit.text !== block.text)
      textEdit.text = block.text;
  }

  function focusAt(pos) {
    textEdit.forceActiveFocus();
    textEdit.cursorPosition = Math.max(0, Math.min(pos, textEdit.length));
  }

  Component.onCompleted: root.load()

  Connections {
    target: root.editor
    function onRestructured() {
      root.load();
    }
  }

  StyledIcon {
    id: box
    visible: root.isTask
    x: root.depth * Appearance.fontSize * 1.5
    // Centred on the first line
    y: Math.max(0, (textEdit.lineHeight - height) / 2)
    text: root.checked ? "check_box" : "check_box_outline_blank"
    fill: root.checked ? 1 : 0
    textColor: root.checked ? Theme.accent : Theme.foregroundAlt
    textSize: Appearance.fontSizeBy(4)

    // A MouseArea, not a TapHandler: it accepts the press, so the editor's
    // background MouseArea (which focuses the note's end) never sees it. An
    // exclusive-grab TapHandler is cancelled by the ScrollView's Flickable,
    // and a passive one lets the press through
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: root.editor.toggle(root.index)
    }
  }

  // The find match, under the text (to the line's end when it wraps)
  Rectangle {
    readonly property rect start: root._match ? textEdit.positionToRectangle(root._match.pos) : Qt.rect(0, 0, 0, 0)
    readonly property rect end: root._match ? textEdit.positionToRectangle(root._match.pos + root._match.len) : Qt.rect(0, 0, 0, 0)
    visible: root._match !== null
    x: textEdit.x + start.x
    y: start.y
    width: end.y === start.y ? end.x - start.x : textEdit.width - start.x
    height: start.height
    radius: 2
    color: Qt.alpha(Theme.accent, 0.35)
  }

  TextEdit {
    id: textEdit

    // One line's height, for the checkbox
    readonly property real lineHeight: fontMetrics.height

    x: root.isTask ? box.x + box.width + Widget.spacing / 2 : 0
    width: root.width - x
    // Hidden under the rendered text, and no taller than it there, so it
    // takes no clicks meant for the blocks below
    height: root.editing ? implicitHeight : Math.min(implicitHeight, root.height)
    opacity: root.editing ? 1 : 0
    wrapMode: TextEdit.Wrap
    textFormat: TextEdit.PlainText
    color: root.checked ? Theme.foregroundAlt : Theme.foreground
    font.family: Appearance.fontFamily
    font.pixelSize: Appearance.fontSize
    font.strikeout: root.checked
    selectByMouse: true
    selectionColor: Theme.accent
    selectedTextColor: Theme.background

    FontMetrics {
      id: fontMetrics
      font: textEdit.font
    }

    // A click on the rendered text edits the block at about that spot
    function editAt(x, y) {
      root.focusAt(textEdit.positionAt(x, y));
    }

    onTextChanged: root.editor.blockEdited(root.index, text)
    onActiveFocusChanged: {
      if (activeFocus) {
        root.editor.focusBlock = root.index;
        root.editor.focusPos = cursorPosition;
      }
    }
    onCursorPositionChanged: {
      if (activeFocus)
        root.editor.focusPos = cursorPosition;
    }
    onCursorRectangleChanged: {
      if (activeFocus)
        root.editor.ensureVisible(root.index, cursorPosition);
    }

    Keys.onPressed: event => {
      const plain = !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.ShiftModifier));
      const noSelection = textEdit.selectedText === "";
      switch (event.key) {
      case Qt.Key_Return:
      case Qt.Key_Enter:
        if (event.modifiers & Qt.ControlModifier) {
          // Ctrl+Enter checks a task off
          if (root.isTask) {
            root.editor.toggle(root.index);
            event.accepted = true;
          }
        } else if (root.isTask) {
          root.editor.splitTask(root.index, textEdit.cursorPosition);
          event.accepted = true;
        } else if (!(event.modifiers & Qt.ShiftModifier)) {
          event.accepted = root.editor.continueList(textEdit);
        }
        break;
      case Qt.Key_Backspace:
        if (plain && noSelection && textEdit.cursorPosition === 0 && (root.isTask || root.index > 0)) {
          root.editor.mergeBack(root.index);
          event.accepted = true;
        }
        break;
      case Qt.Key_Delete:
        if (plain && noSelection && textEdit.cursorPosition === textEdit.length && root.index < root.editor.blockCount - 1) {
          root.editor.joinNext(root.index);
          event.accepted = true;
        }
        break;
      case Qt.Key_Tab:
      case Qt.Key_Backtab:
        if (root.isTask) {
          root.editor.indentTask(root.index, event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) ? -1 : 1);
          event.accepted = true;
        }
        break;
      case Qt.Key_F:
        if (event.modifiers & Qt.ControlModifier) {
          root.editor.findRequested(textEdit.selectedText);
          event.accepted = true;
        }
        break;
      case Qt.Key_Up:
        if (plain && textEdit.cursorRectangle.y < textEdit.lineHeight / 2)
          event.accepted = root.editor.focusNeighbour(root.index, -1);
        break;
      case Qt.Key_Down:
        if (plain && textEdit.cursorRectangle.y + textEdit.cursorRectangle.height > textEdit.contentHeight - textEdit.lineHeight / 2)
          event.accepted = root.editor.focusNeighbour(root.index, 1);
        break;
      }
    }
  }

  Text {
    id: rendered
    visible: !root.editing
    x: textEdit.x
    width: textEdit.width
    topPadding: root._blankBefore ? textEdit.lineHeight / 2 : 0
    bottomPadding: root._blankAfter ? textEdit.lineHeight / 2 : 0
    text: root._markdown
    textFormat: Text.MarkdownText
    wrapMode: Text.Wrap
    color: textEdit.color
    linkColor: Theme.accent
    font.family: Appearance.fontFamily
    font.pixelSize: Appearance.fontSize
    font.strikeout: root.checked

    HoverHandler {
      cursorShape: rendered.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.IBeamCursor
    }
    // A MouseArea, like the checkbox's, so neither the hidden field nor the
    // editor's background MouseArea sees the press
    MouseArea {
      anchors.fill: parent
      onClicked: mouse => {
        const link = rendered.linkAt(mouse.x, mouse.y);
        if (link !== "")
          Qt.openUrlExternally(link);
        else
          textEdit.editAt(mouse.x, mouse.y - rendered.topPadding);
      }
    }
  }
}

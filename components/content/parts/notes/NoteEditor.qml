pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods
import qs.components.reusable

// Edits one note (a NotesManager document) as NoteMarkdown blocks: plain
// text, and task lines with checkboxes. Typing only changes its own block;
// Enter, Backspace/Delete across blocks, toggles and the toolbar are
// structural edits, which re-read every block in place (the Repeater is
// modelled by a count, so its delegates survive).
Item {
  id: root

  // The NotesManager document, or null
  property var note: null
  property bool showCompleted: true
  property string placeholderText: I18n.tr("Write something…")

  property var doc: NoteMarkdown.parse("")
  property int blockCount: 0
  // Tasks checked / all, updated on structural edits
  property var progress: ({
      "done": 0,
      "total": 0
    })
  // The block last focused and its cursor, for the toolbar (-1: none)
  property int focusBlock: -1
  property int focusPos: 0

  // Find in note: the match shown ({ block, pos, len }, whose block shows
  // raw with it highlighted), or null; its index among findCount matches
  property var findMatch: null
  property int findIndex: -1
  property int findCount: 0

  signal restructured
  // Ctrl+F in a block, with its selected text
  signal findRequested(string text)

  // What this editor last wrote or read, so its own edits don't reload it
  property string _lastText: ""
  readonly property string _noteText: root.note?.text ?? ""
  // A line to show once the note has loaded (revealLine), or -1
  property int _pendingLine: -1

  on_NoteTextChanged: {
    if (root._noteText !== root._lastText)
      root._load();
  }
  onNoteChanged: {
    root.focusBlock = -1;
    root.findMatch = null;
    root._load();
  }
  Component.onCompleted: root._load()

  // An empty note loads without its text changing
  Connections {
    target: root.note
    function onLoadedChanged() {
      root._revealPending();
    }
  }

  // ScrollView's own Flickable, for scrolling to the cursor
  readonly property Flickable _flick: scroll.contentItem as Flickable

  function _block(index: int): NoteBlock {
    return repeater.itemAt(index) as NoteBlock;
  }

  function _load() {
    root._lastText = root._noteText;
    root._set(NoteMarkdown.parse(root._noteText), null);
    root._revealPending();
  }

  // Puts the cursor at the start of a line of the note (0-based), once it
  // has loaded: a search result
  function revealLine(line) {
    root._pendingLine = line;
    root._revealPending();
  }

  function _revealPending() {
    if (root._pendingLine < 0 || !root.note?.loaded)
      return;
    const at = NoteMarkdown.positionAt(root.doc, root._pendingLine, 0);
    root._pendingLine = -1;
    // A jump to the line, not back to where the note was left
    memory.cancel();
    // After the blocks have been laid out
    Qt.callLater(() => root.focusAt(at.block, at.pos));
  }

  // --- Find ---

  function _matches(query) {
    const q = String(query ?? "").toLowerCase();
    const matches = [];
    if (q === "")
      return matches;
    root.doc.blocks.forEach((block, index) => {
      if (root._block(index)?.shown === false)
        return;
      const text = block.text.toLowerCase();
      for (let at = text.indexOf(q); at >= 0; at = text.indexOf(q, at + q.length))
        matches.push({
          "block": index,
          "pos": at,
          "len": q.length
        });
    });
    return matches;
  }

  // Shows a match of `query`: with step 0 the one at or after the current
  // match (or the cursor), else the next (1) or previous (-1) one
  function find(query, step) {
    const matches = root._matches(query);
    root.findCount = matches.length;
    if (matches.length === 0) {
      root.findMatch = null;
      root.findIndex = -1;
      return;
    }
    const from = root.findMatch ?? {
      "block": Math.max(0, root.focusBlock),
      "pos": root.focusBlock >= 0 ? root.focusPos : 0
    };
    const after = m => m.block > from.block || (m.block === from.block && m.pos >= from.pos);
    let i = matches.findIndex(after);
    if (i < 0)
      i = step < 0 ? matches.length : 0;
    const onCurrent = root.findMatch !== null && i < matches.length && matches[i].block === from.block && matches[i].pos === from.pos;
    if (step > 0 && onCurrent)
      i += 1;
    else if (step < 0)
      i -= 1;
    i = (i + matches.length) % matches.length;
    root.findIndex = i;
    root.findMatch = matches[i];
    Qt.callLater(root._scrollToMatch);
  }

  function _scrollToMatch() {
    const match = root.findMatch;
    if (match) {
      memory.cancel();
      root.ensureVisible(match.block, match.pos);
    }
  }

  // Closes find; with `select`, the match is selected for editing
  function endFind(select) {
    const match = root.findMatch;
    root.findMatch = null;
    root.findIndex = -1;
    root.findCount = 0;
    const item = match && select ? root._block(match.block) : null;
    if (item) {
      item.focusAt(match.pos);
      item.field.select(match.pos, match.pos + match.len);
    }
  }

  function _set(doc, focus) {
    root.doc = doc;
    root.progress = NoteMarkdown.progress(doc);
    root.blockCount = doc.blocks.length;
    root.restructured();
    if (focus)
      root.focusAt(focus.block, focus.pos);
  }

  function _commit() {
    const text = NoteMarkdown.serialize(root.doc);
    root._lastText = text;
    root.note?.edit(text);
  }

  // A structural edit's { doc, focus }
  function apply(result) {
    root._set(result.doc, result.focus);
    root._commit();
  }

  function focusAt(index, pos) {
    const item = root._block(index);
    if (item)
      item.focusAt(pos);
  }

  // Focus the note's end (a click below the text)
  function focusEnd() {
    const last = root.blockCount - 1;
    const item = root._block(last);
    if (item)
      item.focusAt(item.field.length);
  }

  // Up/Down past a block's first or last line: the next shown block
  function focusNeighbour(index, step) {
    for (let i = index + step; i >= 0 && i < root.blockCount; i += step) {
      const item = root._block(i);
      if (item?.shown) {
        // Keep the cursor's column, across a checkbox's indent
        const from = root._block(index)?.field;
        const x = (from ? from.x + from.cursorRectangle.x : 0) - item.field.x;
        item.field.forceActiveFocus();
        item.field.cursorPosition = item.field.positionAt(x, step > 0 ? 1 : item.field.contentHeight - 1);
        return true;
      }
    }
    return false;
  }

  // Scrolls a block's position (its cursor, a match) into view, once the
  // blocks have been laid out: a structural edit reloads every block and
  // adds new ones at the end, so until then their y is stale (a new last
  // block's is 0, which scrolled to the top)
  property var _visible: null
  function ensureVisible(index, pos) {
    root._visible = {
      "block": index,
      "pos": pos
    };
    Qt.callLater(root._scrollToVisible);
  }

  function _scrollToVisible() {
    const at = root._visible;
    root._visible = null;
    const item = at ? root._block(at.block) : null;
    if (!item)
      return;
    blocks.forceLayout();
    const flick = root._flick;
    const rect = item.field.positionToRectangle(at.pos);
    const top = item.y + rect.y;
    const bottom = top + rect.height;
    if (top < flick.contentY)
      flick.contentY = top;
    else if (bottom > flick.contentY + flick.height)
      flick.contentY = bottom - flick.height;
  }

  // Where each note was left (EditsManager, by path), so reopening it
  // comes back there
  ScrollMemory {
    id: memory
    flickable: root._flick
    key: root.note ? "notes:" + root.note.path : ""
  }

  // --- From the blocks ---

  function blockEdited(index, text) {
    const block = root.doc.blocks[index];
    if (!block || block.text === text)
      return;
    if (block.kind === "task" && text.includes("\n")) {
      // Pasted lines: a task stays one line
      root.apply({
        "doc": NoteMarkdown.setText(root.doc, index, text),
        "focus": {
          "block": index,
          "pos": text.length
        }
      });
      return;
    }
    block.text = text;
    if (block.kind === "text" && NoteMarkdown.needsReparse(text)) {
      // "- [ ] " typed (or pasted): the line becomes a checkbox; text
      // after a blank line: a new paragraph
      const item = root._block(index);
      root.apply(NoteMarkdown.reparse(root.doc, index, item ? item.field.cursorPosition : text.length));
      return;
    }
    root._commit();
  }

  function toggle(index) {
    root.apply(NoteMarkdown.toggle(root.doc, index));
  }

  function splitTask(index, pos) {
    root.apply(NoteMarkdown.splitTask(root.doc, index, pos));
  }

  function mergeBack(index) {
    root.apply(NoteMarkdown.mergeBack(root.doc, index));
  }

  function joinNext(index) {
    root.apply(NoteMarkdown.joinNext(root.doc, index));
  }

  function indentTask(index, delta) {
    const pos = root._block(index)?.field.cursorPosition ?? 0;
    const result = NoteMarkdown.indentTask(root.doc, index, delta);
    result.focus = {
      "block": index,
      "pos": pos
    };
    root.apply(result);
  }

  // Enter in a plain list line continues the list, and on an empty item
  // ends it. Returns whether it handled the key.
  function continueList(field) {
    const text = field.text;
    const pos = field.cursorPosition;
    const start = text.lastIndexOf("\n", pos - 1) + 1;
    const newline = text.indexOf("\n", pos);
    const end = newline < 0 ? text.length : newline;
    const next = NoteMarkdown.continuePrefix(text.slice(start, end));
    if (!next)
      return false;
    if (next.clear) {
      field.remove(start, end);
      return true;
    }
    // Only past the marker: Enter before it just breaks the line
    if (pos - start < next.prefix.length - 1)
      return false;
    field.insert(pos, "\n" + next.prefix);
    return true;
  }

  // --- The toolbar ---

  function _focused() {
    return root.focusBlock >= 0 && root.focusBlock < root.blockCount ? root.focusBlock : -1;
  }

  function toggleTask() {
    root.apply(NoteMarkdown.toggleTask(root.doc, root._focused(), root.focusPos));
  }

  function toggleBullet() {
    root.apply(NoteMarkdown.toggleBullet(root.doc, root._focused(), root.focusPos));
  }

  StyledScrollView {
    id: scroll
    anchors.fill: parent
    contentPadding: 0
    showScrollBar: blocks.implicitHeight > scroll.height
    rightPadding: showScrollBar ? Widget.px(12) : 0

    Item {
      width: scroll.availableWidth
      implicitHeight: Math.max(blocks.implicitHeight, scroll.height)

      // A click below the text puts the cursor at its end
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.IBeamCursor
        onClicked: root.focusEnd()
      }

      Column {
        id: blocks
        width: parent.width
        spacing: 2

        Repeater {
          id: repeater
          model: root.blockCount
          delegate: NoteBlock {
            editor: root
          }
        }
      }

      StyledText {
        visible: root.blockCount === 1 && root._noteText === ""
        width: parent.width
        wrapMode: Text.WordWrap
        text: root.placeholderText
        textColor: Theme.foregroundAlt
        opacity: 0.7
      }
    }
  }
}

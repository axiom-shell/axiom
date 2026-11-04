pragma ComponentBehavior: Bound
import QtQuick

import qs.components.methods

/* An editor's undo and redo. Not a singleton: each editor that can undo
 * owns one (GridEditor, BarManager) and points `snapshot` / `restore` at
 * what its edits change. A snapshot is taken before each edit, newest
 * last, up to `limit`; undo puts the newest back and keeps the present
 * for redo. Edits to one field in a row (typing, a stepper) join one step:
 * record(fieldKey) with the same key as the step before adds nothing. */
QtObject {
  id: root

  // Returns what an edit changes, as a plain value (it's cloned)
  property var snapshot: () => null
  // Puts a snapshot back (handed a copy the history no longer keeps)
  property var restore: snap => {}
  property int limit: 50

  // The lists are only ever replaced, never changed in place, so these
  // follow them
  readonly property bool canUndo: root._undo.length > 0
  readonly property bool canRedo: root._redo.length > 0

  property var _undo: []
  property var _redo: []
  // The field the newest step was recorded for ("" for a whole edit)
  property string _lastKey: ""

  // The present, to hand to push() once an edit turns out to change
  // something
  function take() {
    return Utils.clone(root.snapshot());
  }

  // Records `snap` (from take(), before the edit) as one step
  function push(snap) {
    root._undo = root._undo.concat([snap]).slice(-root.limit);
    root._redo = [];
    root._lastKey = "";
  }

  // Records the present before an edit to `fieldKey`; more edits to the
  // same key join this step. An empty key is a step of its own
  function record(fieldKey) {
    const key = fieldKey ?? "";
    if (key !== "" && key === root._lastKey)
      return;
    root.push(root.take());
    root._lastKey = key;
  }

  function undo() {
    if (root._undo.length === 0)
      return;
    const snap = root._undo[root._undo.length - 1];
    root._redo = root._redo.concat([root.take()]);
    root._undo = root._undo.slice(0, -1);
    root._lastKey = "";
    root.restore(snap);
  }

  function redo() {
    if (root._redo.length === 0)
      return;
    const snap = root._redo[root._redo.length - 1];
    root._undo = root._undo.concat([root.take()]);
    root._redo = root._redo.slice(0, -1);
    root._lastKey = "";
    root.restore(snap);
  }

  function clear() {
    root._undo = [];
    root._redo = [];
    root._lastKey = "";
  }
}

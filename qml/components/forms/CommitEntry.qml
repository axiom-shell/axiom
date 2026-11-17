pragma ComponentBehavior: Bound
import QtQuick
import qs.services.ui
import qs.components.reusable

// A text entry editing a value that lives elsewhere (config, a draft): the
// one place the pushed-value rule is written (docs/dev/core/qml-pitfalls.md ›
// Bindings). `value` is pushed in while the entry is unfocused and holds
// nothing typed, so a value arriving mid-edit never eats keystrokes, and
// only an edit made in the entry emits. `live` emits `edited(text)` on each
// edit; otherwise the typed text is held and `committed(text)` fires on
// Enter, on losing focus, when the page's Save runs (EditsManager.holdTyping
// asks the field to commitTyped()) and, unless `commitOnDestroy` is false,
// when the entry goes away with text still held. `scope` names what the entry
// edits (a selection's id, a row's key): a commit of text typed under another
// scope is dropped, so a selection changing mid-edit never writes the typed
// text onto the new one.
StyledTextEntry {
  id: root

  // The value being edited, pushed in
  property string value: ""
  // true: `edited` on each edit; false: `committed` once, when it's done
  property bool live: false
  // false: an entry torn down with text held only lets go of it (an editor
  // that rebuilds on selection, not on save)
  property bool commitOnDestroy: true
  // What the entry edits: text typed under one scope is never committed under
  // another
  property var scope: null

  // Each edit, live only
  signal edited(string text)
  // What was typed, once it's done (not live)
  signal committed(string text)

  // Typed since the last commit or value pushed in (not live)
  property bool _pending: false
  // The scope the pending text was typed under
  property var _typedScope: null

  // Writes what was typed, if anything was (nothing, when `scope` changed
  // since)
  function commitTyped() {
    if (!root._pending)
      return;
    root._pending = false;
    EditsManager.releaseTyping(root);
    if (root._typedScope === root.scope)
      root.committed(root.text);
  }

  // Drops what was typed: back to the value
  function discardTyped() {
    root._pending = false;
    EditsManager.releaseTyping(root);
    root.text = root.value;
  }

  // RestoreNone: a Binding torn down with the entry mustn't write back
  Binding {
    target: root
    property: "text"
    value: root.value
    when: !root.input.activeFocus && !root._pending
    restoreMode: Binding.RestoreNone
  }

  onTextEdited: {
    if (root.live) {
      root.edited(root.text);
      return;
    }
    if (!root._pending)
      root._typedScope = root.scope;
    root._pending = true;
    EditsManager.holdTyping(root, root.Window.window);
  }
  onAccepted: root.commitTyped()
  input.onActiveFocusChanged: {
    if (!root.input.activeFocus)
      root.commitTyped();
  }

  Component.onDestruction: {
    if (root.commitOnDestroy)
      root.commitTyped();
    EditsManager.releaseTyping(root);
  }
}

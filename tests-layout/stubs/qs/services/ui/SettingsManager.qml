pragma Singleton
import QtQuick

// Stand-in for the shell's SettingsManager in the layout harness: what a
// settings card (SettingsGroupCard, SettingsField) reads. Fold state is kept
// (setFoldOpen stores it, so a fold row flips through it like the real one);
// nothing is ever changed or collapsed, and the schema and config are empty.
QtObject {
  property var collapsed: ({})
  // Dotted path -> schema / value / { title, category } a link leads to
  // (empty: nothing found), for tests of the rows that read them
  property var schemas: ({})
  property var values: ({})
  property var located: ({})

  function isFoldOpen(path) {
    return collapsed[path + ":open"] === true;
  }

  function setFoldOpen(path, open) {
    setCollapsed(path + ":open", open);
  }

  function isCollapsed(key) {
    return collapsed[key] === true;
  }

  // `keys`: one key or a list; true sets, false deletes
  function setCollapsed(keys, value) {
    const next = Object.assign({}, collapsed);
    for (const key of [].concat(keys)) {
      if (value)
        next[key] = true;
      else
        delete next[key];
    }
    collapsed = next;
  }

  function isChanged(path) {
    return false;
  }

  function hasChangesUnder(path) {
    return false;
  }

  function schemaAt(path) {
    return schemas[path.join(".")];
  }

  function configValueAt(key) {
    return values[key];
  }

  function commitValues(values) {
  }

  function locate(key) {
    return located[key] ?? null;
  }

  // The paths discard() was given, for tests
  property var discarded: []

  function discard(paths) {
    discarded = discarded.concat(paths);
  }

  function optionsFor(schema) {
    return [];
  }

  function suggestionsFor(schema) {
    return [];
  }
}

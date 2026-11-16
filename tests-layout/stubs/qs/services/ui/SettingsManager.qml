pragma Singleton
import QtQuick

// Stand-in for the shell's SettingsManager in the layout harness: what a
// settings card (SettingsGroupCard, SettingsField) reads. Fold state is kept
// (setFoldOpen stores it, so a fold row flips through it like the real one);
// nothing is ever changed or collapsed, and the schema and config are empty.
QtObject {
  property var folds: ({})
  property var collapsed: ({})
  // Dotted path -> schema / value / { title, category } a link leads to
  // (empty: nothing found), for tests of the rows that read them
  property var schemas: ({})
  property var values: ({})
  property var located: ({})

  function isFoldOpen(key) {
    return folds[key] === true;
  }

  function setFoldOpen(key, open) {
    const next = Object.assign({}, folds);
    next[key] = open;
    folds = next;
  }

  function isCollapsed(key) {
    return collapsed[key] === true;
  }

  function setCollapsed(key, value) {
    const next = Object.assign({}, collapsed);
    next[key] = value;
    collapsed = next;
  }

  function isChanged(path) {
    return false;
  }

  function hasChangesUnder(path) {
    return false;
  }

  function schemaAt(path) {
    return schemas[path.join(".")] ?? ({});
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

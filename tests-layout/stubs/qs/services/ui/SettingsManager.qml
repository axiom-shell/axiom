pragma Singleton
import QtQuick

// Stand-in for the shell's SettingsManager in the layout harness: what a
// settings card (SettingsGroupCard, SettingsField) reads. Fold state is kept
// (setFoldOpen stores it, so a fold row flips through it like the real one);
// nothing is ever changed or collapsed, and the schema and config are empty.
QtObject {
  property var folds: ({})
  property var collapsed: ({})

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
    return ({});
  }

  function configValueAt(key) {
    return undefined;
  }

  function discard(paths) {
  }

  function optionsFor(schema) {
    return [];
  }

  function suggestionsFor(schema) {
    return [];
  }
}

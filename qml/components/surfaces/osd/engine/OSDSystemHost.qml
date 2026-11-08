pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods

// One OSD system of an OSD (an item of its `systems` list): its
// definition and its watcher, each loaded by URL from the system's folder
// (Paths.osdSystemUrl / osdWatchUrl), the watcher handed the definition.
// Neither names the other as a type, so the folder is never imported by
// name; this file's own folder (the bases) and what the watchers import
// are imported by the host that builds it (docs/dev/features/osd.md ›
// Engine). Draws nothing.
Item {
  id: root

  // The system's name (its folder's)
  required property string type
  // Its item in the OSD's `systems` list ({ type, tile, card, quiet, …its
  // own settings })
  property var options: ({})
  // The screen its OSD is on and the OSD's id, for the watcher
  property var screen: null
  property string osdId: ""

  // Its definition (an OSDSystem) and watcher (an OSDWatch), once loaded
  readonly property var definition: definitionLoader.item
  readonly property var watch: watchLoader.item
  // Its state and tiles now, by key (the watcher's `state`: an Item's
  // own `state` is taken)
  readonly property var snapshot: root.watch?.state ?? ({})
  readonly property var tiles: root.watch?.tiles ?? ({})

  // What shows for a change (OSDEngine.judge's, with { system })
  signal change(var what)

  // Whether a change opens the OSD shut (OSDEngine.opens: its item's
  // `quiet`, its key's `opens`, on-screen unless OSD.onScreenChanges or
  // the change's `alert`)
  function opens(what) {
    return OSDEngine.opens(root.options, root.definition, what, OSDConfig.onScreenChanges);
  }

  // The card for a change (OSDEngine.cardOf), or null. A host re-reads
  // the card out through this as the state changes (bound to `snapshot`),
  // so it says what holds now: the apps left, a name filling in
  function card(what) {
    return OSDEngine.cardOf(root.definition, what, root.snapshot);
  }

  // The action a click on `key`'s tile runs ({ id, call } for
  // ActionsManager.run), or null
  function actionOf(key) {
    return root.definition ? root.definition.actionOf(key, root.snapshot[key]) : null;
  }

  // A click on its card: its watcher acts on it (a drive's opens it)
  function activate(what) {
    if (root.watch)
      root.watch.activate(what);
  }

  // Loaded once, as it's built: a type change rebuilds the host; an edit
  // to the item's own settings reaches both in place
  function _load() {
    definitionLoader.setSource(root.type ? Paths.osdSystemUrl(root.type) : "", {
      "type": root.type,
      "options": root.options
    });
  }
  onOptionsChanged: {
    if (root.definition)
      root.definition.options = root.options;
    if (root.watch)
      root.watch.options = root.options;
  }
  Component.onCompleted: root._load()

  Loader {
    id: definitionLoader
    onLoaded: watchLoader.setSource(Paths.osdWatchUrl(root.type), {
      "definition": definitionLoader.item,
      "options": root.options,
      "screen": root.screen,
      "osdId": root.osdId
    })
    onSourceChanged: {
      if (String(definitionLoader.source) === "")
        watchLoader.source = "";
    }
  }

  Loader {
    id: watchLoader
  }

  Connections {
    target: root.watch
    ignoreUnknownSignals: true
    function onChange(what) {
      root.change(what);
    }
  }
}

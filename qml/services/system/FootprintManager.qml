pragma Singleton
import QtQuick
import Quickshell

import qs.config
import qs.services.core
import qs.services.compositor
import qs.services.apps
import qs.services.ui
import qs.components.methods

/*
 * What axiom changed outside its own folders (the daemon's footprint
 * ledger, docs/dev/backend/footprint.md): the rows with their status
 * (present, changed since, gone), undoing some of them or an owner's, and
 * the one-time backfill of what an earlier axiom left. Settings › General's
 * "Changes outside axiom" card and the fields' "Remove its changes" read
 * it. Nothing polls: the daemon pushes `footprint.changed`.
 */
Singleton {
  id: root

  // The ledger's rows: [{ id, kind, owner, target, key, state, inferred,
  // system, status, hookup, ... }]
  property var rows: []
  readonly property int count: rows.length
  // id -> { outcome, detail } of the last undo, for the card
  property var results: ({})

  // The rows an owner (a setting path) caused
  function rowsFor(owner) {
    return root.rows.filter(row => row.owner === owner);
  }

  // Those "Remove its changes" undoes: not the system's own choices
  // (default apps, input method groups), not what axiom only inferred
  function undoableFor(owner) {
    return root.rows.filter(row => row.owner === owner && !row.system && !row.inferred);
  }

  // The owner's rows that are the system's own choices
  function systemFor(owner) {
    return root.rows.filter(row => row.owner === owner && row.system);
  }

  // A row's name
  function labelOf(row) {
    return Footprint.label(row, Quickshell.env("HOME"));
  }

  // rpc: footprint.list
  function refresh() {
    if (Paths.greeter)
      return;
    BackendManager.call("footprint.list", {}, (error, result) => {
      if (error) {
        console.warn("[FootprintManager] footprint.list:", error.message);
        return;
      }
      root.rows = result.rows;
    });
  }

  // Undoes the rows `ids` name (`force`: inferred ones too); each row's
  // outcome lands in `results`
  // rpc: footprint.undo
  function undo(ids, force = false, done = null) {
    BackendManager.call("footprint.undo", {
      "ids": ids,
      "force": force,
      "includeSystem": true,
      "dryRun": false
    }, (error, result) => {
      if (error) {
        console.warn("[FootprintManager] footprint.undo:", error.message);
        if (done)
          done(false);
        return;
      }
      const next = Object.assign({}, root.results);
      for (const r of result.results)
        next[r.id] = r;
      root.results = next;
      root.refresh();
      if (done)
        done(true);
    });
  }

  // Undo all: every row but the system's own choices and the inferred ones
  function undoAll(done = null) {
    root.undo(root.rows.filter(row => !row.system && !row.inferred).map(row => row.id), false, done);
  }

  // Turns a setting off (its off value saved at once, Footprint.offValue),
  // then undoes what it caused, but the system's own choices (the field
  // asks about those: systemFor, then undo) and inferred rows. Owner ""
  // (the compositor's include and autostart lines) commits nothing.
  function undoOwner(path) {
    if (path !== "") {
      const schema = SettingsManager.schemaAt(path.split("."));
      if (!SettingsManager.commitValue(path, Footprint.offValue(schema))) {
        console.warn("[FootprintManager] couldn't turn", path, "off");
        return;
      }
    }
    root.undo(root.undoableFor(path).map(row => row.id), false);
  }

  // The hookup backfill needs every target the shell alone knows: the
  // compositor's include and autostart lines and the screen-sharing line
  // (known too: no compositor kind at all, or one with no include target
  // to find, once the compositor has settled)
  readonly property bool _targetsKnown: CompositorManager.ready && ScreenShareManager.pickerBinary !== "" && (CompositorManager.kind === "" || !CompositorManager.supports.configModes || CompositorConfigManager.includeTarget !== null)
  property bool _backfilled: false
  on_TargetsKnownChanged: root._maybeBackfill()

  function _maybeBackfill() {
    if (root._backfilled || !root._targetsKnown || !BackendManager.ready || Paths.greeter)
      return;
    root._backfilled = true;
    root._backfill();
  }

  // The hookup targets the ledger looks for evidence of, per key and its
  // owner (the compositor's include covers its autostart line); the daemon
  // does it once per ledger
  // rpc: footprint.backfill
  function _backfill() {
    const targets = {};
    const keys = Object.keys(ConfigManager.configSchema.properties.ThemeIntegrations.properties);
    for (const key of keys.concat(["compositorInclude", "screenSharing"])) {
      const list = IntegrationHookupManager.targets(key);
      if (list.length > 0)
        targets[key] = {
          "owner": IntegrationHookupManager.ownerOf(key),
          "targets": list,
          "profiles": ConfigManager.configSchema.properties.ThemeIntegrations.properties[key]?.["x-profiles"] ?? []
        };
    }
    BackendManager.call("footprint.backfill", {
      "targets": targets
    }, (error, result) => {
      if (error) {
        console.warn("[FootprintManager] footprint.backfill:", error.message);
        return;
      }
      if (result.ran)
        root.refresh();
    });
  }

  Component.onCompleted: {
    BackendManager.listen("footprint.changed", () => root.refresh());
    if (BackendManager.ready)
      root._onReady();
  }

  function _onReady() {
    root.refresh();
    root._maybeBackfill();
  }

  Connections {
    target: BackendManager
    function onGreeted() {
      root._onReady();
    }
  }
}

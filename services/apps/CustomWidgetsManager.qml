pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods
import qs.services.core
import qs.services.session

// Runs the custom JSON widgets (docs/dev/features/custom-widgets.md): each
// definition's script is watched through CommandManager while a bar widget,
// popout or module shows it (acquire/release by id, so the script runs once
// for all of them), and its output is read into fields
// (CustomWidgetData.resolve) for every consumer. Also keeps a short numeric
// history for sparklines, and runs the widgets' actions.
//   CustomWidgetsManager.acquire(owner, id) / release(owner)
//   CustomWidgetsManager.fields[id]   // resolved fields, or absent
//   CustomWidgetsManager.history[id]  // { <binding>: [numbers] }
QtObject {
  id: root

  // id -> the definition's fields from its last output
  readonly property var fields: _fields
  // id -> { text, value, exitCode, error, at, blocked } of its last output
  // (blocked: its "run only if" command failed)
  readonly property var outputs: _outputs
  // id -> { binding ("" for the widget's own value) -> [numbers] }, the
  // last historyLength samples
  readonly property var history: _history
  readonly property int historyLength: 60

  // The Custom widgets page's draft and selection
  readonly property CustomWidgetsEditor editor: CustomWidgetsEditor {}

  function acquire(owner, id) {
    if (!id) {
      release(owner);
      return;
    }
    _registry.acquire(owner, {
      "id": id
    });
  }

  function release(owner) {
    _registry.release(owner);
  }

  // Run the widget's script again now
  function refresh(id) {
    const def = CustomWidgetsConfig.definition(id);
    if (!def)
      return;
    if (root._blocked[id]) {
      root._checkIf(id, def);
      return;
    }
    CommandManager.refresh(def.command);
  }

  // Run one of a definition's actions ("click", "rightClick", "middleClick",
  // "scrollUp", "scrollDown"), then refresh it when it asks to
  function act(id, action) {
    const def = CustomWidgetsConfig.definition(id);
    root.runCommand(id, def?.actions?.[action] ?? "", undefined);
  }

  // Run `command` for widget `id`, `{value}` filled in (shell-quoted unless
  // a number). Nothing runs in the greeter or while the screen is locked.
  function runCommand(id, command, value) {
    if (!command || Paths.greeter || LockManager.builtinLocked)
      return;
    const text = value === undefined ? "" : String(value);
    const quoted = /^-?[0-9.]+$/.test(text) ? text : "'" + text.replace(/'/g, "'\\''") + "'";
    CommandManager.runDetached(command.replace(/\{value\}/g, quoted));
    if (CustomWidgetsConfig.definition(id)?.actions?.refreshAfter ?? true)
      root._refreshSoon(id);
  }

  // The lookup `axiom ipc customWidgets refresh` uses: a widget by its
  // refresh name, id or name
  function find(name) {
    return CustomWidgetsConfig.items.find(d => d.refreshName === name) ?? CustomWidgetsConfig.items.find(d => d.id === name || d.name === name) ?? null;
  }

  // -- Private --
  property ConsumerRegistry _registry: ConsumerRegistry {}
  // The ids shown, and what each watches: changes only with the config
  readonly property var _wanted: {
    const ids = {};
    for (const r of root._registry.requests) {
      const def = CustomWidgetsConfig.definition(r.id);
      if (def?.command)
        ids[r.id] = {
          "command": def.command,
          "interval": def.interval,
          "mode": def.mode,
          "format": def.output === "text" ? "text" : "json",
          "execIf": def.execIf
        };
    }
    return ids;
  }
  readonly property string _wantedJson: JSON.stringify(_wanted)
  on_WantedJsonChanged: _sync()

  property var _watching: ({})
  property var _blocked: ({})
  property var _fields: ({})
  property var _outputs: ({})
  property var _history: ({})
  property var _seen: ({})

  function _owner(id) {
    return "customWidget:" + id;
  }

  function _sync() {
    const wanted = root._wanted;
    const last = root._watching;
    for (const id in last) {
      if (!(id in wanted) || JSON.stringify(wanted[id]) !== JSON.stringify(last[id]))
        CommandManager.release(root._owner(id));
    }
    root._watching = wanted;
    for (const id in wanted) {
      if (JSON.stringify(wanted[id]) === JSON.stringify(last[id]))
        continue;
      root._seen[id] = -1;
      if (wanted[id].execIf)
        root._checkIf(id, CustomWidgetsConfig.definition(id));
      else
        root._watch(id);
    }
    // Forget what's no longer shown, so a widget shown again starts fresh
    const keep = map => Object.keys(map).filter(id => id in wanted).reduce((m, id) => {
        m[id] = map[id];
        return m;
      }, {});
    root._fields = keep(root._fields);
    root._outputs = keep(root._outputs);
    root._history = keep(root._history);
    root._read();
  }

  function _watch(id) {
    const w = root._watching[id];
    if (!w)
      return;
    root._blocked[id] = false;
    CommandManager.acquire(root._owner(id), {
      "command": w.command,
      "interval": w.interval,
      "mode": w.mode,
      "format": w.format
    });
  }

  // Waybar's exec-if: the script runs only once this succeeds
  function _checkIf(id, def) {
    CommandManager.run(["sh", "-c", def.execIf], exitCode => {
      if (!(id in root._watching))
        return;
      if (exitCode === 0) {
        root._watch(id);
        return;
      }
      root._blocked[id] = true;
      CommandManager.release(root._owner(id));
      const outputs = Object.assign({}, root._outputs);
      outputs[id] = {
        "text": "",
        "value": undefined,
        "exitCode": exitCode,
        "error": `"${def.execIf}" failed`,
        "at": Date.now(),
        "blocked": true
      };
      root._outputs = outputs;
    });
  }

  // Each push: read the outputs that changed into fields and history
  function _read() {
    let fields = null;
    let outputs = null;
    let history = null;
    for (const id in root._watching) {
      const w = root._watching[id];
      const run = CommandManager.runs[w.command];
      if (!run || run.at === root._seen[id] || root._blocked[id])
        continue;
      root._seen[id] = run.at;
      const def = CustomWidgetsConfig.definition(id);
      const text = CommandManager.outputs[w.command] ?? "";
      const value = CommandManager.values[w.command];
      const sample = CustomWidgetData.parse(text, value, def.output, def.mode === "stream");
      const resolved = CustomWidgetData.resolve(def, sample);
      fields = fields ?? Object.assign({}, root._fields);
      outputs = outputs ?? Object.assign({}, root._outputs);
      history = history ?? Object.assign({}, root._history);
      fields[id] = resolved;
      outputs[id] = {
        "text": text,
        "value": value,
        "exitCode": run.exitCode,
        "error": run.error,
        "at": run.at,
        "blocked": false
      };
      history[id] = root._pushHistory(history[id], def, resolved);
    }
    if (fields) {
      root._fields = fields;
      root._outputs = outputs;
      root._history = history;
    }
  }

  // The numbers a definition graphs: its own value, and each Sparkline
  // element's binding
  function _pushHistory(last, def, resolved) {
    const next = {};
    const bindings = [""].concat((def.module?.elements ?? []).filter(e => e.type === "Sparkline" && e.bind?.value).map(e => e.bind.value));
    for (const b of bindings) {
      const v = b === "" ? resolved.value : parseFloat(CustomWidgetData.elementValue(resolved, b));
      const list = (last?.[b] ?? []).slice(-(root.historyLength - 1));
      if (typeof v === "number" && isFinite(v))
        list.push(v);
      next[b] = list;
    }
    return next;
  }

  property var _pendingRefresh: []
  function _refreshSoon(id) {
    if (root._pendingRefresh.indexOf(id) < 0)
      root._pendingRefresh = root._pendingRefresh.concat([id]);
    _refreshTimer.restart();
  }
  // An action's effect takes a moment to show in the script's output
  property Timer _refreshTimer: Timer {
    interval: 300
    onTriggered: {
      const ids = root._pendingRefresh;
      root._pendingRefresh = [];
      ids.forEach(id => root.refresh(id));
    }
  }

  property Connections _pushes: Connections {
    target: CommandManager
    function onRunsChanged() {
      root._read();
    }
  }

  property IpcTarget _ipc: IpcTarget {
    target: "customWidgets"

    // Run a custom widget's script again now: its refresh name, id or name
    // (what Waybar's signal did)
    function refresh(name: string): string {
      const def = root.find(name);
      if (!def)
        return `no custom widget "${name}"`;
      root.refresh(def.id);
      return "";
    }

    // The custom widgets: id, refresh name and name, one a line
    function list(): string {
      return CustomWidgetsConfig.items.map(d => `${d.id}\t${d.refreshName}\t${d.name}`).join("\n");
    }
  }
}

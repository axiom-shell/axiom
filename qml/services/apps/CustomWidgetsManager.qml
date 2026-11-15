pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods
import qs.services.core
import qs.services.session
import qs.services.ui

// Runs the custom JSON widgets (docs/dev/features/custom-widgets.md): each
// definition's script is watched through CommandManager while a bar widget,
// popout or module shows it (acquire/release by id, so the script runs once
// for all of them), and its output is read into fields
// (CustomWidgetData.resolve) for every consumer. Also keeps a short numeric
// history for sparklines, and runs the widgets' actions: the commands of
// Waybar's clicks, and named actions (invoke) that run the definition's
// action command, or a built-in (axiom:refresh, axiom:restart, an
// ActionsManager id).
//   CustomWidgetsManager.acquire(owner, id) / release(owner)
//   CustomWidgetsManager.fields[id]   // resolved fields, or absent
//   CustomWidgetsManager.history[id]  // { <binding>: [numbers] }
QtObject {
  id: root

  // id -> the definition's fields from its last output
  readonly property var fields: _fields
  // id -> { text, value, exitCode, error, stderr (its last line), exited (a
  // stream that ended with a non-zero exit), at, blocked } of its last
  // output (blocked: its "run only if" command failed)
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
    CommandManager.refresh(root._command(def));
  }

  // Stop the widget's script and start it again now (a poll just runs
  // again): refresh only republishes a running stream's last line
  function restart(id) {
    const def = CustomWidgetsConfig.definition(id);
    if (!def)
      return;
    if (root._blocked[id]) {
      root._checkIf(id, def);
      return;
    }
    CommandManager.restart(root._command(def));
  }

  // Run one of a definition's actions ("click", "rightClick", "middleClick",
  // "scrollUp", "scrollDown"): its named action when it has one
  // (actions.named, a scroll is continuous), else its command, then
  // refresh it when it asks to
  function act(id, action) {
    const def = CustomWidgetsConfig.definition(id);
    const named = def?.actions?.named?.[action] ?? "";
    if (named !== "")
      root.invoke(id, named, undefined, action.startsWith("scroll"));
    else
      root.runCommand(id, def?.actions?.[action] ?? "", undefined);
  }

  // Run `command` for widget `id`, `{value}` filled in (shell-quoted unless
  // a number). Nothing runs in the greeter or while the screen is locked.
  function runCommand(id, command, value) {
    if (!command || Paths.greeter || LockManager.builtinLocked)
      return;
    CommandManager.runDetached(CustomWidgetData.fillCommand(command, {
      "value": CustomWidgetData.asText(value)
    }));
    if (CustomWidgetsConfig.definition(id)?.actions?.refreshAfter ?? true)
      root._refreshSoon(id);
  }

  // Run the named action `action` of widget `id` with `value` ({value} in
  // its command). Built-ins ("axiom:refresh", "axiom:restart",
  // "axiom:<ActionsManager id>": never a session or destructive one) need
  // no command; any other id runs the definition's action command
  // (invoke.command, {action} {value} {rev} filled in, quoted) and, at
  // exit 0, refreshes the script when the definition asks. `fromIpc`: the
  // request came from `axiom ipc` (nothing shows the widget to click:
  // refused while nothing shows it). Returns "" when it ran, else why not:
  // "no widget", "not shown", "locked", "refused", "no action command",
  // "failing" (the script isn't answering) or "disabled" (the sample turns
  // it off)
  function invoke(id, action, value, continuous, fromIpc) {
    const def = CustomWidgetsConfig.definition(id);
    if (!def)
      return "no widget";
    if (fromIpc && !root._shown(id))
      return "not shown";
    if (Paths.greeter || LockManager.builtinLocked)
      return "locked";
    if (action.startsWith("axiom:")) {
      const rest = action.slice(6);
      const refused = ActionsManager.sessionActions.concat(ActionsManager.destructive(rest) ? [rest] : []);
      if (!CustomWidgetData.builtinAllowed(action, refused))
        return "refused";
      if (rest === "refresh")
        root.refresh(id);
      else if (rest === "restart")
        root.restart(id);
      else
        ActionsManager.run(rest);
      return "";
    }
    if (def.invoke.command === "")
      return "no action command";
    const fields = root._fields[id];
    if (fields && fields.failure && fields.failure.kind !== "script")
      return "failing";
    if (!CustomWidgetData.actionEnabled(fields?.actions, action))
      return "disabled";
    const command = CustomWidgetData.fillCommand(def.invoke.command, {
      "action": action,
      "value": CustomWidgetData.asText(value),
      "rev": fields?.rev ?? ""
    });
    CommandManager.run(["sh", "-c", command], code => root._done(id, code));
    return "";
  }

  // What an action's name reads as on a button with no label of its own
  function actionLabel(id) {
    if (id === "axiom:refresh")
      return I18n.tr("Refresh");
    if (id === "axiom:restart")
      return I18n.tr("Restart");
    return id.startsWith("axiom:") ? ActionsManager.label(id.slice(6)) : "";
  }

  // The lookup `axiom ipc customWidgets refresh` uses: a widget by its
  // refresh name, id or name
  function find(name) {
    return CustomWidgetsConfig.items.find(d => d.refreshName === name) ?? CustomWidgetsConfig.items.find(d => d.id === name || d.name === name) ?? null;
  }

  // -- Private --
  property ConsumerRegistry _registry: ConsumerRegistry {}
  // Whether something shows the widget (the editor's running one counts)
  function _shown(id) {
    return root._registry.requests.some(r => r.id === id);
  }

  // An action command finished: at exit 0 the script runs again, when the
  // definition asks
  function _done(id, exitCode) {
    if (exitCode === 0 && CustomWidgetsConfig.definition(id)?.actions.refreshAfter)
      root.refresh(id);
  }

  // The ids shown, and what each watches: changes only with the config
  readonly property var _wanted: {
    const ids = {};
    for (const r of root._registry.requests) {
      const def = CustomWidgetsConfig.definition(r.id);
      if (def?.command)
        ids[r.id] = {
          "command": root._command(def),
          "interval": def.interval,
          "mode": def.mode,
          "format": def.output === "text" ? "text" : "json",
          "execIf": def.execIf
        };
    }
    return ids;
  }
  readonly property string _wantedJson: JSON.stringify(_wanted)
  // Next tick: an acquire made while a consumer's binding on `fields`
  // evaluates (its id settling) must not write `fields` inside it
  on_WantedJsonChanged: Qt.callLater(root._sync)

  property var _watching: ({})
  property var _blocked: ({})
  property var _fields: ({})
  property var _outputs: ({})
  property var _history: ({})
  property var _seen: ({})

  // The command a definition's script runs as
  function _command(def) {
    return def.command;
  }

  function _owner(id) {
    return "customWidget:" + id;
  }

  function _sync() {
    const wanted = root._wanted;
    const last = root._watching;
    for (const id in last) {
      if (!(id in wanted) || !Utils.deepEqual(wanted[id], last[id]))
        CommandManager.release(root._owner(id));
    }
    root._watching = wanted;
    for (const id in wanted) {
      if (Utils.deepEqual(wanted[id], last[id]))
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
    }, null, true);
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
      fields = fields ?? Object.assign({}, root._fields);
      outputs = outputs ?? Object.assign({}, root._outputs);
      history = history ?? Object.assign({}, root._history);
      outputs[id] = {
        "text": text,
        "value": value,
        "exitCode": run.exitCode,
        "error": run.error,
        "stderr": run.stderr,
        "exited": run.exited,
        "at": run.at,
        "blocked": false
      };
      const resolved = CustomWidgetData.resolve(def, sample, root._context(id, outputs[id]));
      fields[id] = resolved;
      history[id] = root._pushHistory(history[id], def, resolved);
    }
    if (fields) {
      root._fields = fields;
      root._outputs = outputs;
      root._history = history;
    }
  }

  // What resolve needs besides the definition and the sample (its
  // `context`): the theme's colour names, the script's last run (`output`,
  // an entry of `outputs`), whether the definition is interactive (it has
  // an action command, or screens) and the failure messages. `{0}` is the exit code,
  // `{1}` the script's last stderr line.
  function _context(id, output) {
    const def = CustomWidgetsConfig.definition(id);
    return {
      "colorNames": Object.keys(Theme.stringToColorMap),
      "run": {
        "exitCode": output.exitCode,
        "error": output.error,
        "stderr": output.stderr ?? "",
        "text": output.text,
        "exited": output.exited ?? false
      },
      "interactive": def.invoke.command !== "" || def.module.views.length > 0,
      "stream": def.mode === "stream",
      "words": {
        "exited": I18n.tr("The script exited with code {0}"),
        "exitedWith": I18n.tr("The script exited with code {0}: {1}")
      }
    };
  }

  // The numbers a definition graphs: its own value, and each Sparkline
  // element's binding
  function _pushHistory(last, def, resolved) {
    const next = {};
    const bindings = [""].concat(CustomWidgetData.historyBindings(def.module));
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

  // A definition edited (its format, icons, states: a preview on the page)
  // redraws its last output at once, not at the next one (a stream may
  // send none for a while). The history keeps only real samples.
  function _reresolve() {
    let fields = null;
    for (const id in root._fields) {
      const def = CustomWidgetsConfig.definition(id);
      const out = root._outputs[id];
      if (!def || !out || out.blocked)
        continue;
      const resolved = CustomWidgetData.resolve(def, CustomWidgetData.parse(out.text, out.value, def.output, def.mode === "stream"), root._context(id, out));
      if (Utils.deepEqual(resolved, root._fields[id]))
        continue;
      fields = fields ?? Object.assign({}, root._fields);
      fields[id] = resolved;
    }
    if (fields)
      root._fields = fields;
  }
  property Connections _definitions: Connections {
    target: CustomWidgetsConfig
    function onItemsChanged() {
      root._reresolve();
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

    // Stop a custom widget's script and start it again now: its refresh
    // name, id or name (a stream's process is replaced, a poll runs again)
    function restart(name: string): string {
      const def = root.find(name);
      if (!def)
        return `no custom widget "${name}"`;
      root.restart(def.id);
      return "";
    }

    // The custom widgets: id, refresh name and name, one a line
    function list(): string {
      return CustomWidgetsConfig.items.map(d => `${d.id}\t${d.refreshName}\t${d.name}`).join("\n");
    }
  }
}

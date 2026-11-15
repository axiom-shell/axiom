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
//   CustomWidgetsManager.busy[id]     // a hold: { action, run, phase, until, sampled }
//   CustomWidgetsManager.lastAction[id] // { action, failed, exitCode, message, at, run }
//   CustomWidgetsManager.actionRan(id, entry) // each action command's end, each refusal
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
  // id -> the hold a discrete action put on the widget's script actions
  // (a double press acts once): { action, run (its number), phase
  // ("running": its command runs, at most holdCap; "grace": until the next
  // sample or a second after the exit), until (ms), sampled (a sample came
  // while it ran) }
  readonly property var busy: _busy
  // id -> the widget's last action to end: { action, failed, exitCode,
  // message (a failure's last stderr line), at, run }; the elements flash
  // and explain a failure from it
  readonly property var lastAction: _lastAction
  readonly property int holdCap: 15000
  readonly property int holdGrace: 1000

  // An action command ended, or an action was refused: `entry` is { at (ms),
  // action, command (as it ran: placeholders filled, {tree} expanded; ""
  // when refused), exitCode, ms (how long it ran), stderr (its last line),
  // refused (why not: invoke's reasons; "" when it ran) }. The editor keeps
  // the last few of the selected definition's
  signal actionRan(string id, var entry)

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
      "value": CustomWidgetData.asText(value),
      "tree": Paths.treePath
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
  // request comes from the named-action IPC (`axiom ipc customWidgets act`):
  // refused while nothing shows the widget. Returns "" when it ran, else why not:
  // "no widget", "not shown", "locked", "refused", "no action command",
  // "failing" (the script isn't answering), "disabled" (the sample turns
  // it off) or "busy" (another discrete action holds the widget: a double
  // press acts once; invoke.hold off never holds). A continuous action
  // (a scroll, a slider) never holds, one runs at a time and the latest
  // value waits; built-ins never hold and are never refused for it
  function invoke(id, action, value, continuous, fromIpc) {
    const why = root._invoke(id, action, value, continuous, fromIpc);
    if (why !== "" && why !== "no widget")
      root.actionRan(id, {
        "at": Date.now(),
        "action": action,
        "command": "",
        "exitCode": -1,
        "ms": 0,
        "stderr": "",
        "refused": why
      });
    return why;
  }

  function _invoke(id, action, value, continuous, fromIpc) {
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
    if (continuous) {
      // One run of an action at a time; a value sent meanwhile replaces any
      // waiting one (the latest wins), run when the first ends
      if (root._own(root._inFlight[id], action)) {
        root._pending[id] = Object.assign({}, root._pending[id], {
          [action]: value
        });
        return "";
      }
      root._inFlight[id] = Object.assign({}, root._inFlight[id], {
        [action]: true
      });
      root._start(id, action, value, 0, true);
      return "";
    }
    // A discrete one is refused while another holds the widget
    const hold = def.invoke.hold;
    if (root._busy[id])
      return "busy";
    const run = ++root._runSeq;
    if (hold)
      root._hold(id, action, run);
    root._start(id, action, value, run, false);
    return "";
  }

  // Runs the action command (`run`: the discrete run's number, 0 for a
  // continuous one)
  function _start(id, action, value, run, continuous) {
    const def = CustomWidgetsConfig.definition(id);
    const command = CustomWidgetData.fillCommand(def.invoke.command, {
      "action": action,
      "value": CustomWidgetData.asText(value),
      "rev": root._fields[id]?.rev ?? "",
      "tree": Paths.treePath
    });
    const started = Date.now();
    CommandManager.run(["sh", "-c", command], (code, out, err) => root._done(id, action, run, continuous, code, err, command, started));
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

  property var _busy: ({})
  property var _lastAction: ({})
  // id -> { action -> true }: continuous runs in flight; id -> { action ->
  // value }: the latest value sent meanwhile
  property var _inFlight: ({})
  property var _pending: ({})
  property int _runSeq: 0

  // Whether `map` lists `key` itself: an action id is a script's or a
  // config's word, so `constructor` and `toString` aren't listed
  function _own(map, key) {
    return map !== undefined && map !== null && Object.prototype.hasOwnProperty.call(map, key);
  }

  // Puts a hold on widget `id` for discrete run `run` of `action`
  function _hold(id, action, run) {
    root._setBusy(id, {
      "action": action,
      "run": run,
      "phase": "running",
      "until": Date.now() + root.holdCap,
      "sampled": false
    });
  }

  // Sets or (undefined) clears widget `id`'s hold, by a new map
  function _setBusy(id, entry) {
    const next = Object.assign({}, root._busy);
    if (entry === undefined)
      delete next[id];
    else
      next[id] = entry;
    root._busy = next;
    root._scheduleHold();
  }

  // One timer, at the earliest end of any hold
  function _scheduleHold() {
    const ends = Object.values(root._busy).map(e => e.until);
    if (ends.length === 0) {
      _holdTimer.stop();
      return;
    }
    _holdTimer.interval = Math.max(1, Math.min(...ends) - Date.now());
    _holdTimer.restart();
  }
  property Timer _holdTimer: Timer {
    onTriggered: {
      const now = Date.now();
      const next = {};
      for (const id in root._busy) {
        if (root._busy[id].until > now)
          next[id] = root._busy[id];
      }
      root._busy = next;
      root._scheduleHold();
    }
  }

  // An action command finished with `exitCode` and `stderr`. The widget's
  // last action is recorded (a failure's message: its last stderr line, or
  // the code) and a failure logged (the script's, not a shell problem: not
  // a warning). Only the run that holds the widget ends its hold (a late
  // exit of an older run, past the cap, leaves a newer hold alone): at
  // exit 0 into a grace (until the next sample or a second), or at once
  // when a sample came meanwhile; a failure releases it. At exit 0 the
  // script runs again when the definition asks. A continuous run starts
  // the value sent meanwhile
  function _done(id, action, run, continuous, exitCode, stderr, command, startedAt) {
    const failed = exitCode !== 0;
    const line = String(stderr ?? "").split("\n").map(l => l.trim()).filter(l => l !== "").pop() ?? "";
    const message = failed ? (line !== "" ? line.slice(0, 300) : I18n.tr("The action failed with code {0}", exitCode)) : "";
    if (failed)
      console.log(`[CustomWidgetsManager] ${id}: action ${action} failed with code ${exitCode}${line !== "" ? ": " + line : ""}`);
    // a widget no longer shown forgets its runs (_sync)
    if (!(id in root._watching))
      return;
    root.actionRan(id, {
      "at": Date.now(),
      "action": action,
      "command": command,
      "exitCode": exitCode,
      "ms": Date.now() - startedAt,
      "stderr": line,
      "refused": ""
    });
    root._lastAction = Object.assign({}, root._lastAction, {
      [id]: {
        "action": action,
        "failed": failed,
        "exitCode": exitCode,
        "message": message,
        "at": Date.now(),
        "run": run
      }
    });
    const hold = root._busy[id];
    if (!continuous && hold?.run === run) {
      if (failed || hold.sampled)
        root._setBusy(id, undefined);
      else
        root._setBusy(id, Object.assign({}, hold, {
          "phase": "grace",
          "until": Date.now() + root.holdGrace
        }));
    }
    if (!failed && CustomWidgetsConfig.definition(id)?.actions.refreshAfter)
      root.refresh(id);
    if (continuous) {
      const waiting = root._own(root._pending[id], action) ? root._pending[id][action] : undefined;
      const inFlight = Object.assign({}, root._inFlight[id]);
      delete inFlight[action];
      root._inFlight[id] = inFlight;
      if (root._own(root._pending[id], action)) {
        const rest = Object.assign({}, root._pending[id]);
        delete rest[action];
        root._pending[id] = rest;
        root.invoke(id, action, waiting, true);
      }
    }
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

  // The command a definition's script runs as: `{tree}` filled in
  function _command(def) {
    return root._expand(def.command);
  }

  // `{tree}` (the axiom tree this shell runs, with a trailing slash: a dev
  // or nested tree finds its own data/ scripts) filled in the way element
  // commands are (a shell `${tree}` stays). It stays literal in config, so
  // a definition holds no path
  function _expand(text) {
    return CustomWidgetData.fillCommand(text, {
      "tree": Paths.treePath
    });
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
    root._busy = keep(root._busy);
    root._lastAction = keep(root._lastAction);
    root._inFlight = keep(root._inFlight);
    root._pending = keep(root._pending);
    root._scheduleHold();
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
    CommandManager.run(["sh", "-c", root._expand(def.execIf)], exitCode => {
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
      root._sampled(id);
      history[id] = root._pushHistory(history[id], def, resolved);
    }
    if (fields) {
      root._fields = fields;
      root._outputs = outputs;
      root._history = history;
    }
  }

  // A sample (a script's output object, as the editor keeps it) resolved as
  // widget `id`'s live output would be, as a successful run: null without
  // the definition or a sample. What the editor previews a screen with
  function resolveSample(id, sample) {
    const def = CustomWidgetsConfig.definition(id);
    if (!def || sample === null || sample === undefined)
      return null;
    return CustomWidgetData.resolve(def, sample, root._context(id, {
      "exitCode": 0,
      "error": "",
      "stderr": "",
      "text": CustomWidgetData.asText(sample.text),
      "exited": false
    }));
  }

  // As resolveSample, for a definition that isn't in the config (a gallery
  // template, defaults filled): its sample as a successful run's fields
  function resolveFor(def, sample) {
    return CustomWidgetData.resolve(def, sample, root._contextFor(def, {
      "exitCode": 0,
      "error": "",
      "stderr": "",
      "text": CustomWidgetData.asText(sample.text),
      "exited": false
    }));
  }

  // A new sample of widget `id`: a grace ends, a running hold notes it
  // (so its exit ends it)
  function _sampled(id) {
    const hold = root._busy[id];
    if (!hold)
      return;
    if (hold.phase === "grace")
      root._setBusy(id, undefined);
    else if (!hold.sampled)
      root._setBusy(id, Object.assign({}, hold, {
        "sampled": true
      }));
  }

  // What resolve needs besides the definition and the sample (its
  // `context`): the theme's colour names, the script's last run (`output`,
  // an entry of `outputs`), whether the definition is interactive (it has
  // an action command, or screens) and the failure messages. `{0}` is the exit code,
  // `{1}` the script's last stderr line.
  function _context(id, output) {
    return root._contextFor(CustomWidgetsConfig.definition(id), output);
  }

  function _contextFor(def, output) {
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
      const raw = b === "" ? resolved.value : CustomWidgetData.elementValue(resolved, b);
      // A list is the series itself (CustomWidgetData.series): no history
      if (Array.isArray(raw))
        continue;
      const v = b === "" ? raw : parseFloat(raw);
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

  // The IPC's act and actValue: widget `name`'s action `action`, discrete,
  // refused while nothing shows the widget; "" or why not
  function _ipcAct(name, action, value) {
    const def = root.find(name);
    if (!def)
      return `no custom widget "${name}"`;
    return root.invoke(def.id, action, value, false, true);
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

    // Run a named action of a custom widget (its name as `refresh`) as a
    // press would, holding it as one does. Answers "" when it ran, else why
    // not: "not shown" (nothing shows the widget: a stream isn't running),
    // "locked", "refused", "no action command", "failing", "disabled" or "busy"
    function act(name: string, action: string): string {
      return root._ipcAct(name, action, undefined);
    }

    // As act, with `value` as the action's {value}
    function actValue(name: string, action: string, value: string): string {
      return root._ipcAct(name, action, value);
    }

    // The custom widgets: id, refresh name and name, one a line
    function list(): string {
      return CustomWidgetsConfig.items.map(d => `${d.id}\t${d.refreshName}\t${d.name}`).join("\n");
    }
  }
}

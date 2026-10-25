pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.services.core
import qs.services.compositor

/*
 * Hooks theme integrations into their apps' configs: each ThemeIntegrations
 * switch's `x-hookup` targets (the line that loads its axiom file, where it
 * goes), run by scripts/integration_hookup.py. `check(key)` fills
 * `status[key]` ({ targets: [...] }: per target its text, file, whether it's
 * done, the lines it would comment out, ...); `apply(key)` backs each
 * changed file up beside it and edits it, then checks again, leaving the
 * script's results in `results[key]`. Nothing is polled: the hookup panel
 * checks when it's shown. Only an Apply click edits a user's config (and an
 * Apply that changed something runs the integration again).
 *
 * Three keys aren't theme integrations: "compositorInclude" (the lines that
 * load axiom's module, and the autostart line), "compositorAutostart" (only the
 * latter), in the user's compositor config, for the onboarding's Compositor
 * page and the settings' Compositor card, and "compositorModule" (only the
 * former), for CompositorConfigManager's notification that the module isn't
 * loaded.
 * Their targets come from CompositorConfigManager (its writer), passed to the script.
 */
Singleton {
  id: root

  // key -> { targets: [...] } from the last check
  property var status: ({})
  // key -> [{ path, changed, backup, error }] from the last apply
  property var results: ({})
  // key -> true while a check or apply for it is queued or running
  property var busy: ({})

  readonly property var _given: ({
      "compositorInclude": [CompositorConfigManager.includeTarget, CompositorConfigManager.autostartTarget].filter(target => target !== null),
      "compositorAutostart": [CompositorConfigManager.autostartTarget].filter(target => target !== null),
      "compositorModule": [CompositorConfigManager.includeTarget].filter(target => target !== null)
    })

  // The x-hookup targets of an integration, as the schema has them
  function targets(key) {
    return root._given[key] ?? ConfigManager.configSchema.properties.ThemeIntegrations.properties[key]?.["x-hookup"] ?? [];
  }

  // The x-hookupNote of an integration, untranslated ("" if none)
  function note(key) {
    return ConfigManager.configSchema.properties.ThemeIntegrations.properties[key]?.["x-hookupNote"] ?? "";
  }

  // Whether every target Apply can do is done (false until checked, and
  // for an integration that's only copied)
  function isDone(key) {
    const targets = (root.status[key]?.targets ?? []).filter(t => !t.copyOnly && !t.skipped);
    return targets.length > 0 && targets.every(t => t.done);
  }

  function check(key) {
    root._enqueue("status", key);
  }

  function apply(key) {
    root._enqueue("apply", key);
  }

  // [{ action, key }] waiting for the process
  property var _queue: []

  function _setBusy(key, on) {
    const next = Object.assign({}, root.busy);
    if (on)
      next[key] = true;
    else
      delete next[key];
    root.busy = next;
  }

  function _enqueue(action, key) {
    if (root.targets(key).length === 0)
      return;
    if (root._queue.some(item => item.action === action && item.key === key))
      return;
    root._queue = root._queue.concat([
      {
        "action": action,
        "key": key
      }
    ]);
    root._setBusy(key, true);
    // Later: a panel checks while it's being built, before the Process can
    // start, and this batches the panels a page shows at once
    Qt.callLater(root._next);
  }

  function _next() {
    if (_process.running || root._queue.length === 0)
      return;
    const item = root._queue[0];
    root._queue = root._queue.slice(1);
    _process.item = item;
    _process.command = ["python3", Paths.scriptsPath + "integration_hookup.py", item.action, item.key].concat(root._given[item.key] ? ["--targets", JSON.stringify(root._given[item.key])] : []);
    _process.running = true;
  }

  function _done(item, text, exitCode) {
    let data = null;
    try {
      data = JSON.parse(text);
    } catch (e) {
      data = null;
    }
    if (exitCode !== 0 || !data) {
      console.warn("[IntegrationHookupManager] integration_hookup.py", item.action, item.key, "failed:", _errors.text.trim() || "exited with " + exitCode);
    } else if (item.action === "status") {
      const next = Object.assign({}, root.status);
      next[item.key] = data;
      root.status = next;
    } else {
      const next = Object.assign({}, root.results);
      next[item.key] = data.results;
      root.results = next;
      for (const result of data.results)
        if (result.error)
          console.warn("[IntegrationHookupManager]", item.key, result.path, result.error);
      // Its axiom file (or ncspot's block, filled between the markers just
      // added) is written for the current theme now, not at the next change
      if (!root._given[item.key] && data.results.some(result => result.changed))
        ThemeManager.themeIntegrations(ThemeManager.activeTheme, [item.key]);
      // What it looks like now
      root._queue = [
        {
          "action": "status",
          "key": item.key
        }
      ].concat(root._queue);
    }
    if (!root._queue.some(queued => queued.key === item.key))
      root._setBusy(item.key, false);
    Qt.callLater(root._next);
  }

  Process {
    id: _process
    property var item: null
    property int _exitCode: -1
    property bool _outDone: false
    property bool _errDone: false

    function _report() {
      if (_exitCode < 0 || !_outDone || !_errDone)
        return;
      root._done(item, _out.text, _exitCode);
    }

    onRunningChanged: if (running) {
      _exitCode = -1;
      _outDone = false;
      _errDone = false;
    }
    onExited: exitCode => {
      _exitCode = exitCode;
      _report();
    }
    stdout: StdioCollector {
      id: _out
      onStreamFinished: {
        _process._outDone = true;
        _process._report();
      }
    }
    stderr: StdioCollector {
      id: _errors
      onStreamFinished: {
        _process._errDone = true;
        _process._report();
      }
    }
  }
}

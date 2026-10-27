pragma Singleton
import QtQuick
import Quickshell
import qs.services.core
import qs.services.compositor

/*
 * Hooks theme integrations into their apps' configs: each ThemeIntegrations
 * switch's `x-hookup` targets (the line that loads its axiom file, where it
 * goes), checked and applied by the daemon (hookup.status, hookup.apply).
 * `check(key)` fills `status[key]` ({ targets: [...] }: per target its text, file, whether it's
 * done, the lines it would comment out, ...); `apply(key)` backs each
 * changed file up beside it and edits it, then checks again, leaving the
 * daemon's results in `results[key]`. Nothing is polled: the hookup panel
 * checks when it's shown. Only an Apply click edits a user's config (and an
 * Apply that changed something runs the integration again).
 *
 * Three keys aren't theme integrations: "compositorInclude" (the lines that
 * load axiom's module, and the autostart line), "compositorAutostart" (only the
 * latter), in the user's compositor config, for the onboarding's Compositor
 * page and the settings' Compositor card, and "compositorModule" (only the
 * former), for CompositorConfigManager's notification that the module isn't
 * loaded.
 * Their targets come from CompositorConfigManager (the daemon's writer),
 * passed with the call.
 */
Singleton {
  id: root

  // key -> { targets: [...] } from the last check
  property var status: ({})
  // key -> [{ path, changed, backup, error }] from the last apply
  property var results: ({})
  // key -> true while a check or apply for it is running
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
    if (root.targets(key).length === 0)
      return;
    root._setBusy(key, 1);
    BackendManager.call("hookup.status", {
      "key": key,
      "targets": root._given[key]
    }, (error, result) => {
      root._setBusy(key, -1);
      if (error) {
        console.warn("[IntegrationHookupManager] checking", key, "failed:", error.message);
        return;
      }
      const next = Object.assign({}, root.status);
      next[key] = result;
      root.status = next;
    });
  }

  function apply(key) {
    if (root.targets(key).length === 0)
      return;
    root._setBusy(key, 1);
    BackendManager.call("hookup.apply", {
      "key": key,
      "targets": root._given[key]
    }, (error, result) => {
      if (error) {
        root._setBusy(key, -1);
        console.warn("[IntegrationHookupManager] applying", key, "failed:", error.message);
        return;
      }
      const next = Object.assign({}, root.results);
      next[key] = result.results;
      root.results = next;
      for (const r of result.results)
        if (r.error)
          console.warn("[IntegrationHookupManager]", key, r.path, r.error);
      // Its axiom file (or ncspot's block, filled between the markers just
      // added) is written for the current theme now, not at the next change
      if (!root._given[key] && result.results.some(r => r.changed))
        ThemeManager.themeIntegrations(ThemeManager.activeTheme, [key]);
      // What it looks like now (busy until that's back)
      root.check(key);
      root._setBusy(key, -1);
    });
  }

  // key -> calls in flight
  property var _calls: ({})

  function _setBusy(key, change) {
    const calls = Object.assign({}, root._calls);
    calls[key] = (calls[key] ?? 0) + change;
    const next = Object.assign({}, root.busy);
    if (calls[key] > 0)
      next[key] = true;
    else {
      delete calls[key];
      delete next[key];
    }
    root._calls = calls;
    root.busy = next;
  }
}

pragma Singleton

import QtQuick
import Quickshell

import qs.config
import qs.components.methods
import qs.services.core
import qs.services.system
import qs.services.ui

/*
 * The Monitors page: the connected outputs (CompositorManager.
 * withOutputDetails, read at startup and when monitors come, go or the
 * config reloads; never polled) and the editor for Monitors.items, a
 * draft of profiles (each a layout for one set of monitors). The saved
 * profile matching what's connected is picked and applied on every
 * hotplug by the daemon, which names it (CompositorConfigManager.
 * monitorProfile); the page finds that name in the draft.
 *
 * Apply tries the selected profile at once (CompositorManager.applyOutputs)
 * and asks to keep it: keep() saves the draft, and revert() (or the
 * countdown running out) puts back what was there before, on the monitors
 * and in the draft. A QML reload keeps the trial (its countdown starts
 * over). Apply shows while the draft differs from the saved config or
 * from the monitors as they are (differsFromLive).
 *
 * A monitor connected or removed (seen between two reads) is said where
 * the OSD's `monitor` status or Monitors.notify puts it (lastEvent).
 */
Singleton {
  id: root

  // The outputs in detail (CompositorManager.withOutputDetails), disabled
  // ones included
  property var outputs: []
  readonly property var enabledOutputs: outputs.filter(monitor => !monitor.disabled)

  // --- The draft ---

  property ConfigDraft _draft: ConfigDraft {
    id: draft
    path: ["Monitors"]
  }
  readonly property var profiles: draft.local?.items ?? []
  readonly property alias isDirty: draft.isDirty

  // The profile shown on the page
  property int selectedProfile: 0
  readonly property var profile: profiles[selectedProfile] ?? null
  readonly property var rules: profile?.outputs ?? []
  // The selected output (its rule's `output`)
  property string selectedOutput: ""
  readonly property int selectedIndex: rules.findIndex(rule => rule.output === selectedOutput)
  readonly property var selectedRule: rules[selectedIndex] ?? null

  // The draft's profile for what's connected: the one _detect found (the
  // daemon's match, by name: names are unique) or made, through renames
  readonly property int liveProfile: _named(profiles, _liveName)
  property string _liveName: ""
  // The selected profile is for what's connected: Apply tries it live
  readonly property bool selectedIsLive: selectedProfile === liveProfile

  // Loads the draft unless it holds unsaved edits (the page is rebuilt
  // whenever the overlay reopens), with a profile for what's connected
  function ensureLoaded() {
    if (!draft.isDirty) {
      draft.load();
      _detectPending = true;
    }
    refresh();
  }

  // Detect once the monitors have been read
  property bool _detectPending: false
  // The page is open: a monitor coming or going re-detects (unless edited)
  property bool pageShown: false
  // The inspector's Advanced section is unfolded
  property bool advancedOpen: false

  function save() {
    draft.save();
  }

  function reset() {
    draft.load();
    _detect();
  }

  onOutputsChanged: {
    if (_wholeScalePending && outputs.length > 0)
      useWholeScale();
    if (_detectPending && outputs.length > 0) {
      _detectPending = false;
      _detect();
    }
  }

  // The connected monitor a rule is for, or null
  function monitorFor(rule) {
    return rule ? MonitorLayout.find(rule.output, outputs) : null;
  }

  // A rule's rect in the layout
  function rectFor(rule) {
    return MonitorLayout.ruleRect(rule, monitorFor(rule));
  }

  // What's connected, as a profile: the one the daemon matched (adding any
  // monitor it doesn't list), else a new one from how they are
  function _detect() {
    if (outputs.length === 0)
      return;
    const local = draft.local ?? {
      "items": []
    };
    draft.local = local;
    local.items = local.items ?? [];
    let index = _named(local.items, CompositorConfigManager.monitorProfile);
    let edited = false;
    if (index < 0) {
      local.items.push(_newProfile(local.items.length));
      index = local.items.length - 1;
      edited = true;
    } else {
      const listed = local.items[index].outputs;
      for (const monitor of outputs)
        if (!listed.some(rule => MonitorLayout.matches(rule.output, monitor))) {
          listed.push(MonitorLayout.ruleFromMonitor(monitor, outputs));
          edited = true;
        }
    }
    selectProfile(index);
    _liveName = local.items[index].name;
    if (edited)
      draft.changed();
    _detected = JSON.stringify(draft.local);
  }

  // The index of the profile called `name` in `list`, -1 for "" or none
  function _named(list, name) {
    return name ? list.findIndex(profile => profile.name === name) : -1;
  }

  // The draft as _detect left it
  property string _detected: ""

  // The draft holds no edits but detection's: a hotplug or the daemon's
  // new match may detect again
  function _untouched() {
    return !draft.isDirty || JSON.stringify(draft.local) === _detected;
  }

  // The daemon's match for a hotplug may come after the page's read: it
  // detects again (unless a detect is still waiting for the read, which
  // will use it). Otherwise the live profile follows the name, the page
  // closed or not.
  property Connections _match: Connections {
    target: CompositorConfigManager

    function onMonitorProfileChanged() {
      if (root.pending || root._detectPending)
        return;
      if (root.pageShown && root._untouched())
        root.reset();
      else
        root._liveName = CompositorConfigManager.monitorProfile;
    }
  }

  function _uniqueName(name) {
    let result = name;
    for (let n = 2; profiles.some(profile => profile.name === result); n++)
      result = `${name} (${n})`;
    return result;
  }

  // --- Editing ---

  // The selected profile's rule for an output, in the draft, or undefined
  function _ruleOf(output) {
    return draft.local?.items?.[selectedProfile]?.outputs?.find(r => r.output === output);
  }

  // A profile from how the monitors are now, named after its place
  function _newProfile(count) {
    return {
      "name": _uniqueName(I18n.tr("Layout {0}", count + 1)),
      "outputs": outputs.map(monitor => MonitorLayout.ruleFromMonitor(monitor, outputs))
    };
  }

  function setField(output, key, value) {
    const rule = _ruleOf(output);
    if (!rule || rule[key] === value)
      return;
    rule[key] = value;
    draft.changed();
  }

  function move(output, x, y) {
    const rule = _ruleOf(output);
    const rx = Math.round(x);
    const ry = Math.round(y);
    if (!rule || (rule.x === rx && rule.y === ry))
      return;
    rule.x = rx;
    rule.y = ry;
    draft.changed();
  }

  // Shows a profile, keeping the selected monitor if the profile has it
  function selectProfile(index) {
    const listed = draft.local?.items?.[index]?.outputs ?? [];
    selectedProfile = index;
    if (!listed.some(rule => rule.output === selectedOutput))
      selectedOutput = listed[0]?.output ?? "";
  }

  function newProfile() {
    draft.local.items.push(_newProfile(profiles.length));
    draft.changed();
    selectProfile(draft.local.items.length - 1);
  }

  function renameProfile(index, name) {
    const target = draft.local?.items?.[index];
    if (!target || target.name === name)
      return;
    if (target.name === _liveName)
      _liveName = name;
    target.name = name;
    draft.changed();
  }

  function removeProfile(index) {
    if (!draft.local?.items?.[index])
      return;
    draft.local.items.splice(index, 1);
    draft.changed();
    selectProfile(Math.max(0, Math.min(selectedProfile, draft.local.items.length - 1)));
  }

  // Leaves an output out of the profile (one that isn't connected)
  function forgetOutput(output) {
    const list = draft.local?.items?.[selectedProfile]?.outputs;
    const index = list ? list.findIndex(rule => rule.output === output) : -1;
    if (index < 0)
      return;
    list.splice(index, 1);
    draft.changed();
  }

  // --- Checks ---

  // Outputs laid out on their own (not disabled, not mirroring)
  readonly property var placedRules: rules.filter(rule => !rule.disabled && !rule.mirror)
  readonly property var placedRects: placedRules.map(rule => rectFor(rule))

  // [{ level: "error" | "warning", text }]: errors block Apply
  readonly property var issues: {
    const result = [];
    const placed = root.placedRules;
    for (const [a, b] of MonitorLayout.overlaps(root.placedRects))
      result.push({
        "level": "error",
        "text": I18n.tr("{0} and {1} overlap", root.labelFor(placed[a]), root.labelFor(placed[b]))
      });
    if (placed.length === 0 && root.rules.length > 0)
      result.push({
        "level": "error",
        "text": I18n.tr("Every monitor is off")
      });
    for (const index of MonitorLayout.islands(root.placedRects))
      result.push({
        "level": "warning",
        "text": I18n.tr("{0} doesn't touch the others, so the cursor can't reach it", root.labelFor(placed[index]))
      });
    for (const rule of root.rules) {
      if (rule.mirror && !root.rules.some(other => other.output === rule.mirror && !other.disabled && !other.mirror))
        result.push({
          "level": "error",
          "text": I18n.tr("{0} mirrors a monitor that isn't shown", root.labelFor(rule))
        });
      const monitor = root.monitorFor(rule);
      const mode = MonitorLayout.parseMode(rule.mode);
      if (monitor && mode && !rule.disabled && MonitorLayout.validScales(mode.width, mode.height).indexOf(rule.scale) < 0)
        result.push({
          "level": "warning",
          "text": I18n.tr("{0}'s scale is rounded to one that fits its resolution", root.labelFor(rule))
        });
    }
    for (const file of CompositorConfigManager.monitorConflicts)
      result.push({
        "level": "warning",
        "text": I18n.tr("{0} sets monitors too, and loads after axiom, so its rules win", file)
      });
    return result;
  }
  readonly property bool canApply: !issues.some(issue => issue.level === "error")
  // The selected profile isn't what the connected monitors show (a
  // layout the compositor didn't take, or set elsewhere): Apply shows
  // though nothing is unsaved (MonitorLayout.differsFromLive). Not while
  // a change settles: the outputs are read again once it has
  readonly property bool differsFromLive: selectedIsLive && !_refreshSoon.running && !_reading && MonitorLayout.differsFromLive(rules, outputs)

  // A rule's name on the page: its connector, else its description
  function labelFor(rule) {
    const monitor = monitorFor(rule);
    return monitor?.name || rule?.label || String(rule?.output ?? "").replace(/^desc:/, "");
  }

  // --- Apply, keep, revert ---

  // Waiting for keep()/revert() after Apply
  readonly property bool pending: _trial.state !== ""
  property int secondsLeft: 0
  readonly property int confirmSeconds: 15

  // The trial, kept across a QML reload so its way back is too: JSON of
  // { rules, details } putting back what was there before Apply, the
  // draft it tried (keep() saves it) and the name of the profile tried,
  // "" when none
  PersistentProperties {
    id: _trial
    reloadableId: "axiomMonitorTrial"
    property string state: ""

    // After the draft's own load
    onLoaded: if (state !== "")
      Qt.callLater(root._resume)
  }

  function _resume() {
    draft.local = JSON.parse(_trial.state).draft;
    draft.changed();
    secondsLeft = confirmSeconds;
    _countdown.restart();
  }

  // Tries the selected profile now; keep() saves it. A profile for other
  // monitors can only be saved.
  function apply() {
    if (!canApply || pending || !CompositorManager.supports.monitors)
      return;
    if (!selectedIsLive) {
      save();
      return;
    }
    const all = outputs;
    _trial.state = JSON.stringify({
      "rules": all.map(monitor => MonitorLayout.ruleFromMonitor(monitor, all)),
      "details": all,
      "draft": draft.local,
      "profile": profile.name
    });
    CompositorManager.applyOutputs(rules.filter(rule => monitorFor(rule) !== null), all);
    secondsLeft = confirmSeconds;
    _countdown.restart();
    _refreshSoon.restart();
  }

  function keep() {
    if (!pending)
      return;
    const trial = _end();
    if (!draft.save()) {
      console.warn("[MonitorManager] Could not save the monitor layout; putting the old one back");
      _runRevert(trial);
    }
  }

  function revert() {
    if (pending)
      _runRevert(_end());
  }

  // Ends the trial, returning its state
  function _end() {
    const trial = JSON.parse(_trial.state);
    _trial.state = "";
    _countdown.stop();
    return trial;
  }

  // Puts back the monitors as they were before Apply, and the profile
  // tried in the draft as they were (the same for revert(), the countdown
  // and a keep() that couldn't save): what the page shows is then what's
  // on the monitors, unsaved where the saved profile differs
  function _runRevert(trial) {
    CompositorManager.applyOutputs(trial.rules, trial.details);
    const items = draft.local?.items ?? [];
    const tried = items[_named(items, trial.profile ?? _liveName)];
    if (tried) {
      tried.outputs = MonitorLayout.restored(tried.outputs, trial.rules, trial.details);
      draft.changed();
    }
    _refreshSoon.restart();
  }

  property Timer _countdown: Timer {
    interval: 1000
    repeat: true
    onTriggered: {
      root.secondsLeft--;
      if (root.secondsLeft <= 0)
        root.revert();
    }
  }

  // --- Identify ---

  // Each screen shows its name for a moment
  property bool identifying: false

  function identify() {
    identifying = true;
    _identifyTimer.restart();
  }

  property Timer _identifyTimer: Timer {
    interval: 3000
    onTriggered: root.identifying = false
  }

  // --- Primary ---

  function setPrimary(name) {
    SettingsManager.commitValue("General.primaryMonitor", name);
  }

  // --- Reading the monitors ---

  function refresh() {
    if (_reading || !CompositorManager.supports.monitors)
      return;
    _reading = true;
    CompositorManager.withOutputDetails(outputs => {
      root._reading = false;
      if (!outputs)
        return;
      const before = root.outputs;
      root.outputs = outputs;
      // A monitor connected or unplugged ends a trial without reverting:
      // the daemon has applied the saved profile for the new set. One the
      // trial turned off or mirrors is still listed, so it doesn't
      if (root._read && root._sayHotplugs(before, outputs) && root.pending)
        root._end();
      root._read = true;
    });
  }

  property bool _reading: false
  // The monitors have been read once: what's connected at the start isn't
  // a hotplug
  property bool _read: false

  // --- Monitors coming and going ---

  // The last monitor connected or removed, for the OSD's `monitor`
  // status: { kind: "added" | "removed", name, description, width,
  // height, serial }, else null. Set only when the OSD says it
  // (_sayHotplugs)
  property var lastEvent: null
  property int _serial: 0

  // Each monitor connected or removed between two reads (by connector,
  // disabled ones included: turning one off isn't unplugging it), where
  // the OSD's `monitor` status or Monitors.notify puts it
  // (NotificationManager.announce): its card, a notification, or nothing.
  // Returns whether there was one
  function _sayHotplugs(before, after) {
    const names = list => list.map(monitor => monitor.name);
    const added = after.filter(monitor => !names(before).includes(monitor.name));
    const removed = before.filter(monitor => !names(after).includes(monitor.name));
    for (const monitor of added)
      root._sayHotplug("added", monitor);
    for (const monitor of removed)
      root._sayHotplug("removed", monitor);
    return added.length + removed.length > 0;
  }

  function _sayHotplug(kind, monitor) {
    const label = monitor.description || monitor.name;
    const size = monitor.width > 0 ? `${monitor.width}×${monitor.height}` : "";
    const summary = kind === "added" ? I18n.tr("{0} connected", label) : I18n.tr("{0} disconnected", label);
    const body = [monitor.description ? monitor.name : "", size].filter(part => part !== "").join(" · ");
    // Silent (the Quiet section): one entry per connector, its last change
    if (NotificationManager.announce("monitor", MonitorsConfig.notify, summary, body, {
      "icon": "video-display",
      "desktopEntry": root._desktopEntry,
      "key": "monitor:" + monitor.name,
      "silent": true
    }) !== "osd")
      return;
    root._serial += 1;
    root.lastEvent = {
      "kind": kind,
      "name": monitor.name,
      "description": monitor.description ?? "",
      "width": monitor.width ?? 0,
      "height": monitor.height ?? 0,
      "serial": root._serial
    };
  }

  // Mode changes send no event: read again once they've settled
  property Timer _refreshSoon: Timer {
    interval: 600
    onTriggered: root.refresh()
  }

  // --- First run ---

  // Hyprland's example config scales monitors "auto", often a fractional
  // 1.25 or 1.5 on a laptop, which blurs and misaligns the shell. The
  // onboarding, finding it on a first run, rounds those down: a saved
  // layout with every scale whole (MonitorLayout.wholeScaleRules), which
  // axiom's layer applies like any other. A whole scale (2 on a HiDPI
  // panel) is left alone, and nothing happens once a layout is saved, or
  // when no scale is fractional.
  function useWholeScale() {
    if (outputs.length === 0) {
      _wholeScalePending = true;
      refresh();
      return;
    }
    _wholeScalePending = false;
    if (MonitorsConfig.profiles.length > 0 || !enabledOutputs.some(monitor => !Number.isInteger(monitor.scale)))
      return;
    SettingsManager.commitValues({
      "Monitors.items": [
        {
          "id": "layout-1",
          "name": I18n.tr("Layout {0}", 1),
          "outputs": MonitorLayout.wholeScaleRules(outputs)
        }
      ]
    });
    // After the config writer has applied it (debounced, then evaluated)
    _refreshLater.restart();
  }

  property bool _wholeScalePending: false

  property Timer _refreshLater: Timer {
    interval: 2000
    onTriggered: root.refresh()
  }

  property Connections _events: Connections {
    target: CompositorManager

    function onOutputsHotplugged() {
      if (root.pageShown && !root.pending && root._untouched()) {
        draft.load();
        root._detectPending = true;
      }
      root._refreshSoon.restart();
    }
    function onConfigReloaded() {
      root._refreshSoon.restart();
    }
  }

  // Read as soon as the compositor is known to have monitors: created early
  // in the shell's start, this can come before CompositorManager.supports
  // is filled in, and a refresh then does nothing
  readonly property bool _canRead: CompositorManager.supports.monitors === true
  on_CanReadChanged: refresh()
  // The monitors' notifications: a click opens their settings
  readonly property string _desktopEntry: "axiom-monitors"

  Component.onCompleted: {
    NotificationManager.registerHandler(root._desktopEntry, () => SettingsManager.openSetting("Monitors"));
    refresh();
  }

  // Recovers from a layout that can't be seen: `axiom ipc
  // monitors revert`
  property IpcTarget _ipc: IpcTarget {
    target: "monitors"

    function open(): void {
      ShellManager.openOverlayPage("Monitors");
    }

    function keep(): void {
      root.keep();
    }

    function revert(): void {
      root.revert();
    }

    function identify(): void {
      root.identify();
    }
  }
}

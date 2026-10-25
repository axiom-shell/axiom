pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Polkit

import qs.config
import qs.components.methods
import qs.services.compositor

/*
 * axiom as the session's polkit agent (the Polkit section): while
 * PolkitConfig.enabled, a PolkitAgent answers apps' requests for
 * administrator rights, and PolkitWindow (shell/PolkitPrompt) shows each
 * one. A session has one agent, so registering fails while another holds
 * it: axiom then stops the known ones (methods/PolkitAgents), their
 * systemd user units included, and registers again. 15 s after it starts
 * it looks once more, for an agent a user's own autostart launched after
 * qs. Turned off, the units it stopped start again. Requests queue in
 * Quickshell, one flow at a time; a reload keeps the registration and the
 * open flow.
 *
 * Nothing is polled. Created from shell.qml's `_services`.
 */
Singleton {
  id: root

  // The PolkitAgent while enabled, else null
  readonly property var agent: loader.item
  readonly property bool registered: agent?.isRegistered ?? false
  // The request being answered (an AuthFlow), else null
  readonly property var flow: agent?.flow ?? null
  // "off" | "starting" | "running" | "blocked" (another agent, or no
  // logind session, kept it from registering)
  readonly property string status: !PolkitConfig.enabled ? "off" : registered ? "running" : _blocked ? "blocked" : "starting"
  // Process names of the agents axiom stopped since it started
  readonly property var replaced: JSON.parse(_state.replaced)
  // The monitor the open request shows on: the focused one when it came in
  readonly property string screenName: _screenName
  // From pkaction, for the open request: { description, vendor, vendorUrl }
  readonly property var actionInfo: _actionInfo

  // Authenticate as another of the request's identities (restarts it)
  function selectIdentity(identity) {
    if (root.flow && identity)
      root.flow.selectedIdentity = identity;
  }

  function submit(response) {
    if (root.flow && root.flow.isResponseRequired)
      root.flow.submit(response);
  }

  function cancel() {
    if (root.flow)
      root.flow.cancelAuthenticationRequest();
  }

  property string _screenName: ""
  property var _actionInfo: ({})
  property bool _blocked: false
  // Took the agent down to register again (Quickshell deletes the old one
  // later, and a new one made before then doesn't register)
  property bool _paused: false
  property bool _retried: false
  // Units axiom stopped (started again when it's turned off) and the
  // agents it stopped, as JSON: kept across a reload, as the agent is
  PersistentProperties {
    id: _state
    reloadableId: "axiomPolkit"
    property string stoppedUnits: "[]"
    property string replaced: "[]"
  }
  readonly property var _stoppedUnits: JSON.parse(_state.stoppedUnits)

  property LazyLoader _loader: LazyLoader {
    id: loader
    active: PolkitConfig.enabled && !root._paused

    PolkitAgent {
      onAuthenticationRequestStarted: root._requestStarted()
    }
  }

  function _requestStarted() {
    root._screenName = CompositorManager.focusedOutput || General.primaryMonitor;
    root._actionInfo = {};
    const flow = root.flow;
    if (!flow)
      return;
    // Polkit lists the admin group's users first, often root: start on the
    // user's own identity when it's one of them
    const user = Quickshell.env("USER");
    const own = flow.identities.find(identity => !identity.isGroup && identity.string === user);
    if (own && flow.selectedIdentity !== own)
      flow.selectedIdentity = own;
    root._describe();
  }

  // The action pkaction is describing: a request that came in meanwhile
  // is described once it's done, and never gets another's description
  property string _describing: ""

  function _describe() {
    const id = root.flow?.actionId ?? "";
    if (id === "" || pkaction.running)
      return;
    root._describing = id;
    pkaction.command = ["pkaction", "--verbose", "--action-id", id];
    pkaction.running = true;
  }

  Process {
    id: pkaction
    stdout: StdioCollector {
      onStreamFinished: {
        const info = {};
        for (const line of text.split("\n")) {
          const match = line.match(/^\s+(description|vendor|vendor_url):\s*(.*)$/);
          if (match)
            info[match[1] === "vendor_url" ? "vendorUrl" : match[1]] = match[2].trim();
        }
        if (root.flow?.actionId === root._describing)
          root._actionInfo = info;
      }
    }
    onExited: {
      if ((root.flow?.actionId ?? root._describing) !== root._describing)
        Qt.callLater(root._describe);
    }
  }

  // --- Other agents ---

  // Registering takes a D-Bus round trip; still not registered by now, it
  // failed
  property Timer _registerCheck: Timer {
    interval: 2000
    onTriggered: {
      if (!root.agent || root.registered)
        return;
      root._probe(names => {
        if (names.length > 0 && !root._retried) {
          root._retried = true;
          root._stopOthers(true);
        } else {
          root._blocked = true;
          console.warn("[PolkitManager] Could not register as the polkit agent", names.length > 0 ? `(still running: ${names.join(", ")})` : "");
        }
      });
    }
  }

  // An agent a user's own autostart started after qs: it couldn't
  // register, so it only waits; stop it, so the settings can say so
  property Timer _lateCheck: Timer {
    interval: 15000
    onTriggered: {
      if (root.registered)
        root._probe(names => {
          if (names.length > 0)
            root._stopOthers(false);
        });
    }
  }

  property Timer _resume: Timer {
    interval: 300
    onTriggered: root._paused = false
  }

  onAgentChanged: {
    if (agent)
      _registerCheck.restart();
  }

  property Connections _config: Connections {
    target: PolkitConfig
    function onEnabledChanged() {
      root._blocked = false;
      root._retried = false;
      if (PolkitConfig.enabled) {
        root._lateCheck.restart();
      } else if (root._stoppedUnits.length > 0) {
        restartUnits.command = ["systemctl", "--user", "start"].concat(root._stoppedUnits);
        restartUnits.running = true;
        _state.stoppedUnits = "[]";
      }
    }
  }

  // Calls `then` with the known agents running, by process name
  function _probe(then) {
    root._probeWaiting.push(then);
    if (!probe.running)
      probe.running = true;
  }

  property var _probeWaiting: []

  function _agentNames(text) {
    const names = [];
    for (const line of text.split("\n")) {
      const executable = line.trim().split(/\s+/)[1] ?? "";
      const name = executable.replace(/^.*\//, "");
      if (PolkitAgents.agents.some(agent => agent.process === name) && !names.includes(name))
        names.push(name);
    }
    return names;
  }

  Process {
    id: probe
    command: ["pgrep", "-af", PolkitAgents.processPattern]
    stdout: StdioCollector {
      onStreamFinished: {
        const waiting = root._probeWaiting;
        root._probeWaiting = [];
        const names = root._agentNames(text);
        for (const then of waiting)
          then(names);
      }
    }
  }

  // Stop the running units, then any agent process left; prints
  // "unit <name>" for each unit stopped, and the processes it stops
  readonly property string _stopScript: 'pattern=$1; shift; for unit in "$@"; do systemctl --user -q is-active "$unit" 2>/dev/null && systemctl --user stop "$unit" && echo "unit $unit"; done; pgrep -af "$pattern"; pkill -f "$pattern"; true'

  property bool _registerAfterStop: false

  function _stopOthers(register) {
    if (stopper.running)
      return;
    root._registerAfterStop = register;
    stopper.command = ["sh", "-c", _stopScript, "sh", PolkitAgents.processPattern].concat(PolkitAgents.units);
    stopper.running = true;
  }

  Process {
    id: stopper
    stdout: StdioCollector {
      onStreamFinished: {
        const units = text.split("\n").filter(line => line.startsWith("unit ")).map(line => line.slice(5).trim());
        const names = root._agentNames(text.split("\n").filter(line => !line.startsWith("unit ")).join("\n"));
        _state.stoppedUnits = JSON.stringify(root._stoppedUnits.concat(units.filter(unit => !root._stoppedUnits.includes(unit))));
        // A unit's agent is gone by the time its process would print
        const stopped = names.concat(units.map(unit => PolkitAgents.agents.find(agent => agent.unit === unit)?.process ?? unit.replace(/\.service$/, "")));
        _state.replaced = JSON.stringify(root.replaced.concat(stopped.filter((name, i) => stopped.indexOf(name) === i && !root.replaced.includes(name))));
        if (stopped.length > 0)
          console.log("[PolkitManager] Stopped", stopped.join(", "));
        if (root._registerAfterStop) {
          root._paused = true;
          root._resume.restart();
        }
      }
    }
  }

  Process {
    id: restartUnits
  }

  Component.onCompleted: {
    if (PolkitConfig.enabled)
      _lateCheck.start();
  }
}

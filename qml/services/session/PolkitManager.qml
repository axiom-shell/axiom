pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Polkit

import qs.config
import qs.components.methods
import qs.services.core
import qs.services.ui

/*
 * axiom as the session's polkit agent (the Polkit section): while
 * PolkitConfig.enabled, a PolkitAgent answers apps' requests for
 * administrator rights, and each one goes through the shared prompt's
 * queue (PromptManager), which draws its card (prompt/PolkitCard). A session has one agent, so registering fails while another holds
 * it: axiom then stops the known ones (methods/PolkitAgents), their
 * systemd user units included, and registers again. The daemon does the
 * looking and the stopping (polkit.probe, polkit.stopOthers), only in
 * this session, and records what it stopped: it starts them again when the
 * Polkit switch goes off (polkit.handBack), when axiom quits, and after a
 * crash. 15 s after it starts it looks once more, for an agent a user's own
 * autostart launched after qs. Requests queue in Quickshell, one flow at a
 * time; a reload keeps the registration and the open flow.
 *
 * rpc: polkit.probe, polkit.stopOthers, polkit.handBack
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

  property var _actionInfo: ({})
  property bool _blocked: false
  // Took the agent down to register again (Quickshell deletes the old one
  // later, and a new one made before then doesn't register)
  property bool _paused: false
  // Remakes since it was turned on or reloaded: a reload hands the new
  // generation the old listener as it is, so one that never registered
  // never retries
  property int _remakes: 0
  // The agents axiom stopped, as JSON: kept across a reload, as the agent is
  // (the daemon keeps what to start again)
  PersistentProperties {
    id: _state
    reloadableId: "axiomPolkit"
    property string replaced: "[]"
  }

  property LazyLoader _loader: LazyLoader {
    id: loader
    active: PolkitConfig.enabled && !root._paused

    PolkitAgent {
      onAuthenticationRequestStarted: root._requestStarted()
    }
  }

  // The open request's place in the shared prompt's queue, and the flow it
  // was queued for: a new flow queues again, so it's shown on the monitor
  // focused when it comes to the front
  property string _promptId: ""
  property var _promptFlow: null

  onFlowChanged: _syncPrompt()

  function _syncPrompt() {
    if (root.flow === root._promptFlow)
      return;
    if (root._promptId !== "")
      PromptManager.withdraw(root._promptId);
    root._promptFlow = root.flow;
    root._promptId = root.flow ? PromptManager.request({
      "content": "polkit",
      "outsideCancels": false
    }, null, () => root.cancel()) : "";
  }

  function _requestStarted() {
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

  // The action pkaction is describing ("" when it isn't running): a
  // request that came in meanwhile is described once it's done, and never
  // gets another's description
  property string _describing: ""

  function _describe() {
    const id = root.flow?.actionId ?? "";
    if (id === "" || root._describing !== "")
      return;
    root._describing = id;
    CommandManager.run(["pkaction", "--verbose", "--action-id", id], (code, stdout) => {
      root._describing = "";
      const info = {};
      for (const line of stdout.split("\n")) {
        const match = line.match(/^\s+(description|vendor|vendor_url):\s*(.*)$/);
        if (match)
          info[match[1] === "vendor_url" ? "vendorUrl" : match[1]] = match[2].trim();
      }
      if (root.flow?.actionId === id)
        root._actionInfo = info;
      else if ((root.flow?.actionId ?? id) !== id)
        Qt.callLater(root._describe);
    }, null, true);
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
        // Turned off (or registered) while the daemon looked
        if (!root.agent || root.registered)
          return;
        if (root._remakes < 3) {
          root._remakes++;
          if (names.length > 0)
            root._stopOthers(true);
          else
            root._remake();
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
      root._remakes = 0;
      if (PolkitConfig.enabled) {
        root._lateCheck.restart();
      } else {
        BackendManager.call("polkit.handBack", {}, error => {
          if (error)
            console.warn("[PolkitManager] Could not hand the agents back:", error.message);
        });
      }
    }
  }

  // Calls `then` with the known agents running in this session, by process name
  function _probe(then) {
    root._probeWaiting.push(then);
    if (root._probeWaiting.length > 1)
      return;
    BackendManager.call("polkit.probe", {
      "pattern": PolkitAgents.processPattern
    }, (error, result) => {
      const waiting = root._probeWaiting;
      root._probeWaiting = [];
      const names = error ? [] : root._agentNames(result.names);
      for (const then of waiting)
        then(names);
    });
  }

  property var _probeWaiting: []

  function _agentNames(names) {
    return names.filter((name, i) => names.indexOf(name) === i && PolkitAgents.agents.some(agent => agent.process === name));
  }

  property bool _stopping: false

  // The daemon stops the running units, then any agent process left, in
  // this session only, recording each to start again
  function _stopOthers(register) {
    if (root._stopping)
      return;
    root._stopping = true;
    BackendManager.call("polkit.stopOthers", {
      "pattern": PolkitAgents.processPattern,
      "units": PolkitAgents.units
    }, (error, result) => {
      root._stopping = false;
      if (error) {
        console.warn("[PolkitManager] Could not stop the other agents:", error.message);
        if (register)
          root._remake();
        return;
      }
      // A unit's agent is gone by the time its process would be listed
      const stopped = root._agentNames(result.names).concat(result.units.map(unit => PolkitAgents.agents.find(agent => agent.unit === unit)?.process ?? unit.replace(/\.service$/, "")));
      _state.replaced = JSON.stringify(root.replaced.concat(stopped.filter((name, i) => stopped.indexOf(name) === i && !root.replaced.includes(name))));
      if (stopped.length > 0)
        console.log("[PolkitManager] Stopped", stopped.join(", "));
      if (register)
        root._remake();
    });
  }

  // Deleting the agent deletes its listener, so the next registers afresh
  function _remake() {
    root._paused = true;
    root._resume.restart();
  }

  Component.onCompleted: {
    // A reload keeps the open flow
    root._syncPrompt();
    if (PolkitConfig.enabled)
      _lateCheck.start();
  }
}

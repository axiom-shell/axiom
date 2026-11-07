pragma Singleton

import QtQuick
import Quickshell.Services.Pipewire

import qs.config
import qs.services.core
import qs.services.ui
import qs.components.methods

// Pipewire audio state: the default output (sink) and input (source), every
// device and app stream, and helpers to control them. All audio nodes are
// tracked, which is what makes their `.audio` and `.properties` available.
QtObject {
  id: root

  // -- Nodes --
  readonly property var sinks: Pipewire.nodes.values.filter(n => n.type === PwNodeType.AudioSink)
  readonly property var sources: Pipewire.nodes.values.filter(n => n.type === PwNodeType.AudioSource)
  readonly property var _playbackStreams: Pipewire.nodes.values.filter(n => n.type === PwNodeType.AudioOutStream)
  readonly property var _recordingStreams: Pipewire.nodes.values.filter(n => n.type === PwNodeType.AudioInStream)

  property PwObjectTracker tracker: PwObjectTracker {
    objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource].concat(root.sinks, root.sources, root._playbackStreams, root._recordingStreams)
  }

  // App streams grouped per application (an app often opens several):
  // [{ key, name, icon, subtitle, nodes }]
  readonly property var playbackApps: groupByApp(_playbackStreams)
  readonly property var recordingApps: groupByApp(_recordingStreams)

  // -- Default output --
  readonly property var defaultSink: Pipewire.defaultAudioSink

  readonly property real volume: Pipewire.defaultAudioSink?.audio?.volume ?? 0
  readonly property bool muted: Pipewire.defaultAudioSink?.audio?.muted ?? false

  function increaseVolume(amount = 0.05) {
    stepNodeVolume(defaultSink, amount);
  }

  function decreaseVolume(amount = 0.05) {
    stepNodeVolume(defaultSink, -amount);
  }

  function toggleMute() {
    toggleNodeMute(defaultSink);
  }

  function setVolume(value) {
    setNodeVolume(defaultSink, value);
  }

  // The next output after the default one, round the list (keybind
  // action audioOutputNext)
  function nextOutput() {
    if (root.sinks.length < 2)
      return;
    setDefault(root.sinks[(root.sinks.indexOf(root.defaultSink) + 1) % root.sinks.length]);
  }

  // Volume keys (keybind actions volumeUp, ...): the OSD shows the change
  property IpcTarget _ipc: IpcTarget {
    target: "audio"

    function volumeUp(): void {
      root.increaseVolume();
    }

    function volumeDown(): void {
      root.decreaseVolume();
    }

    function toggleMute(): void {
      root.toggleMute();
    }

    function toggleMicMute(): void {
      root.toggleSourceMute();
    }

    // Says so on the OSD with only one output to switch to
    function nextOutput(): void {
      if (root.sinks.length < 2)
        ShellManager.refuse("speaker", I18n.tr("Audio output"), I18n.tr("No other output to switch to"));
      else
        root.nextOutput();
    }
  }

  // -- Default input --
  readonly property var defaultSource: Pipewire.defaultAudioSource

  // -- Settled defaults --

  // Whether the default output's / input's level and mute changing now is
  // the user's: the device has been the default, bound, since before the
  // change, and still is. A device switching, appearing, binding or going
  // away (a Bluetooth headset connecting, disconnecting or changing
  // profile) changes them too: a node going away turns unready, then has
  // its volumes cleared (reading 0) while it's still the default. The
  // OSD's bars and microphone status read these
  function sinkSettled() {
    return root.defaultSink?.ready === true && root.defaultSink === root._settledSink;
  }
  function sourceSettled() {
    return root.defaultSource?.ready === true && root.defaultSource === root._settledSource;
  }

  // The defaults, taken once they've bound and their own changes are
  // through
  property var _settledSink: null
  property var _settledSource: null
  function _settle() {
    root._settledSink = root.defaultSink?.ready ? root.defaultSink : null;
    root._settledSource = root.defaultSource?.ready ? root.defaultSource : null;
  }
  onDefaultSinkChanged: Qt.callLater(root._settle)
  onDefaultSourceChanged: Qt.callLater(root._settle)
  property Connections _sinkReady: Connections {
    target: root.defaultSink
    function onReadyChanged() {
      Qt.callLater(root._settle);
    }
  }
  property Connections _sourceReady: Connections {
    target: root.defaultSource
    function onReadyChanged() {
      Qt.callLater(root._settle);
    }
  }
  Component.onCompleted: root._settle()

  readonly property real sourceVolume: Pipewire.defaultAudioSource?.audio?.volume ?? 0
  readonly property bool sourceMuted: Pipewire.defaultAudioSource?.audio?.muted ?? false

  function toggleSourceMute() {
    toggleNodeMute(defaultSource);
  }

  function setSourceMuted(muted) {
    if (defaultSource?.audio)
      defaultSource.audio.muted = muted;
  }

  // The microphone on or off (keybind action toggleMicMute with its call):
  // enable unmutes it
  property IpcTarget _micIpc: IpcTarget {
    target: "microphone"

    function toggle(): void {
      root.toggleSourceMute();
    }

    function enable(): void {
      root.setSourceMuted(false);
    }

    function disable(): void {
      root.setSourceMuted(true);
    }

    // Whether it's on (unmuted)
    function status(): bool {
      return !root.sourceMuted;
    }
  }

  function setSourceVolume(value, max = 1.0) {
    setNodeVolume(defaultSource, value, max);
  }

  // -- Any node --
  function setNodeVolume(node, value, max = 1.0) {
    if (node?.audio)
      node.audio.volume = Math.max(0.0, Math.min(max, value));
  }

  function stepNodeVolume(node, delta, max = 1.0) {
    if (node?.audio)
      setNodeVolume(node, node.audio.volume + delta, max);
  }

  function toggleNodeMute(node) {
    if (node?.audio)
      node.audio.muted = !node.audio.muted;
  }

  // Several nodes at once (an app's streams, an OSD bar's matched streams)
  function setNodesVolume(nodes, value, max = 1.0) {
    (nodes ?? []).forEach(n => root.setNodeVolume(n, value, max));
  }

  function setNodesMuted(nodes, muted) {
    (nodes ?? []).forEach(n => {
      if (n?.audio)
        n.audio.muted = muted;
    });
  }

  // Playback streams (bound, with audio) for an OSD app bar: those whose binary,
  // application name or nickname contains one of `apps` (case-insensitive),
  // by app in the listed order, so the first listed app's stream comes
  // first. With `other`, the first stream no `excluded` entry matches
  // instead (by binary or application name).
  function matchStreams(apps, other, excluded) {
    const lower = list => (list ?? []).map(a => String(a).toLowerCase()).filter(a => a !== "");
    const wanted = lower(apps);
    if (!other && wanted.length === 0)
      return [];
    const streams = root._playbackStreams.filter(n => n.audio && n.ready).map(n => ({
          "node": n,
          "binary": n.properties["application.process.binary"]?.toLowerCase() ?? "",
          "name": n.properties["application.name"]?.toLowerCase() ?? "",
          "nickname": n.nickname?.toLowerCase() ?? ""
        }));
    if (other) {
      const skip = lower(excluded);
      const found = streams.find(s => (s.binary || s.name) && !skip.some(ex => s.binary.includes(ex) || s.name.includes(ex)));
      return found ? [found.node] : [];
    }
    const matched = [];
    for (const app of wanted) {
      for (const s of streams) {
        if (!matched.includes(s.node) && (s.binary.includes(app) || s.name.includes(app) || s.nickname.includes(app)))
          matched.push(s.node);
      }
    }
    return matched;
  }

  function setDefault(node) {
    if (!node)
      return;
    if (node.type === PwNodeType.AudioSource)
      Pipewire.preferredDefaultAudioSource = node;
    else
      Pipewire.preferredDefaultAudioSink = node;
  }

  function groupByApp(streams) {
    const groups = [];
    const byKey = {};
    for (const node of streams) {
      if (!node?.audio)
        continue;
      const props = node.properties || {};
      const name = appName(node);
      const key = name.toLowerCase();
      if (!byKey[key]) {
        byKey[key] = {
          "key": key,
          "name": name,
          "icon": props["application.icon-name"] || props["application.process.binary"] || "",
          "subtitle": props["media.name"] || "",
          "nodes": []
        };
        groups.push(byKey[key]);
      }
      byKey[key].nodes.push(node);
    }
    return groups;
  }

  // -- Device identity / name --

  // The physical device a sink or source is part of, as text: its sink
  // and source share it, and so does a Bluetooth headset across its
  // profiles (a profile switch replaces the node, not the device). A
  // virtual node (no device) is its own. "" for none, or one not bound
  // yet (its properties, so its device, come then)
  function deviceKey(node) {
    if (!node?.ready)
      return "";
    const props = node.properties || {};
    const key = props["device.id"] ?? props["api.bluez5.address"] ?? node.id;
    return key === undefined || key === null ? "" : String(key);
  }

  // A sink's or source's name to show ({ title, detail }:
  // AudioDevices.deviceName's, a kind's name translated)
  function deviceLabel(node) {
    if (!node)
      return {
        "title": "",
        "detail": ""
      };
    const props = node.properties || {};
    const name = AudioDevices.deviceName({
      "nick": props["node.nick"] ?? node.nickname ?? "",
      "description": node.description || node.name || "",
      "profile": props["device.profile.description"] ?? "",
      "bus": props["device.bus"] ?? "",
      "kind": root.deviceKind(node)
    });
    return {
      "title": name.translate ? I18n.tr(name.title) : name.title,
      "detail": name.detail
    };
  }

  // -- Device kind / icons --

  // headphones | headset | bluetooth | hdmi | webcam | speaker. Pipewire
  // doesn't expose the active port here, so headphones plugged into an
  // analog card's jack still read as speaker.
  function deviceKind(node) {
    if (!node)
      return "speaker";
    const props = node.properties || {};
    const formFactor = props["device.form-factor"] || "";
    const text = `${node.name || ""} ${node.description || ""}`.toLowerCase();
    if (formFactor === "headphone" || text.includes("headphone"))
      return "headphones";
    if (formFactor === "headset" || formFactor === "hands-free" || text.includes("headset"))
      return "headset";
    if (formFactor === "webcam")
      return "webcam";
    if (props["device.bus"] === "bluetooth" || text.startsWith("bluez"))
      return "bluetooth";
    if (formFactor === "tv" || formFactor === "monitor" || text.includes("hdmi") || text.includes("displayport"))
      return "hdmi";
    return "speaker";
  }

  // Output glyph for a device kind, reflecting mute and level
  function outputIcon(kind, muted, level) {
    switch (kind) {
    case "headphones":
    case "headset":
      return muted ? "headset_off" : (kind === "headset" ? "headset" : "headphones");
    case "bluetooth":
      return muted ? "volume_off" : "bluetooth_audio";
    case "hdmi":
      return muted ? "volume_off" : "monitor";
    }
    if (muted || level <= 0)
      return "volume_off";
    if (level < 0.34)
      return "volume_mute";
    if (level < 0.67)
      return "volume_down";
    return "volume_up";
  }

  // Input glyph for a device kind, reflecting mute
  function inputIcon(kind, muted) {
    if (muted)
      return "mic_off";
    switch (kind) {
    case "headset":
      return "headset";
    case "webcam":
      return "camera";
    }
    return "mic";
  }

  // -- Microphone use --

  // Active links into an app input stream from a non-stream node. Quickshell
  // only types exact media classes, so virtual sources (`Audio/Source/Virtual`,
  // e.g. EasyEffects or a loopback) read as Untracked; their media.class is
  // checked below once the tracker has bound them. A link group's state
  // reads Unlinked until the group is bound, so every candidate is tracked.
  readonly property var _inputGroups: Pipewire.linkGroups.values.filter(g => g && g.target?.type === PwNodeType.AudioInStream && g.source && !g.source.isStream)
  readonly property var _captureLinks: _inputGroups.filter(g => g.state === PwLinkState.Active)

  property PwObjectTracker captureTracker: PwObjectTracker {
    objects: root._inputGroups.concat(root._inputGroups.map(g => g.source))
  }

  // App input streams actively recording from a microphone. Recording a
  // sink monitor (visualisers, peak meters) doesn't count.
  readonly property var micCaptures: {
    const targets = [];
    for (const g of _captureLinks) {
      const isMic = g.source.type === PwNodeType.AudioSource || (g.source.properties?.["media.class"] ?? "").startsWith("Audio/Source");
      if (isMic && !targets.includes(g.target))
        targets.push(g.target);
    }
    return targets;
  }
  readonly property bool micInUse: micCaptures.length > 0

  // An app stream's name: its application, else its binary or node name
  function appName(node) {
    const props = node?.properties ?? {};
    return props["application.name"] || props["application.process.binary"] || node?.nickname || node?.name || I18n.tr("Unknown");
  }
}

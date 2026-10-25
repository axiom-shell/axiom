pragma Singleton

import QtQuick
import Quickshell.Services.Pipewire

import qs.config
import qs.services.core

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
  readonly property string name: Pipewire.defaultAudioSink?.name ?? ""
  readonly property string description: Pipewire.defaultAudioSink?.description ?? ""

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
  }

  // -- Default input --
  readonly property var defaultSource: Pipewire.defaultAudioSource

  readonly property real sourceVolume: Pipewire.defaultAudioSource?.audio?.volume ?? 0
  readonly property bool sourceMuted: Pipewire.defaultAudioSource?.audio?.muted ?? false

  function toggleSourceMute() {
    toggleNodeMute(defaultSource);
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
  readonly property var micUsers: [...new Set(micCaptures.map(n => appName(n)))]
  readonly property bool micInUse: micCaptures.length > 0

  // An app stream's name: its application, else its binary or node name
  function appName(node) {
    const props = node?.properties ?? {};
    return props["application.name"] || props["application.process.binary"] || node?.nickname || node?.name || I18n.tr("Unknown");
  }
}

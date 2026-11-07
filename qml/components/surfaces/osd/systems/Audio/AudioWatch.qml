pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.services.system
import qs.components.surfaces.osd.engine

// Audio's state for the OSD: each bar's level and mute (the default
// output's, the default input's, the streams an Other apps or App bar
// matches) and each device tile's device (AudioManager.deviceKey: "" while
// none is bound, a gap its definition bridges), name, Bluetooth address
// and mute. A bar counts a level only on the node it read before, its
// volume in (`node`, `streams`: resetBy). A change while the default device switches or binds isn't the
// user's (AudioManager.sinkSettled / sourceSettled)
OSDWatch {
  id: root

  readonly property var _sink: AudioManager.defaultSink
  readonly property var _source: AudioManager.defaultSource

  // A stream bar's streams (AudioManager.matchStreams: an App bar's apps,
  // or Other apps' first stream no App bar of any OSD matches): the first
  // one's level and mute, which it shows, the set of them (`streams`,
  // resetBy) and every one's level (`levels`: a change on any of them)
  function _streams(bar) {
    const nodes = AudioManager.matchStreams(bar.type === "app" ? bar.apps : [], bar.type === "other", bar.type === "other" ? OSDConfig.excludedApps : []);
    const first = nodes[0] ?? null;
    const found = first !== null && first.ready && first.audio;
    return {
      "level": found ? first.audio.volume : 0,
      "muted": !found || first.audio.muted,
      "streams": nodes.map(n => n.id).join(","),
      "levels": nodes.map(n => n.audio ? `${n.audio.volume}:${n.audio.muted}` : "").join(",")
    };
  }

  // The default device's node a bar reads, once its volume is in
  // (AudioManager.volumeKnown), else "": its device switching, or its
  // volume arriving, is resetBy, not a level
  function _node(node) {
    return AudioManager.volumeKnown(node) ? String(node.id) : "";
  }

  // A device tile's state from its node (null for none)
  function _device(node, output) {
    const value = AudioManager.deviceKey(node);
    const label = AudioManager.deviceLabel(node);
    const kind = AudioManager.deviceKind(node);
    return {
      "value": value,
      "address": value !== "" ? AudioManager.bluetoothAddress(node) : "",
      "name": value !== "" ? label.title : "",
      "detail": value !== "" ? label.detail : "",
      "icon": value === "" ? "" : output ? AudioManager.outputIcon(kind, false, 1) : AudioManager.inputIcon(kind, false),
      "muted": output ? AudioManager.muted : AudioManager.sourceMuted
    };
  }

  state: {
    const out = {
      "audio": root._device(root._sink, true),
      "microphone": root._device(root._source, false)
    };
    (root.options.bars ?? []).forEach((bar, i) => {
      if (bar.type === "master")
        out.master = {
          "level": AudioManager.volume,
          "muted": AudioManager.muted,
          "node": root._node(root._sink)
        };
      else if (bar.type === "microphone")
        out.micLevel = {
          "level": AudioManager.sourceVolume,
          "muted": AudioManager.sourceMuted,
          "node": root._node(root._source)
        };
      else
        out[bar.type === "app" ? "app:" + i : bar.type] = root._streams(bar);
    });
    return out;
  }

  // The default output's (master, its device) and input's (the
  // microphone's bar and device) only once bound and still the default;
  // a stream bar's always (its own set changing is resetBy)
  function settled(key, before, after) {
    if (key === "master" || key === "audio")
      return AudioManager.sinkSettled();
    if (key === "micLevel" || key === "microphone")
      return AudioManager.sourceSettled();
    return true;
  }
}

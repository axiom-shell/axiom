pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// Audio on the OSD: the volume bars (master, other apps, an app's, the
// microphone's), the output and input device tiles (a mute strikes its
// icon through) and the device-switch card ("Output", "Input", "Output and
// input" while the other tile holds the same device). AudioWatch reads
// PipeWire; a switch is judged here, settled or not, a mute and a level
// only while the device is settled
OSDSystem {
  id: root

  // A switch to another device is its card (never the first one
  // appearing, nor going: a gap); a mute strikes its icon through. A
  // switch counts as the new node binds (never settled), a mute and a
  // level only once it has
  onAdd: "none"
  onChange: "card"
  onRemove: "none"
  settledKinds: ["update", "level"]
  // A Bluetooth headset's profile switch replaces its node, often with
  // none between, and changes its icon, not its look
  keepThroughGap: true
  updateFields: []
  // A bar's level changes only on the node it read before, its volume in:
  // a stream bar's set of streams changing (one appearing with its
  // volume, going: Discord joining) or the System volume or Microphone
  // bar's node (the default device switching, binding, its volume
  // arriving) isn't its level changing
  resetBy: ["streams", "node"]
  // Its card takes in any of its own changes without one (a new device's
  // mute, its level arriving late)
  takesIn: "system"
  // A headset taking the output and the input: one card says both
  // I18n.tr("Output and input")
  groups: [
    {
      "keys": ["audio", "microphone"],
      "role": "Output and input"
    }
  ]

  // The bars in `bars` order (keys unique: the microphone's bar is
  // `micLevel`, its tile keeping `microphone`; an App bar is
  // `app:<its index>`), then the tiles in `tiles` order; a bar whose
  // showOsd is off never opens the OSD shut. A bar is drawn by its
  // `design`, design/VolumeBar.qml (Paths.osdDesignUrl), given its entry
  // (`bar`: its item in `bars`), which reads and sets PipeWire itself; a
  // tile's click mutes its device
  // I18n.tr("An app") I18n.tr("Input") I18n.tr("Microphone") I18n.tr("Other apps") I18n.tr("Output") I18n.tr("System volume")
  readonly property var _bars: ({
      "master": {
        "icon": "volume_up",
        "label": "System volume"
      },
      "other": {
        "icon": "music_note",
        "label": "Other apps"
      },
      "app": {
        "icon": "apps",
        "label": "An app"
      },
      "microphone": {
        "icon": "mic",
        "label": "Microphone"
      }
    })
  readonly property var _tiles: ({
      "audio": {
        "icon": "volume_up",
        "label": "Output",
        "action": "toggleMute"
      },
      "microphone": {
        "icon": "mic",
        "label": "Input",
        "action": "toggleMicMute"
      }
    })
  // A second bar of one kind (two System volume bars) is left out: keys
  // are unique
  exposes: (options.bars ?? []).map((bar, i) => ({
        "key": bar.type === "app" ? "app:" + i : bar.type === "microphone" ? "micLevel" : bar.type,
        "part": "bar",
        "icon": bar.icon || (_bars[bar.type]?.icon ?? "volume_up"),
        "label": _bars[bar.type]?.label ?? "",
        "mark": bar.type === "microphone" ? "microphone" : "audio",
        "opens": bar.showOsd !== false,
        "design": "VolumeBar",
        "bar": bar
      })).filter((e, i, all) => all.findIndex(o => o.key === e.key) === i).concat((options.tiles ?? ["audio", "microphone"]).map(key => Object.assign({
      "key": key,
      "part": "tile"
    }, _tiles[key])))

  // A device tile's state: { value (the device: AudioManager.deviceKey,
  // "" in a gap), address (its Bluetooth address, else ""), name, detail,
  // icon (its kind's, unmuted), muted }; hidden in a gap
  function tile(key, state) {
    const muted = state?.muted === true;
    const out = {
      "name": state?.name ?? "",
      "detail": state?.detail ?? "",
      "device": state?.value ?? "",
      "address": state?.address ?? "",
      "on": !muted,
      "slash": muted,
      "notable": muted,
      "hidden": !state?.value
    };
    // Unless the device has its own, the exposes' (the speaker, the mic)
    if (state?.icon)
      out.icon = state.icon;
    return out;
  }

  // A device's card: its name, what it's used for (the group's role when
  // the other tile holds it too) and its profile; a bar has none
  function card(change, state) {
    const key = change.key;
    if (key !== "audio" && key !== "microphone")
      return null;
    const s = state[key] ?? {};
    return {
      "title": s.name ?? "",
      "role": key === "audio" ? "Output" : "Input",
      "detail": s.detail ?? ""
    };
  }
}

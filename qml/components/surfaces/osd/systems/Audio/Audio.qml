pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// Audio on the OSD: the volume bars (master, other apps, an app's; the
// microphone's bar, whose key the port settles beside the microphone
// tile's), the output and input device tiles and the device-switch card. A
// stub until its port (`stub`: the timelines skip it); only what it exposes
// is declared
OSDSystem {
  readonly property bool stub: true

  // A Bluetooth headset's profile switch changes its icon, not its look
  updateFields: ["label"]

  // The bars in `bars` order (keys unique: the microphone's bar is
  // `micLevel`, its tile keeping `microphone`; an App bar is
  // `app:<its index>`), then the tiles in `tiles` order; a bar whose
  // showOsd is off never opens the OSD shut
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
        "label": "Output"
      },
      "microphone": {
        "icon": "mic",
        "label": "Input"
      }
    })
  exposes: (options.bars ?? []).map((bar, i) => ({
        "key": bar.type === "app" ? "app:" + i : bar.type === "microphone" ? "micLevel" : bar.type,
        "part": "bar",
        "icon": bar.icon || (_bars[bar.type]?.icon ?? "volume_up"),
        "label": _bars[bar.type]?.label ?? "",
        "mark": bar.type === "microphone" ? "microphone" : "audio",
        "opens": bar.showOsd !== false
      })).concat((options.tiles ?? ["audio", "microphone"]).map(key => Object.assign({
      "key": key,
      "part": "tile"
    }, _tiles[key])))
}

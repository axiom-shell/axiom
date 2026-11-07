pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// Camera, microphone and screen in use on the OSD: the apps capturing
// each (PrivacyWatch reads PipeWire and the camera's device users), a
// tile lit while some are. Anyone's change counts. A capture starting is
// its card, naming the apps; one of several stopping a "still" card
// naming those left; a call app dropping the camera or the microphone but
// keeping the other a "still" card of the one kept; the last one
// stopping the unlit icon. One app on the camera and the microphone is
// one card, and a card stays naming the apps it came with once they stop
// (a picker's preview stream)
OSDSystem {
  id: root

  model: "set"
  onAdd: "card"
  onRemove: "still"
  anyone: true
  ownerField: "app"
  // I18n.tr("Using the camera and microphone")
  groups: [
    {
      "keys": ["camera", "micUse"],
      "role": "Using the camera and microphone"
    }
  ]

  // In `kinds` order; each card made by the engine from its roles
  // I18n.tr("Camera") I18n.tr("Microphone in use") I18n.tr("Screen sharing")
  // I18n.tr("Using the camera") I18n.tr("Still using the camera") I18n.tr("Stopped using the camera")
  // I18n.tr("Using the microphone") I18n.tr("Still using the microphone") I18n.tr("Stopped using the microphone")
  // I18n.tr("Sharing the screen") I18n.tr("Still sharing the screen") I18n.tr("Stopped sharing the screen")
  readonly property var _kinds: ({
      "camera": {
        "icon": "videocam",
        "label": "Camera",
        "roles": {
          "add": "Using the camera",
          "still": "Still using the camera",
          "stopped": "Stopped using the camera"
        }
      },
      "micUse": {
        "icon": "record_voice_over",
        "label": "Microphone in use",
        "roles": {
          "add": "Using the microphone",
          "still": "Still using the microphone",
          "stopped": "Stopped using the microphone"
        }
      },
      "screenShare": {
        "icon": "screen_share",
        "label": "Screen sharing",
        "roles": {
          "add": "Sharing the screen",
          "still": "Still sharing the screen",
          "stopped": "Stopped sharing the screen"
        }
      }
    })
  exposes: (options.kinds ?? ["camera", "micUse", "screenShare"]).filter(key => _kinds[key]).map(key => Object.assign({
      "key": key,
      "part": "tile"
    }, _kinds[key]))

  // state: { members: [{ id (the stream's node), app (its app's name) }] };
  // lit and unusual while any capture, never hidden
  function tile(key, state) {
    const apps = [...new Set((state?.members ?? []).map(m => m.app))];
    return {
      "apps": apps,
      "name": apps.join(", "),
      "on": apps.length > 0,
      "notable": apps.length > 0
    };
  }
}

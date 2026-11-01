pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.services.session
import qs.services.system
import qs.components.methods

// One status or media item of an OSD (OSDContent builds one per item):
// watches what it shows and reports the user's changes as a line to show,
// never a first reading or a device appearing. Only the watcher of its
// type is built, so an OSD without a type never wakes its service.
// Changes in the first moments are services settling (the LEDs' first
// reading, PipeWire binding, UPower and D-Bus answering), not the user.
Loader {
  id: root

  // Its item ({ type, icon, … }, see OSD.items in the schema)
  required property var entry

  // A change to show: { type, icon, text }; the media item's has only its
  // type, the card reading the track itself
  signal fired(var line)

  // Reports a state through OSDItems.status, `icon` the service's own
  // (the device's), the item's icon winning
  function _report(state, icon) {
    if (!root._armed)
      return;
    const s = OSDItems.status(root.entry.type, state);
    // The texts OSDItems.status gives, translated here:
    // I18n.tr("Caps Lock on") I18n.tr("Caps Lock off") I18n.tr("Num Lock on") I18n.tr("Num Lock off")
    // I18n.tr("Scroll Lock on") I18n.tr("Scroll Lock off") I18n.tr("Microphone on") I18n.tr("Microphone off")
    // I18n.tr("Power saver") I18n.tr("Balanced") I18n.tr("Performance")
    // I18n.tr("Charger plugged in") I18n.tr("On battery")
    // I18n.tr("Caffeine on") I18n.tr("Caffeine off") I18n.tr("Do not disturb on") I18n.tr("Do not disturb off")
    // I18n.tr("Night light on") I18n.tr("Night light off") I18n.tr("Wi-Fi on") I18n.tr("Wi-Fi off")
    // I18n.tr("Bluetooth on") I18n.tr("Bluetooth off") I18n.tr("Airplane mode on") I18n.tr("Airplane mode off")
    root.fired({
      "type": root.entry.type,
      "icon": root.entry.icon || icon || s.icon,
      "text": s.value !== undefined ? s.value : I18n.tr(s.text)
    });
  }

  // Reports what it shows now, as a change would (the settings page's
  // Show button, on an OSD with no levels)
  function preview() {
    const type = root.entry.type;
    if (type === "media") {
      root.fired({
        "type": "media"
      });
      return;
    }
    const key = ["caps", "num", "scroll"].find(k => root.entry[k] === true) ?? "caps";
    const lit = {
      "caps": LockKeysManager.capsLock,
      "num": LockKeysManager.numLock,
      "scroll": LockKeysManager.scrollLock
    };
    const states = {
      "lockKeys": () => ({
            "key": key,
            "on": lit[key]
          }),
      "keyboardLayout": () => ({
            "name": KeyboardLayoutManager.keymapName || String(KeyboardLayoutManager.layouts[KeyboardLayoutManager.layoutIndex] ?? "").toUpperCase()
          }),
      "micMute": () => ({
            "muted": AudioManager.sourceMuted
          }),
      "outputDevice": () => ({
            "name": AudioManager.description || AudioManager.name
          }),
      "powerProfile": () => ({
            "profile": BatteryManager.profile
          }),
      "caffeine": () => ({
            "on": IdleManager.caffeine
          }),
      "dnd": () => ({
            "on": NotificationManager.dnd
          }),
      "nightLight": () => ({
            "on": NightLightManager.active
          }),
      "wifi": () => ({
            "on": NetworkingManager.wifiEnabled
          }),
      "bluetooth": () => ({
            "on": BluetoothManager.enabled
          }),
      "airplane": () => ({
            "on": NetworkingManager.airplane
          }),
      "charger": () => ({
            "plugged": !BatteryManager.onBattery
          }),
      "message": () => ({
            "icon": root.entry.icon || "chat",
            "text": I18n.tr("A message")
          })
    };
    const state = states[type];
    if (!state)
      return;
    const was = root._armed;
    root._armed = true;
    root._report(state(), "");
    root._armed = was;
  }

  property bool _armed: false
  readonly property Timer _settle: Timer {
    // behaviour timing: how long services take to report their state
    interval: 1500
    running: true
    onTriggered: root._armed = true
  }

  readonly property var _watchers: ({
      "lockKeys": lockKeys,
      "keyboardLayout": keyboardLayout,
      "micMute": micMute,
      "outputDevice": outputDevice,
      "powerProfile": powerProfile,
      "caffeine": caffeine,
      "dnd": dnd,
      "nightLight": nightLight,
      "wifi": wifi,
      "bluetooth": bluetooth,
      "airplane": airplane,
      "charger": charger,
      "media": media,
      "message": null
    })
  sourceComponent: root._watchers[root.entry.type] ?? null

  Component {
    id: lockKeys

    Item {
      id: keys
      property var _last: null

      function _check() {
        const now = {
          "available": LockKeysManager.available,
          "caps": LockKeysManager.capsLock,
          "num": LockKeysManager.numLock,
          "scroll": LockKeysManager.scrollLock
        };
        const change = OSDItems.lockKeyChange(keys._last, now, root.entry);
        keys._last = now;
        if (change)
          root._report(change, "");
      }

      // The LEDs are read only while held
      Component.onCompleted: LockKeysManager.acquire(keys)
      Component.onDestruction: LockKeysManager.release(keys)

      // One state sets several keys at once: compare once it's all in
      Connections {
        target: LockKeysManager
        function onAvailableChanged() {
          Qt.callLater(keys._check);
        }
        function onCapsLockChanged() {
          Qt.callLater(keys._check);
        }
        function onNumLockChanged() {
          Qt.callLater(keys._check);
        }
        function onScrollLockChanged() {
          Qt.callLater(keys._check);
        }
      }
    }
  }

  Component {
    id: keyboardLayout

    Item {
      id: layout
      property var _last: null

      function _check() {
        const now = {
          "layouts": KeyboardLayoutManager.layouts,
          "index": KeyboardLayoutManager.layoutIndex
        };
        const switched = OSDItems.layoutSwitched(layout._last, now);
        layout._last = now;
        if (switched)
          root._report({
            "name": KeyboardLayoutManager.keymapName || String(now.layouts[now.index] ?? "").toUpperCase()
          }, "");
      }

      Component.onCompleted: layout._check()

      Connections {
        target: KeyboardLayoutManager
        function onLayoutIndexChanged() {
          Qt.callLater(layout._check);
        }
        function onLayoutsChanged() {
          Qt.callLater(layout._check);
        }
      }
    }
  }

  Component {
    id: micMute

    Item {
      id: mic
      // A change as the input device switches (or binds) is the device's
      property var _source: null

      Component.onCompleted: mic._source = AudioManager.defaultSource

      Connections {
        target: AudioManager
        function onSourceMutedChanged() {
          if (AudioManager.defaultSource === mic._source && mic._source !== null)
            root._report({
              "muted": AudioManager.sourceMuted
            }, AudioManager.inputIcon(AudioManager.deviceKind(AudioManager.defaultSource), AudioManager.sourceMuted));
          mic._source = AudioManager.defaultSource;
        }
        function onDefaultSourceChanged() {
          mic._source = AudioManager.defaultSource;
        }
      }
    }
  }

  Component {
    id: outputDevice

    Item {
      id: output
      property var _sink: null

      // Named once the new device has bound (its description arrives then)
      function _show() {
        const sink = AudioManager.defaultSink;
        if (sink)
          root._report({
            "name": AudioManager.description || AudioManager.name
          }, AudioManager.outputIcon(AudioManager.deviceKind(sink), false, 1));
      }

      Component.onCompleted: output._sink = AudioManager.defaultSink

      Connections {
        target: AudioManager
        function onDefaultSinkChanged() {
          // From one device to another: not the first one binding, nor the
          // last going away
          if (output._sink !== null && AudioManager.defaultSink !== null && AudioManager.defaultSink !== output._sink)
            Qt.callLater(output._show);
          output._sink = AudioManager.defaultSink;
        }
      }
    }
  }

  Component {
    id: powerProfile

    Item {
      id: profile
      property string _last: ""

      Component.onCompleted: profile._last = BatteryManager.profile

      Connections {
        target: BatteryManager
        function onProfileChanged() {
          if (profile._last !== "" && BatteryManager.profile !== "")
            root._report({
              "profile": BatteryManager.profile
            }, "");
          profile._last = BatteryManager.profile;
        }
      }
    }
  }

  Component {
    id: caffeine

    Item {
      Connections {
        target: IdleManager
        function onCaffeineChanged() {
          root._report({
            "on": IdleManager.caffeine
          }, "");
        }
      }
    }
  }

  Component {
    id: dnd

    Item {
      Connections {
        target: NotificationManager
        function onDndChanged() {
          root._report({
            "on": NotificationManager.dnd
          }, "");
        }
      }
    }
  }

  Component {
    id: nightLight

    Item {
      Connections {
        target: NightLightManager
        function onActiveChanged() {
          root._report({
            "on": NightLightManager.active
          }, "");
        }
      }
    }
  }

  Component {
    id: wifi

    Item {
      Connections {
        target: NetworkingManager
        function onWifiEnabledChanged() {
          if (NetworkingManager.available)
            root._report({
              "on": NetworkingManager.wifiEnabled
            }, "");
        }
      }
    }
  }

  Component {
    id: bluetooth

    Item {
      Connections {
        target: BluetoothManager
        function onEnabledChanged() {
          if (BluetoothManager.available)
            root._report({
              "on": BluetoothManager.enabled
            }, "");
        }
      }
    }
  }

  Component {
    id: airplane

    Item {
      Connections {
        target: NetworkingManager
        function onAirplaneChanged() {
          root._report({
            "on": NetworkingManager.airplane
          }, "");
        }
      }
    }
  }

  Component {
    id: charger

    Item {
      Connections {
        target: BatteryManager
        function onOnBatteryChanged() {
          if (BatteryManager.isAvailable)
            root._report({
              "plugged": !BatteryManager.onBattery
            }, "");
        }
      }
    }
  }

  Component {
    id: media

    Item {
      id: track
      // A new track: its title changing, on the same player or another
      // (a player appearing with one is a new track too)
      function _fire() {
        if (root._armed && MediaManager.hasActivePlayer && MediaManager.trackTitle !== "")
          root.fired({
            "type": "media"
          });
      }

      Connections {
        target: MediaManager
        function onTrackTitleChanged() {
          if (root.entry.onTrackChange)
            Qt.callLater(track._fire);
        }
        function onIsPlayingChanged() {
          if (root.entry.onPlayPause)
            Qt.callLater(track._fire);
        }
      }
    }
  }
}

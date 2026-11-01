pragma ComponentBehavior: Bound
import QtQuick

import qs.services.session
import qs.services.system
import qs.components.methods

// One status type of an OSD, or its now playing card (OSDContent builds
// one per status and one for the card): its state now, as a tile
// (OSDItems.tile), and the user's changes to it, never a first reading or
// a device appearing. Only the watcher of its type is built, so an OSD
// without a type never wakes its service. Changes in the first moments
// are services settling (the LEDs' first reading, PipeWire binding, UPower
// and D-Bus answering), not the user.
Loader {
  id: root

  // A status type (OSD.statuses.items in the schema), or "media"
  required property string type
  // The OSD's `media` ({ enabled, onTrackChange, onPlayPause }), for "media"
  property var mediaOptions: ({})

  // The user changed it; `switched`: an audio device switched (its card),
  // not its mute
  signal fired(bool switched)

  // What it shows now (OSDItems.tile; a message's is OSDContent's)
  readonly property var tile: OSDItems.tile(root.type, root._state())

  // A click on its icon can change it (toggle)
  readonly property bool canToggle: ["keyboardLayout", "audio", "microphone", "powerProfile", "caffeine", "dnd", "nightLight", "wifi", "bluetooth", "airplane"].includes(root.type)

  // Flips it, as its own control would (the layout to the next, the
  // profile between power saver and the rest)
  function toggle() {
    switch (root.type) {
    case "keyboardLayout":
      KeyboardLayoutManager.cycle("next");
      break;
    case "audio":
      AudioManager.toggleMute();
      break;
    case "microphone":
      AudioManager.toggleSourceMute();
      break;
    case "powerProfile":
      BatteryManager.setPowerSaver(BatteryManager.profile !== "powerSaver");
      break;
    case "caffeine":
      IdleManager.toggle();
      break;
    case "dnd":
      NotificationManager.toggleDnd();
      break;
    case "nightLight":
      NightLightManager.toggle();
      break;
    case "wifi":
      NetworkingManager.toggleWifi();
      break;
    case "bluetooth":
      BluetoothManager.toggleEnabled();
      break;
    case "airplane":
      NetworkingManager.setAirplane(!NetworkingManager.airplane);
      break;
    }
  }

  // Its state now, for OSDItems.tile: reads only its own type's service
  function _state() {
    switch (root.type) {
    case "capsLock":
      return {
        "available": LockKeysManager.available,
        "on": LockKeysManager.capsLock
      };
    case "numLock":
      return {
        "available": LockKeysManager.available,
        "on": LockKeysManager.numLock
      };
    case "scrollLock":
      return {
        "available": LockKeysManager.available,
        "on": LockKeysManager.scrollLock
      };
    case "keyboardLayout":
      return {
        "layouts": KeyboardLayoutManager.layouts,
        "index": KeyboardLayoutManager.layoutIndex
      };
    case "audio":
    case "microphone":
      {
        const output = root.type === "audio";
        const node = output ? AudioManager.defaultSink : AudioManager.defaultSource;
        const kind = AudioManager.deviceKind(node);
        const label = AudioManager.deviceLabel(node);
        return {
          "name": label.title,
          "detail": label.detail,
          "device": AudioManager.deviceKey(node),
          "muted": output ? AudioManager.muted : AudioManager.sourceMuted,
          "icon": output ? AudioManager.outputIcon(kind, false, 1) : AudioManager.inputIcon(kind, false)
        };
      }
    case "powerProfile":
      return {
        "profile": BatteryManager.profile
      };
    case "caffeine":
      return {
        "on": IdleManager.caffeine
      };
    case "dnd":
      return {
        "on": NotificationManager.dnd
      };
    case "nightLight":
      return {
        "on": NightLightManager.active
      };
    case "wifi":
      return {
        "available": NetworkingManager.available,
        "on": NetworkingManager.wifiEnabled
      };
    case "bluetooth":
      return {
        "available": BluetoothManager.available,
        "on": BluetoothManager.enabled
      };
    case "airplane":
      return {
        "on": NetworkingManager.airplane
      };
    case "charger":
      return {
        "available": BatteryManager.isAvailable,
        "plugged": !BatteryManager.onBattery
      };
    }
    return {};
  }

  function _report(switched) {
    if (root._armed)
      root.fired(switched === true);
  }

  property bool _armed: false
  readonly property Timer _settle: Timer {
    // behaviour timing: how long services take to report their state
    interval: 1500
    running: true
    onTriggered: root._armed = true
  }

  readonly property var _watchers: ({
      "capsLock": lockKeys,
      "numLock": lockKeys,
      "scrollLock": lockKeys,
      "keyboardLayout": keyboardLayout,
      "audio": audioDevice,
      "microphone": audioDevice,
      "powerProfile": powerProfile,
      "caffeine": caffeine,
      "dnd": dnd,
      "nightLight": nightLight,
      "wifi": wifi,
      "bluetooth": bluetooth,
      "airplane": airplane,
      "charger": charger,
      "media": media
    })
  sourceComponent: root._watchers[root.type] ?? null

  Component {
    id: lockKeys

    Item {
      id: keys
      readonly property string key: OSDItems.lockKeys[root.type] ?? ""
      property var _last: null

      function _check() {
        const now = {
          "available": LockKeysManager.available,
          "caps": LockKeysManager.capsLock,
          "num": LockKeysManager.numLock,
          "scroll": LockKeysManager.scrollLock
        };
        const changed = OSDItems.lockKeyChanged(keys._last, now, keys.key);
        keys._last = now;
        if (changed)
          root._report();
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
          root._report();
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
    id: audioDevice

    Item {
      id: device
      readonly property bool output: root.type === "audio"
      readonly property var node: device.output ? AudioManager.defaultSink : AudioManager.defaultSource
      // The physical device last in use (AudioManager.deviceKey), kept
      // through a gap with none: a Bluetooth headset switching profile
      // replaces its node (often with none between), not the device
      property string _last: ""

      // A switch from one device to another: not the first one appearing
      function _check() {
        const key = AudioManager.deviceKey(device.node);
        if (key === "")
          return;
        if (device._last !== "" && key !== device._last)
          root._report(true);
        device._last = key;
      }

      // A mute: a change as the device switches or binds is the device's
      function _muteChanged() {
        if (device.output ? AudioManager.sinkSettled() : AudioManager.sourceSettled())
          root._report(false);
      }

      Component.onCompleted: device._check()

      // Judged once the new node has bound
      onNodeChanged: Qt.callLater(device._check)

      Connections {
        target: device.node
        function onReadyChanged() {
          Qt.callLater(device._check);
        }
      }

      Connections {
        target: AudioManager
        function onMutedChanged() {
          if (device.output)
            device._muteChanged();
        }
        function onSourceMutedChanged() {
          if (!device.output)
            device._muteChanged();
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
            root._report();
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
          root._report();
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
          root._report();
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
          root._report();
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
            root._report();
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
            root._report();
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
          root._report();
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
            root._report();
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
        if (MediaManager.hasActivePlayer && MediaManager.trackTitle !== "")
          root._report();
      }

      Connections {
        target: MediaManager
        function onTrackTitleChanged() {
          if (root.mediaOptions.onTrackChange)
            Qt.callLater(track._fire);
        }
        function onIsPlayingChanged() {
          if (root.mediaOptions.onPlayPause)
            Qt.callLater(track._fire);
        }
      }
    }
  }
}

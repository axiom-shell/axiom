pragma ComponentBehavior: Bound
import QtQuick

import qs.services.session
import qs.services.compositor
import qs.services.system
import qs.services.apps
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

  // A status type (an OSD's statuses.items, or a card-only one from its
  // cards.items), or "media"
  required property string type
  // The OSD's `cards` ({ onTrackChange, onPlayPause, … }), for "media"
  property var mediaOptions: ({})

  // It changed: the user's doing, or (a VPN, a capture, Wi-Fi joining a
  // network, the charger, a drive, the battery, a monitor) anything's.
  // `card`: shown as its card (a type in OSDItems.cardTypes: an audio
  // device switched, not its mute; a VPN came up; an app started a
  // capture; the charger was plugged in; Wi-Fi joined a network;
  // something done to a drive; the battery dropped to low or critical; a
  // monitor came or went; a screenshot was taken)
  signal fired(bool card)

  // What it shows now (OSDItems.tile; a message's is OSDContent's)
  readonly property var tile: OSDItems.tile(root.type, root._state())

  // A click on its icon can change it (toggle)
  // (a recording only stops)
  readonly property bool canToggle: root.type === "recording" ? ScreenshotManager.recording : ["keyboardLayout", "audio", "microphone", "powerProfile", "caffeine", "dnd", "nightLight", "wifi", "bluetooth", "airplane", "vpn"].includes(root.type)

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
    case "vpn":
      VpnManager.toggleLast();
      break;
    case "recording":
      if (ScreenshotManager.recording)
        ScreenshotManager.stopRecording();
      break;
    }
  }

  // A click on its card (OSDItems.clickableCards): a drive's opens or
  // unlocks it, a screenshot's opens the picture
  function activate() {
    switch (root.type) {
    case "drive":
      DrivesManager.activate(DrivesManager.lastEvent);
      break;
    case "screenshot":
      ScreenshotManager.open(ScreenshotManager.lastShot?.path ?? "");
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
        "on": NetworkingManager.wifiEnabled,
        "network": NetworkingManager.wifiDevice?.connected ? (NetworkingManager.activeNetwork?.name ?? "") : "",
        "signal": Math.round((NetworkingManager.activeNetwork?.signalStrength ?? 0) * 100)
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
        "plugged": !BatteryManager.onBattery,
        "percent": BatteryManager.percentage,
        "charging": BatteryManager.isCharging,
        "full": BatteryManager.isFull,
        "untilFull": BatteryManager.timeToFull
      };
    case "vpn":
      return {
        // Hidden with no VPN (NetworkManager running isn't one)
        "available": VpnManager.rows.length > 0,
        "on": VpnManager.anyActive,
        "name": VpnManager.activeRows.map(r => r.name).join(", "),
        "address": VpnManager.primary?.ipv4 ?? ""
      };
    case "drive":
      return {
        "available": DrivesManager.available,
        "count": DrivesManager.count,
        "event": DrivesManager.lastEvent
      };
    case "battery":
      return {
        "available": BatteryManager.isAvailable,
        "level": BatteryManager.level,
        "percent": BatteryManager.percentage,
        "timeLeft": BatteryManager.timeRemaining
      };
    case "monitor":
      return {
        "event": MonitorManager.lastEvent
      };
    case "screenshot":
      return {
        "event": ScreenshotManager.lastShot
      };
    case "recording":
      return {
        "available": ScreenshotManager.hasRecorder,
        "on": ScreenshotManager.recording
      };
    case "camera":
    case "screenShare":
    case "micUse":
      return {
        "apps": root._apps(root._captures()),
        "last": root._lastApps
      };
    }
    return {};
  }

  // The streams capturing what this type watches (camera, screenShare,
  // micUse)
  function _captures() {
    switch (root.type) {
    case "camera":
      return PrivacyManager.cameraCaptures;
    case "screenShare":
      return PrivacyManager.screenCaptures;
    case "micUse":
      return AudioManager.micCaptures;
    }
    return [];
  }

  // The apps last seen capturing (a capture's watcher keeps them): its
  // card still names them once the capture stops
  property var _lastApps: []

  // The apps' names of capturing streams, once each
  function _apps(nodes) {
    return [...new Set(nodes.map(n => AudioManager.appName(n)))];
  }

  // A card only for a type that has one
  function _report(card) {
    if (root._armed)
      root.fired(card === true && OSDItems.cardTypes.includes(root.type));
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
      "vpn": vpn,
      "drive": drive,
      "battery": battery,
      "monitor": monitor,
      "screenshot": screenshot,
      "recording": recording,
      "camera": capture,
      "screenShare": capture,
      "micUse": capture,
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
      id: radio
      // The Wi-Fi device has joined a network: its own state, steadier
      // than the scanned list (which can drop the network joined for a
      // moment as it's rebuilt). Leaving one for another goes through
      // disconnected
      readonly property bool joined: NetworkingManager.wifiDevice?.connected === true

      // The network's card as one is joined (its name fills in as the
      // list catches up)
      onJoinedChanged: {
        if (radio.joined)
          root._report(true);
      }

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
        // Plugged in: its card (the level, charging, the time to full)
        function onOnBatteryChanged() {
          if (BatteryManager.isAvailable)
            root._report(!BatteryManager.onBattery);
        }
      }
    }
  }

  Component {
    id: vpn

    Item {
      id: tunnels
      // Each VPN's last settled state (OSDItems.vpnStep)
      property var _last: null

      function _check() {
        const now = {};
        for (const row of VpnManager.rows)
          now[row.id] = row.state;
        const step = OSDItems.vpnStep(tunnels._last, now);
        tunnels._last = step.last;
        if (step.changed)
          root._report(step.up);
      }

      // Lists Tailscale among the VPNs (polled while held, as for the Vpn
      // widget)
      Component.onCompleted: {
        VpnManager.acquire(tunnels);
        tunnels._check();
      }
      Component.onDestruction: VpnManager.release(tunnels)

      Connections {
        target: VpnManager
        function onRowsChanged() {
          Qt.callLater(tunnels._check);
        }
      }
    }
  }

  Component {
    id: drive

    Item {
      Connections {
        target: DrivesManager
        // Something done to a drive (DrivesManager.lastEvent; never a
        // drive there at login): its card
        function onLastEventChanged() {
          if (DrivesManager.lastEvent)
            root._report(true);
        }
      }
    }
  }

  Component {
    id: battery

    Item {
      Connections {
        target: BatteryManager
        // The battery dropped to low or critical (levelEvent, set only
        // when an OSD shows `battery`): its card
        function onLevelEventChanged() {
          if (BatteryManager.levelEvent)
            root._report(true);
        }
      }
    }
  }

  Component {
    id: monitor

    Item {
      Connections {
        target: MonitorManager
        // A monitor connected or removed (lastEvent, never one there at
        // the start): its card
        function onLastEventChanged() {
          if (MonitorManager.lastEvent)
            root._report(true);
        }
      }
    }
  }

  Component {
    id: screenshot

    Item {
      Connections {
        target: ScreenshotManager
        // A screenshot taken (lastShot): its card
        function onLastShotChanged() {
          if (ScreenshotManager.lastShot)
            root._report(true);
        }
      }
    }
  }

  Component {
    id: recording

    Item {
      Connections {
        target: ScreenshotManager
        function onRecordingChanged() {
          root._report();
        }
      }
    }
  }

  Component {
    id: capture

    Item {
      id: apps
      // By node id: an app's name may come in after its stream starts
      // (its properties bind later), which isn't another app starting
      readonly property var now: root._captures().map(n => n.id)
      // Their names, as they bind
      readonly property var names: root._apps(root._captures())
      property var _last: []

      onNamesChanged: {
        if (apps.names.length > 0)
          root._lastApps = apps.names;
      }

      function _check() {
        const change = OSDItems.captureChange(apps._last, apps.now);
        apps._last = apps.now;
        if (change !== "")
          root._report(change === "started");
      }

      Component.onCompleted: {
        apps._last = apps.now;
        root._lastApps = apps.names;
      }
      // Links bind one by one: judged once they're in
      onNowChanged: Qt.callLater(apps._check)
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

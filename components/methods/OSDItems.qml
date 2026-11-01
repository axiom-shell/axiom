pragma Singleton
import QtQuick

// What an OSD's status icons show (the OSD's surfaces/osd): which lock
// key or layout change is the user's, each status's tile from its state,
// which tiles the row shows, and which change may take the highlight
// from the one shown.
QtObject {
  id: root

  // The LED each lock key status reads (LockKeysManager's names)
  readonly property var lockKeys: ({
      "capsLock": "caps",
      "numLock": "num",
      "scrollLock": "scroll"
    })

  // Whether a lock key (`key`: "caps" | "num" | "scroll") changed between
  // two states ({ available, caps, num, scroll }); never across an
  // unavailable one (the first reading, or the LEDs gone: not the user)
  function lockKeyChanged(before, after, key) {
    if (!before || !after || !before.available || !after.available)
      return false;
    return before[key] !== after[key];
  }

  // Whether the layout switched between two keyboard states ({ layouts,
  // index }): the same list of more than one layout, another index. A
  // changed list is a config reload, not a switch
  function layoutSwitched(before, after) {
    if (!before || !after || after.layouts.length < 2)
      return false;
    return JSON.stringify(before.layouts) === JSON.stringify(after.layouts) && before.index !== after.index;
  }

  // A status's tile from its state:
  //   { icon, label, tone, on, slash, notable, hidden }
  // (an audio device's also { name, detail, device }; a message's
  // { name, detail }, its card's lines)
  // `icon` always the base one ("wifi", never "wifi_off": off is told by
  // `on`, a mute by `slash`), `label` short text drawn instead of the icon
  // (a layout's code), `tone` "warning" for a message saying why something
  // couldn't run (else ""), `on` lit (a toggle on, the microphone live),
  // `slash` muted (audio, microphone: drawn struck through), `notable` out
  // of the ordinary (the row's "What's unusual"), `hidden`
  // nothing to show (no Wi-Fi, one layout). States:
  //   capsLock / numLock / scrollLock { available, on },
  //   keyboardLayout { layouts, index },
  //   audio / microphone { muted, name, detail, icon (the device's,
  //   unmuted), device (its identity, deviceKey's) }, powerProfile { profile: "powerSaver" |
  //   "balanced" | "performance" | "" }, charger { available, plugged,
  //   percent, charging, full, untilFull (the time left to full, as
  //   shown) }, wifi { available, on, network (the one joined, else ""),
  //   signal (0-100) },
  //   message { icon, text, detail, tone }, vpn { available, on, name (the VPNs up),
  //   address (the first one's) }, camera / screenShare / micUse { apps
  //   (the app names using it), last (the ones last seen using it: a
  //   card outlives a capture that stops at once) }, drive { available
  //   (udisks2 answers), count (drives plugged in), event (the last one:
  //   DrivesManager.lastEvent, { kind: "added" | "mounted" | "ejected",
  //   name, mountPoint }, or null) }, every other
  //   type (recording too) { available, on }
  function tile(type, state) {
    const t = {
      "icon": "",
      "label": "",
      "on": false,
      "slash": false,
      "tone": "",
      "notable": false,
      "hidden": false
    };
    const s = state ?? {};
    switch (type) {
    case "capsLock":
    case "numLock":
    case "scrollLock":
      {
        const icons = {
          "capsLock": "keyboard_capslock",
          "numLock": "dialpad",
          "scrollLock": "swap_vert"
        };
        // Num Lock is on on most desktops and missing on most laptops: it
        // shows as it changes, never as unusual
        return Object.assign(t, {
          "icon": icons[type],
          "on": s.on === true,
          "notable": s.on === true && type !== "numLock",
          "hidden": s.available !== true
        });
      }
    case "keyboardLayout":
      {
        const layouts = s.layouts ?? [];
        return Object.assign(t, {
          "icon": "keyboard",
          "label": String(layouts[s.index] ?? "").toUpperCase(),
          "on": true,
          "notable": (s.index ?? 0) > 0,
          "hidden": layouts.length < 2
        });
      }
    case "audio":
    case "microphone":
      return Object.assign(t, {
        "icon": s.icon || (type === "audio" ? "volume_up" : "mic"),
        "name": s.name ?? "",
        "detail": s.detail ?? "",
        "device": s.device ?? "",
        "on": s.muted !== true,
        "slash": s.muted === true,
        "notable": s.muted === true,
        "hidden": !s.device
      });
    case "powerProfile":
      {
        const icons = {
          "powerSaver": "energy_savings_leaf",
          "balanced": "balance",
          "performance": "speed"
        };
        return Object.assign(t, {
          "icon": icons[s.profile] ?? icons.balanced,
          "on": s.profile !== "balanced",
          "notable": s.profile === "powerSaver" || s.profile === "performance",
          "hidden": !s.profile
        });
      }
    case "charger":
      return Object.assign(t, {
        "icon": "power",
        "name": s.plugged === true && s.percent !== undefined ? `${s.percent}%` : "",
        "percent": s.percent ?? 0,
        "charging": s.charging === true,
        "full": s.full === true,
        "untilFull": s.untilFull ?? "",
        "on": s.plugged === true,
        "notable": s.available === true && s.plugged === false,
        "hidden": s.available !== true
      });
    case "vpn":
      return Object.assign(t, {
        "icon": "vpn_key",
        "name": s.on === true ? (s.name ?? "") : "",
        "address": s.on === true ? (s.address ?? "") : "",
        "on": s.on === true,
        "notable": s.on === true,
        "hidden": s.available !== true
      });
    case "drive":
      {
        const e = s.event ?? null;
        return Object.assign(t, {
          "icon": "usb",
          "name": e?.name ?? "",
          "event": e?.kind ?? "",
          "mountPoint": e?.mountPoint ?? "",
          "on": (s.count ?? 0) > 0,
          "hidden": s.available !== true || (s.count ?? 0) === 0
        });
      }
    case "camera":
    case "screenShare":
    case "micUse":
      {
        const apps = s.apps ?? [];
        const icons = {
          "camera": "videocam",
          "screenShare": "screen_share",
          "micUse": "record_voice_over"
        };
        return Object.assign(t, {
          "icon": icons[type],
          "apps": apps,
          "last": s.last ?? [],
          "name": apps.join(", "),
          "on": apps.length > 0,
          "notable": apps.length > 0
        });
      }
    case "message":
      return Object.assign(t, {
        "icon": s.icon || "chat",
        "name": s.text ?? "",
        "detail": s.detail ?? "",
        "tone": s.tone ?? "",
        "on": true,
        "hidden": !s.text
      });
    }
    // [icon, notable when on (else when off; null: never)]
    const toggles = {
      "caffeine": ["coffee", true],
      "dnd": ["do_not_disturb_on", true],
      "nightLight": ["nightlight", true],
      "wifi": ["wifi", false],
      "bluetooth": ["bluetooth", null],
      "airplane": ["airplanemode_active", true],
      "recording": ["screen_record", true]
    };
    const toggle = toggles[type];
    if (!toggle)
      return Object.assign(t, {
        "hidden": true
      });
    const on = s.on === true;
    Object.assign(t, {
      "icon": toggle[0],
      "on": on,
      "notable": toggle[1] !== null && on === toggle[1],
      "hidden": s.available === false
    });
    // The network joined names Wi-Fi (its tooltip, its card)
    if (type === "wifi" && on && s.network)
      Object.assign(t, {
        "name": s.network,
        "signal": s.signal ?? 0
      });
    return t;
  }

  // The statuses the row shows, in the OSD's order: of `types` (its
  // statuses), by `mode` ("notable" | "all" | "changed") over `tiles` (by
  // type, tile()'s), `changed` (the type that just changed, or "") always
  // among them. A hidden tile shows only as it changes; a message never
  // (it shows as its card).
  function rowTypes(types, tiles, mode, changed) {
    return types.filter(type => {
      if (type === "message")
        return false;
      if (type === changed)
        return true;
      const t = tiles[type];
      if (!t || t.hidden)
        return false;
      return mode === "all" || (mode === "notable" && t.notable);
    });
  }

  // A VPN going up or down, from `last` (each VPN's last settled state,
  // `{ id: "on" | "off" }`, what this returned before; null at first) and
  // `now` (`{ id: state }`, a VpnManager row's state by its id):
  // { changed, up, last }. Changed: one known before is settled again in
  // another state, through "connecting" or "disconnecting" or not; `up`:
  // one of them came up (its card; one going down as another comes up is
  // a switch, shown as the one up). A row appearing (its service
  // answering, Tailscale's first status) isn't a change; one going away
  // is forgotten
  function vpnStep(last, now) {
    const next = {};
    let changed = false;
    let up = false;
    for (const id of Object.keys(now ?? {})) {
      const state = now[id];
      const was = last?.[id];
      if (state !== "on" && state !== "off") {
        if (was !== undefined)
          next[id] = was;
        continue;
      }
      if (was !== undefined && was !== state) {
        changed = true;
        up = up || state === "on";
      }
      next[id] = state;
    }
    return {
      "changed": changed,
      "up": up,
      "last": next
    };
  }

  // What changed in the streams using the camera or sharing the screen
  // (lists of their PipeWire node ids, which stay put while a stream's
  // name is still being read): "started" (one that wasn't, its card),
  // "stopped" (none now, after some), else ""
  function captureChange(before, after) {
    const was = before ?? [];
    const now = after ?? [];
    if (now.some(id => !was.includes(id)))
      return "started";
    if (now.length === 0 && was.length > 0)
      return "stopped";
    return "";
  }

  // The status types that show a card for a change (`fired(true)`): an
  // audio device switching, a VPN coming up, an app starting to use the
  // camera or share the screen, the charger plugged in, a Wi-Fi network
  // joined, something done to a drive (DrivesManager.lastEvent), and a
  // message (always: alwaysCard)
  readonly property var cardTypes: ["audio", "microphone", "vpn", "camera", "screenShare", "micUse", "charger", "wifi", "drive", "message"]

  // The types shown as their card even on an OSD whose detail cards are
  // off: a message is its text, nothing without it
  function alwaysCard(type) {
    return type === "message";
  }

  // A drive event's card (DrivesManager.lastEvent's kinds): its icon and
  // what happened (English)
  readonly property var _driveCards: ({
      "added": {
        "icon": "usb",
        "role": "Connected"
      },
      "locked": {
        "icon": "lock",
        "role": "Encrypted: click to unlock"
      },
      "mounted": {
        "icon": "usb",
        "role": "Mounted"
      },
      "unmounted": {
        "icon": "usb",
        "role": "Unmounted"
      },
      "ejected": {
        "icon": "eject",
        "role": "Safe to remove"
      },
      "removed": {
        "icon": "usb_off",
        "role": "Disconnected"
      },
      "pulled": {
        "icon": "warning",
        "role": "Unplugged without ejecting"
      },
      "busy": {
        "icon": "warning",
        "role": "In use: close what's using it"
      },
      "ejectFailed": {
        "icon": "warning",
        "role": "Couldn't eject"
      }
    })

  // Whether two capture tiles (tile()'s) share an app: one app taking the
  // camera and the microphone together (a call)
  function _sameApp(a, b) {
    const apps = a?.apps ?? [];
    return apps.some(app => (b?.apps ?? []).includes(app));
  }

  // What a status's card shows, from the OSD's tiles (by type, tile()'s)
  // and status types: { icon, title, role, detail, tone, clickable (a
  // click acts on it: a drive's, DrivesManager.activate) }, or null for a
  // type with no card. `role` is English, for the caller to translate
  // (what an audio device is now used for: "Output and input" when the
  // OSD's other device status holds the same device; what a VPN, the apps
  // or the charger did, a drive's last event); `detail` an audio device's
  // profile, a VPN's address, a network's signal, the time left to a full
  // battery, where a drive was mounted, a message's second line; `tone` a
  // message's ("warning" for a refusal, else "")
  function card(type, tiles, types) {
    if (!root.cardTypes.includes(type))
      return null;
    const t = tiles?.[type] ?? {};
    const out = {
      "icon": t.icon ?? "",
      "title": t.name ?? "",
      "role": "",
      "detail": "",
      "tone": t.tone ?? "",
      "clickable": type === "drive"
    };
    switch (type) {
    case "audio":
    case "microphone":
      {
        const other = type === "audio" ? "microphone" : "audio";
        const key = t.device ?? "";
        const both = key !== "" && (types ?? []).includes(other) && tiles?.[other]?.device === key;
        out.role = both ? "Output and input" : type === "audio" ? "Output" : "Input";
        out.detail = t.detail ?? "";
        break;
      }
    case "vpn":
      out.role = "Connected";
      out.detail = t.address ?? "";
      break;
    case "camera":
    case "micUse":
    case "screenShare":
      {
        // Stopped while its card shows (a picker's preview stream): who
        // it was, and that it stopped
        if ((t.apps ?? []).length === 0 && (t.last ?? []).length > 0) {
          out.title = t.last.join(", ");
          out.role = type === "camera" ? "Stopped using the camera" : type === "micUse" ? "Stopped using the microphone" : "Stopped sharing the screen";
          break;
        }
        if (type === "screenShare") {
          out.role = "Sharing the screen";
          break;
        }
        // One app on both: one card says so, whichever came first
        const other = type === "camera" ? "micUse" : "camera";
        const both = (types ?? []).includes(other) && root._sameApp(t, tiles?.[other]);
        out.role = both ? "Using the camera and microphone" : type === "camera" ? "Using the camera" : "Using the microphone";
        break;
      }
    case "charger":
      out.icon = "battery_charging_full";
      out.title = `${t.percent ?? 0}%`;
      out.role = t.full === true ? "Fully charged" : t.charging === true ? "Charging" : "Plugged in";
      out.detail = t.full === true ? "" : (t.untilFull ?? "");
      break;
    case "wifi":
      out.role = "Connected";
      out.detail = t.name ? `${t.signal ?? 0}%` : "";
      break;
    case "drive":
      {
        const look = root._driveCards[t.event] ?? root._driveCards.added;
        out.icon = look.icon;
        out.role = look.role;
        out.detail = t.event === "mounted" ? (t.mountPoint ?? "") : "";
        break;
      }
    case "message":
      out.detail = t.detail ?? "";
      break;
    }
    return out;
  }

  // How long after a change its own knock-on changes (airplane mode
  // switching the radios, a headset taking the output then the input, a
  // new device's mute) don't take its highlight, in ms
  readonly property int quietWindow: 2000

  // The on-screen mark a bar or status type is judged by (a change the
  // pointer made in axiom's own bar or panels, ShellManager.onScreen):
  // every output level and the output device one ("audio"), the input's
  // ("microphone"), else the type itself
  function onScreenKind(type) {
    if (type === "master" || type === "other" || type === "app")
      return "audio";
    return type;
  }

  // How long after a mark the change it made may still come in, in ms:
  // a connection's state settles seconds after the click
  function onScreenWindow(kind) {
    if (kind === "vpn")
      return 15000;
    if (kind === "wifi" || kind === "bluetooth" || kind === "airplane")
      return 8000;
    return 2000;
  }

  // Whether a change of `type` is the pointer's own, `elapsed` ms after
  // its kind was last marked (Infinity: never)
  function fromScreen(type, elapsed) {
    return elapsed >= 0 && elapsed < root.onScreenWindow(root.onScreenKind(type));
  }

  // Whether a change of type `incoming` takes the highlight from `shown`
  // (the type highlighted, "" for none) `elapsed` ms after it took it,
  // over `tiles` (by type, tile()'s); `shownCard` / `incomingCard`: the
  // change shows its card (cardTypes: an audio device switching, not its
  // mute; a VPN coming up; a capture starting). Always, except Wi-Fi or
  // Bluetooth just after airplane mode switched them, a card's own status
  // changing again without one (a new device's mute, the other half of a
  // VPN switch, a capture stopping as soon as it started; not a VPN,
  // Wi-Fi or the charger turning off), the camera and
  // the microphone taken by the same app together (one card says both),
  // the output and
  // input switching to the same device together (one change: a headset),
  // and either device's mute just after a device switch (its own state
  // coming in, not the user); a message's card gives way only to another
  // card (its text gets read)
  function replaces(shown, incoming, elapsed, tiles, shownCard, incomingCard) {
    if (elapsed >= root.quietWindow)
      return true;
    if (shown === "message" && shownCard === true)
      return incomingCard === true;
    if (shown === "airplane" && (incoming === "wifi" || incoming === "bluetooth"))
      return false;
    if (shownCard !== true)
      return true;
    // A card that said "on" (a VPN up, a network joined, the charger
    // plugged in) gives way to its status turning off: it would say what
    // no longer holds
    if (incoming === shown && incomingCard !== true)
      return ["vpn", "wifi", "charger"].includes(incoming) && tiles?.[incoming]?.on !== true;
    const calls = ["camera", "micUse"];
    if (incomingCard === true && shown !== incoming && calls.includes(shown) && calls.includes(incoming) && root._sameApp(tiles?.[shown], tiles?.[incoming]))
      return false;
    const audio = ["audio", "microphone"];
    if (!audio.includes(shown) || !audio.includes(incoming))
      return true;
    if (incomingCard !== true)
      return false;
    if (shown !== incoming) {
      const a = tiles?.[shown]?.device ?? "";
      return a === "" || a !== (tiles?.[incoming]?.device ?? "");
    }
    return true;
  }

  // An audio device's name for the OSD's card, from its PipeWire node
  // ({ nick: node.nick, description: node.description, profile:
  // device.profile.description, bus: device.bus, kind: deviceKind's }):
  // { title, detail }. The nick names the device ("AudioBox Go", a
  // monitor's model, a headset's alias) unless it's a sound chip's
  // generic one; else the description without the profile it ends with
  // (a virtual device's own name); a built-in sound chip's description
  // names the chip, not what's plugged in, so it's the kind's. `detail`
  // the profile ("Analog Stereo"), unless the title is the description.
  // I18n.tr("Speakers") I18n.tr("Headphones") I18n.tr("Headset") I18n.tr("Display") I18n.tr("Webcam") I18n.tr("Bluetooth")
  function deviceName(d) {
    const nick = String(d?.nick ?? "").trim();
    const profile = String(d?.profile ?? "").trim();
    let description = String(d?.description ?? "").trim();
    const generic = nick === "" || /^(HD-Audio Generic|HDA\b)/i.test(nick);
    if (!generic)
      return {
        "title": nick,
        "detail": profile
      };
    if (description !== "" && d?.bus !== "pci") {
      description = description.replace(/\s*\[[^\]]*\]$/, "");
      if (profile !== "" && description.endsWith(" " + profile))
        return {
          "title": description.slice(0, -profile.length - 1),
          "detail": profile
        };
      return {
        "title": description,
        "detail": ""
      };
    }
    const labels = {
      "speaker": "Speakers",
      "headphones": "Headphones",
      "headset": "Headset",
      "hdmi": "Display",
      "webcam": "Webcam",
      "bluetooth": "Bluetooth"
    };
    return {
      "title": labels[d?.kind] ?? labels.speaker,
      "detail": profile,
      "translate": true
    };
  }
}

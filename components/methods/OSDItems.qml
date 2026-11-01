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
  //   { icon, label, caption, on, slash, notable, hidden }
  // (an audio device's also { name, detail, device })
  // `icon` always the base one ("wifi", never "wifi_off": a toggle off is
  // `slash`, drawn as one struck-through style whatever the icon), `label`
  // short text drawn instead of the icon (a layout's code), `caption` text
  // shown beside it only as it changes (a message), `on`
  // lit (a toggle on, the microphone live), `slash` a toggle off,
  // `notable` out of the ordinary (the row's "What's unusual"), `hidden`
  // nothing to show (no Wi-Fi, one layout). States:
  //   capsLock / numLock / scrollLock { available, on },
  //   keyboardLayout { layouts, index },
  //   audio / microphone { muted, name, detail, icon (the device's,
  //   unmuted), device (its identity, deviceKey's) }, powerProfile { profile: "powerSaver" |
  //   "balanced" | "performance" | "" }, charger { available, plugged },
  //   message { icon, text }, every other type { available, on }
  function tile(type, state) {
    const t = {
      "icon": "",
      "label": "",
      "caption": "",
      "on": false,
      "slash": false,
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
          "slash": s.on !== true,
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
        "on": s.plugged === true,
        "slash": s.plugged !== true,
        "notable": s.available === true && s.plugged === false,
        "hidden": s.available !== true
      });
    case "message":
      return Object.assign(t, {
        "icon": s.icon || "chat",
        "caption": s.text ?? "",
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
      "airplane": ["airplanemode_active", true]
    };
    const toggle = toggles[type];
    if (!toggle)
      return Object.assign(t, {
        "hidden": true
      });
    const on = s.on === true;
    return Object.assign(t, {
      "icon": toggle[0],
      "on": on,
      "slash": !on,
      "notable": toggle[1] !== null && on === toggle[1],
      "hidden": s.available === false
    });
  }

  // The statuses the row shows, in the OSD's order: of `types` (its
  // statuses), by `mode` ("notable" | "all" | "changed") over `tiles` (by
  // type, tile()'s), `changed` (the type that just changed, or "") always
  // among them. A hidden tile shows only as it changes; a message only as
  // one comes.
  function rowTypes(types, tiles, mode, changed) {
    return types.filter(type => {
      if (type === changed)
        return true;
      const t = tiles[type];
      if (!t || t.hidden || type === "message")
        return false;
      return mode === "all" || (mode === "notable" && t.notable);
    });
  }

  // How long after a change its own knock-on changes (airplane mode
  // switching the radios, a headset taking the output then the input, a
  // new device's mute)
  // don't take its highlight, in ms
  readonly property int quietWindow: 2000

  // Whether a change of type `incoming` takes the highlight from `shown`
  // (the type highlighted, "" for none) `elapsed` ms after it took it,
  // over `tiles` (by type, tile()'s); `shownSwitch` / `incomingSwitch`:
  // the change is an audio device switching (its card), not its mute.
  // Always, except Wi-Fi or Bluetooth just after airplane mode switched
  // them, the output and input switching to the same device together
  // (one change: a headset), and a mute just after a device switch (the
  // new device's own state coming in, not the user)
  function replaces(shown, incoming, elapsed, tiles, shownSwitch, incomingSwitch) {
    if (elapsed >= root.quietWindow)
      return true;
    if (shown === "airplane" && (incoming === "wifi" || incoming === "bluetooth"))
      return false;
    const audio = ["audio", "microphone"];
    if (shownSwitch !== true || !audio.includes(incoming))
      return true;
    if (incomingSwitch !== true)
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

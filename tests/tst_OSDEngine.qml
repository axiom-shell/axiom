import QtQuick
import QtTest
import qs.components.methods
import qs.components.surfaces.osd.engine

// OSDEngine: the judgement by model and policy, the arbitration between
// changes (what was OSDItems.replaces / besideCard), the card routing
// (cardRoute / opensCard), over small stand-in definitions declaring what
// the real systems do
TestCase {
  name: "OSDEngine"

  OSDSystem {
    id: toggle
    type: "Toggle"
    exposes: [
      {
        "key": "toggle",
        "part": "tile",
        "icon": "coffee",
        "action": "idleInhibit"
      }
    ]
    function tile(key, state) {
      return {
        "on": state.value === true,
        "notable": state.value === true
      };
    }
  }

  // An output and an input device: a switch is a card, a mute the icon;
  // one headset taking both is one change, and its own state coming in
  // after a switch (a mute, a level) is the card's
  OSDSystem {
    id: audio
    type: "Audio"
    onChange: "card"
    onAdd: "none"
    onRemove: "none"
    exposes: [
      {
        "key": "master",
        "part": "bar",
        "mark": "audio"
      },
      {
        "key": "audio",
        "part": "tile",
        "icon": "volume_up"
      },
      {
        "key": "microphone",
        "part": "tile",
        "icon": "mic"
      }
    ]
    function tile(key, state) {
      return {
        "on": state.muted !== true,
        "slash": state.muted === true,
        "device": state.value ?? ""
      };
    }
    function card(change, state) {
      return {
        "title": "Device"
      };
    }
    function sameChange(shown, incoming) {
      if (incoming.card !== true)
        return true;
      const device = shown.tile?.device ?? "";
      return shown.key !== incoming.key && device !== "" && device === (incoming.tile?.device ?? "");
    }
  }

  // Captures: a start is a card, one of several stopping a "still" card,
  // the last the icon; one app on the camera and the microphone is one
  // card
  OSDSystem {
    id: privacy
    type: "Privacy"
    model: "set"
    onAdd: "card"
    onRemove: "still"
    anyone: true
    exposes: [
      {
        "key": "camera",
        "part": "tile",
        "icon": "videocam"
      },
      {
        "key": "micUse",
        "part": "tile",
        "icon": "record_voice_over"
      },
      {
        "key": "screenShare",
        "part": "tile",
        "icon": "screen_share"
      }
    ]
    function tile(key, state) {
      const apps = (state.members ?? []).map(m => m.name);
      return {
        "apps": apps,
        "on": apps.length > 0
      };
    }
    function card(change, state) {
      return {
        "title": "Apps"
      };
    }
    function sameChange(shown, incoming) {
      if (incoming.card !== true)
        return shown.key === incoming.key;
      const calls = ["camera", "micUse"];
      const apps = shown.tile?.apps ?? [];
      return shown.key !== incoming.key && calls.includes(shown.key) && calls.includes(incoming.key) && apps.some(app => (incoming.tile?.apps ?? []).includes(app));
    }
  }

  OSDSystem {
    id: vpn
    type: "Vpn"
    model: "set"
    onAdd: "card"
    onRemove: "icon"
    onUnexpectedRemove: "card"
    anyone: true
    retractsCardWhenOff: true
    userWindow: 15000
    exposes: [
      {
        "key": "vpn",
        "part": "tile",
        "icon": "vpn_key"
      }
    ]
    function tile(key, state) {
      return {
        "on": (state.members ?? []).length > 0
      };
    }
  }

  OSDSystem {
    id: battery
    type: "Battery"
    retractsCardWhenOff: true
    exposes: [
      {
        "key": "charger",
        "part": "tile",
        "icon": "power",
        "onAdd": "card"
      },
      {
        "key": "battery",
        "part": "tile",
        "icon": "battery_full",
        "model": "event",
        "onAdd": "card"
      }
    ]
    function tile(key, state) {
      return {
        "on": key === "charger" ? state.value === true : false
      };
    }
  }

  OSDSystem {
    id: airplane
    type: "Airplane"
    exposes: [
      {
        "key": "airplane",
        "part": "tile"
      }
    ]
  }

  OSDSystem {
    id: wifi
    type: "Wifi"
    knockOnOf: ["Airplane"]
    retractsCardWhenOff: true
    userWindow: 8000
    exposes: [
      {
        "key": "wifi",
        "part": "tile",
        "icon": "wifi"
      }
    ]
  }

  OSDSystem {
    id: message
    type: "Message"
    model: "event"
    onAdd: "card"
    exposes: [
      {
        "key": "message",
        "part": "card",
        "icon": "chat"
      }
    ]
  }

  OSDSystem {
    id: lockKeys
    type: "LockKeys"
    exposes: [
      {
        "key": "capsLock",
        "part": "tile"
      }
    ]
  }

  // A Bluetooth headset's card takes in Audio's switch to it
  OSDSystem {
    id: bluetooth
    type: "Bluetooth"
    knockOnOf: ["Airplane"]
    exposes: [
      {
        "key": "bluetooth",
        "part": "tile"
      }
    ]
    function absorbs(own, other) {
      return other.system === "Audio" && other.tile?.device === own.tile?.address;
    }
  }

  // The lowest card (Now playing's)
  OSDSystem {
    id: media
    type: "Media"
    yieldsCard: true
    exposes: [
      {
        "key": "media",
        "part": "card",
        "icon": "music_note"
      }
    ]
  }

  readonly property var defs: ({
      "Media": media,
      "Audio": audio,
      "Privacy": privacy,
      "Vpn": vpn,
      "Battery": battery,
      "Airplane": airplane,
      "Wifi": wifi,
      "Message": message,
      "LockKeys": lockKeys,
      "Bluetooth": bluetooth
    })

  function at(system, key, card, tile) {
    return {
      "system": system,
      "key": key,
      "part": "tile",
      "card": card === true,
      "tile": tile ?? {}
    };
  }

  function members(...names) {
    return {
      "members": names.map(name => ({
            "id": name,
            "name": name
          }))
    };
  }

  function test_entry() {
    compare(OSDEngine.partOf(audio, "master"), "bar");
    compare(OSDEngine.partOf(audio, "nope"), "tile", "a tile unless it says");
    compare(OSDEngine.markOf(audio, "master"), "audio", "its mark");
    compare(OSDEngine.markOf(audio, "audio"), "audio", "else the key");
    compare(OSDEngine.policy(battery, "battery", "model"), "event", "the entry's own");
    compare(OSDEngine.policy(battery, "charger", "model"), "scalar", "else the system's");
    verify(OSDEngine.byUser(vpn, "vpn", 14000), "a VPN's long window");
    verify(!OSDEngine.byUser(toggle, "toggle", 2000), "the default 2 s");
    verify(!OSDEngine.byUser(toggle, "toggle", -1), "never marked");
    verify(!OSDEngine.byUser(toggle, "toggle", undefined), "never marked");
  }

  function test_tileOf() {
    compare(OSDEngine.tileOf(toggle, "toggle", {
      "value": true
    }), {
      "icon": "coffee",
      "label": "",
      "tone": "",
      "on": true,
      "slash": false,
      "notable": true,
      "hidden": false
    }, "filled out, the icon from exposes");
    compare(OSDEngine.tileOf(audio, "audio", undefined).device, "", "no state yet");
  }

  function test_cardOf() {
    verify(OSDEngine.cardOf(toggle, {
      "key": "toggle"
    }, {}) === null, "none");
    compare(OSDEngine.cardOf(audio, {
      "key": "audio"
    }, {
      "audio": {
        "value": "60"
      }
    }), {
      "icon": "volume_up",
      "image": "",
      "title": "Device",
      "role": "",
      "detail": "",
      "tone": "",
      "clickable": false
    }, "its tile's icon");
  }

  function test_judge_scalar() {
    const on = {
      "value": true
    };
    const off = {
      "value": false
    };
    verify(OSDEngine.judge(toggle, "toggle", undefined, on, {}) === null, "the first reading");
    verify(OSDEngine.judge(toggle, "toggle", on, on, {}) === null, "the same");
    const turned = OSDEngine.judge(toggle, "toggle", off, on, {
      "at": 5,
      "byUser": true
    });
    compare([turned.kind, turned.show, turned.card, turned.at, turned.byUser, turned.part], ["add", "tile", false, 5, true, "tile"]);
    compare(OSDEngine.judge(toggle, "toggle", on, off, {}).kind, "remove");
    verify(OSDEngine.judge(toggle, "toggle", Object.assign({
      "available": false
    }, off), on, {}) === null, "across an unavailable state");
    verify(OSDEngine.judge(toggle, "toggle", off, Object.assign({
      "available": false
    }, on), {}) === null, "its service gone");
  }

  function test_judge_device() {
    const at = (device, muted) => ({
          "value": device,
          "muted": muted === true
        });
    verify(OSDEngine.judge(audio, "audio", at(""), at("60"), {}) === null, "a device appearing: onAdd none");
    verify(OSDEngine.judge(audio, "audio", at("60"), at(""), {}) === null, "gone: onRemove none");
    const switched = OSDEngine.judge(audio, "audio", at("60"), at("52"), {});
    compare([switched.kind, switched.show, switched.card], ["change", "card", true], "a switch");
    const muted = OSDEngine.judge(audio, "audio", at("60"), at("60", true), {});
    compare([muted.kind, muted.show], ["update", "tile"], "a mute: its look");
    verify(OSDEngine.judge(audio, "audio", at("60"), at("60", true), {
      "settled": false
    }) === null, "unsettled: the device's own");
    const level = OSDEngine.judge(audio, "master", {
      "level": 0.4
    }, {
      "level": 0.5
    }, {});
    compare([level.kind, level.show, level.part], ["level", "level", "bar"], "a bar");
  }

  function test_judge_set() {
    const started = OSDEngine.judge(privacy, "camera", members(), members("Zoom"), {});
    compare([started.kind, started.show, started.added], ["add", "card", ["Zoom"]]);
    const one = OSDEngine.judge(privacy, "micUse", members("Zoom", "OBS"), members("OBS"), {});
    compare([one.kind, one.show, one.still, one.removed, one.left], ["remove", "card", true, ["Zoom"], ["OBS"]], "one of several: still");
    const last = OSDEngine.judge(privacy, "micUse", members("OBS"), members(), {});
    compare([last.show, last.still], ["tile", false], "the last: the icon");
    verify(OSDEngine.judge(privacy, "camera", members("Zoom"), members("Zoom"), {
      "settled": false
    }) === null, "the same members");
    compare(OSDEngine.judge(privacy, "camera", members(), members("Zoom"), {
      "settled": false
    }).show, "card", "anyone's: unsettled counts");

    const down = OSDEngine.judge(vpn, "vpn", members("work"), members(), {});
    compare([down.show, down.unexpected], ["card", true], "a drop no one made: its card");
    const taken = OSDEngine.judge(vpn, "vpn", members("work"), members(), {
      "byUser": true
    });
    compare([taken.show, taken.unexpected], ["tile", false], "taken down on screen: the icon");
    compare(OSDEngine.judge(vpn, "vpn", members("work"), members("home"), {}).show, "card", "a switch: the one up");
  }

  function test_judge_event() {
    const first = {
      "kind": "low"
    };
    verify(OSDEngine.judge(battery, "battery", undefined, {
      "event": first,
      "seq": 1
    }, {}) === null, "one there at the start");
    const low = OSDEngine.judge(battery, "battery", {
      "event": null
    }, {
      "event": first,
      "seq": 1
    }, {});
    compare([low.kind, low.show], ["event", "card"]);
    verify(OSDEngine.judge(battery, "battery", {
      "event": first,
      "seq": 1
    }, {
      "event": first,
      "seq": 1
    }, {}) === null, "the same event");
    verify(OSDEngine.judge(battery, "battery", {
      "event": first,
      "seq": 1
    }, {
      "event": first,
      "seq": 2
    }, {}) !== null, "the same again, pulsed anew");
    verify(OSDEngine.judge(battery, "battery", {
      "event": first,
      "seq": 1,
      "percent": 20
    }, {
      "event": {
        "kind": "low"
      },
      "seq": 1,
      "percent": 19
    }, {}) === null, "the same seq read again with the rest of the state: no event");
    compare(OSDEngine.judge(battery, "charger", {
      "value": false
    }, {
      "value": true
    }, {}).show, "card", "the entry's own policy");
  }

  function test_judge_custom() {
    const own = Qt.createQmlObject(`
      import QtQuick
      import qs.components.surfaces.osd.engine
      OSDSystem {
        type: "Odd"
        property var seen: []
        exposes: [{ "key": "odd", "part": "tile" }]
        function judge(before, after, ctx) {
          seen = seen.concat([ctx.settled]);
          if (after.value === "default")
            return undefined;
          if (after.value === "skip")
            return null;
          return { "kind": "change", "show": "card", "why": ctx.before?.other, "alert": after.value === "alert" };
        }
      }`, this);
    verify(OSDEngine.judge(own, "odd", {
      "value": 1
    }, {
      "value": "skip"
    }, {}) === null, "its own nothing");
    const card = OSDEngine.judge(own, "odd", {
      "value": 1
    }, {
      "value": 2
    }, {
      "settled": false,
      "before": {
        "other": "x"
      }
    });
    compare([card.show, card.card, card.why, card.alert], ["card", true, "x", false], "its own, unsettled too");
    compare(own.seen[own.seen.length - 1], false, "it reads ctx.settled");
    verify(OSDEngine.judge(own, "odd", {
      "value": 1
    }, {
      "value": "default"
    }, {
      "settled": false
    }) === null, "left to the engine: nothing while unsettled");
    const calls = own.seen.length;
    verify(OSDEngine.judge(own, "odd", undefined, {
      "value": 2
    }, {}) === null, "never the first reading");
    verify(OSDEngine.judge(own, "odd", {
      "value": 1,
      "available": false
    }, {
      "value": 2
    }, {}) === null, "nor across an unavailable state");
    compare(own.seen.length, calls, "its judge() isn't asked for either");
    compare(OSDEngine.judge(own, "odd", {
      "value": 1
    }, {
      "value": "alert"
    }, {}).alert, true, "an alert it sets");
    own.destroy();
  }

  function test_updateFields() {
    const own = Qt.createQmlObject(`
      import QtQuick
      import qs.components.surfaces.osd.engine
      OSDSystem {
        type: "Device"
        updateFields: ["label"]
        exposes: [{ "key": "a", "part": "tile" }, { "key": "b", "part": "tile", "updateFields": ["icon"] }]
        function tile(key, state) {
          return { "icon": state.icon ?? "", "label": state.label ?? "", "slash": state.muted === true };
        }
      }`, this);
    const at = (icon, label, muted) => ({
          "value": "60",
          "icon": icon,
          "label": label,
          "muted": muted === true
        });
    verify(OSDEngine.judge(own, "a", at("headphones", ""), at("headset_mic", "")) === null, "a profile switch's icon: not a look change");
    compare(OSDEngine.judge(own, "a", at("headphones", ""), at("headphones", "", true)).kind, "update", "a mute always is");
    compare(OSDEngine.judge(own, "a", at("headphones", "x"), at("headphones", "y")).kind, "update", "a listed field");
    compare(OSDEngine.judge(own, "b", at("headphones", ""), at("headset_mic", "")).kind, "update", "the entry's own list");
    compare(OSDEngine.judge(toggle, "toggle", {
      "value": true,
      "label": "x"
    }, {
      "value": true,
      "label": "x",
      "name": "y"
    }), null, "a field the tile doesn't show");
    own.destroy();
  }

  function test_opens() {
    const bars = Qt.createQmlObject(`
      import QtQuick
      import qs.components.surfaces.osd.engine
      OSDSystem {
        type: "Bars"
        exposes: [{ "key": "master", "part": "bar" }, { "key": "app:0", "part": "bar", "opens": false }]
      }`, this);
    const change = (key, extra) => Object.assign({
        "key": key,
        "byUser": false,
        "alert": false
      }, extra ?? {});
    verify(OSDEngine.opens({}, bars, change("master"), false), "anyone's change");
    verify(!OSDEngine.opens({}, bars, change("master", {
      "byUser": true
    }), false), "made on screen");
    verify(OSDEngine.opens({}, bars, change("master", {
      "byUser": true
    }), true), "made on screen, with onScreenChanges");
    verify(OSDEngine.opens({}, bars, change("master", {
      "byUser": true,
      "alert": true
    }), false), "an alert opens it anyway");
    verify(!OSDEngine.opens({
      "quiet": true
    }, bars, change("master", {
      "alert": true
    }), false), "quiet, even an alert");
    verify(!OSDEngine.opens({}, bars, change("app:0"), false), "its key's opens: false (showOsd off)");
    bars.destroy();
  }

  function test_arbitrate_whole_changes() {
    // A still card reads the incoming change's own fields (Privacy's)
    const own = Qt.createQmlObject(`
      import QtQuick
      import qs.components.surfaces.osd.engine
      OSDSystem {
        type: "Still"
        exposes: [{ "key": "micUse", "part": "tile" }]
        function sameChange(shown, incoming) {
          return shown.key === incoming.key && (incoming.card !== true || (shown.still === true && incoming.still === true));
        }
      }`, this);
    const defs = {
      "Still": own
    };
    const still = (left, at) => ({
          "system": "Still",
          "key": "micUse",
          "part": "tile",
          "kind": "remove",
          "card": true,
          "still": true,
          "left": left,
          "at": at,
          "tile": {
            "on": true
          }
        });
    compare(OSDEngine.arbitrate(still(["OBS", "Zoom"], 0), still(["OBS"], 300), 300, defs), "keep", "several stopping: one card");
    compare(OSDEngine.arbitrate(Object.assign(still(["OBS"], 0), {
      "still": false,
      "kind": "add"
    }), still(["OBS"], 300), 300, defs), "replace", "a start's card, then one stopping");
    own.destroy();
  }

  // What was OSDItems.replaces / besideCard, as declarations
  function test_arbitrate_data() {
    const w = OSDEngine.quietWindow;
    const headset = {
      "device": "60"
    };
    const other = {
      "device": "52"
    };
    return [
      // Rings
      {
        "tag": "anything takes the ring",
        "shown": at("LockKeys", "capsLock"),
        "incoming": at("Wifi", "wifi"),
        "elapsed": 0,
        "out": "replace"
      },
      {
        "tag": "airplane mode switching the radio",
        "shown": at("Airplane", "airplane"),
        "incoming": at("Wifi", "wifi"),
        "elapsed": 300,
        "out": "keep"
      },
      {
        "tag": "and Bluetooth",
        "shown": at("Airplane", "airplane"),
        "incoming": at("Bluetooth", "bluetooth"),
        "elapsed": w - 1,
        "out": "keep"
      },
      {
        "tag": "the user's own toggle later",
        "shown": at("Airplane", "airplane"),
        "incoming": at("Bluetooth", "bluetooth"),
        "elapsed": w,
        "out": "replace"
      },
      {
        "tag": "airplane mode always shows",
        "shown": at("Wifi", "wifi"),
        "incoming": at("Airplane", "airplane"),
        "elapsed": 0,
        "out": "replace"
      },
      {
        "tag": "mutes one after another",
        "shown": at("Audio", "audio", false, headset),
        "incoming": at("Audio", "microphone", false, headset),
        "elapsed": 300,
        "out": "replace"
      },
      // A message's card
      {
        "tag": "a message stays beside the icons",
        "shown": at("Message", "message", true),
        "incoming": at("LockKeys", "capsLock"),
        "elapsed": 300,
        "out": "beside"
      },
      {
        "tag": "another message",
        "shown": at("Message", "message", true),
        "incoming": at("Message", "message", true),
        "elapsed": 300,
        "out": "replace"
      },
      {
        "tag": "another card",
        "shown": at("Message", "message", true),
        "incoming": at("Audio", "audio", true),
        "elapsed": 300,
        "out": "replace"
      },
      // Audio
      {
        "tag": "a headset taking both: one change",
        "shown": at("Audio", "audio", true, headset),
        "incoming": at("Audio", "microphone", true, headset),
        "elapsed": 300,
        "out": "keep"
      },
      {
        "tag": "either order",
        "shown": at("Audio", "microphone", true, headset),
        "incoming": at("Audio", "audio", true, headset),
        "elapsed": 300,
        "out": "keep"
      },
      {
        "tag": "the user's own switch later",
        "shown": at("Audio", "audio", true, headset),
        "incoming": at("Audio", "microphone", true, headset),
        "elapsed": w,
        "out": "replace"
      },
      {
        "tag": "the output switching again",
        "shown": at("Audio", "audio", true, headset),
        "incoming": at("Audio", "audio", true, other),
        "elapsed": 300,
        "out": "replace"
      },
      {
        "tag": "another device",
        "shown": at("Audio", "audio", true, headset),
        "incoming": at("Audio", "microphone", true, other),
        "elapsed": 300,
        "out": "replace"
      },
      {
        "tag": "the new input's mute coming in",
        "shown": at("Audio", "microphone", true, other),
        "incoming": at("Audio", "microphone", false, other),
        "elapsed": 300,
        "out": "suppress"
      },
      {
        "tag": "a headset's mute coming in",
        "shown": at("Audio", "audio", true, headset),
        "incoming": at("Audio", "microphone", false, headset),
        "elapsed": 300,
        "out": "suppress"
      },
      {
        "tag": "the new device's level coming in late",
        "shown": at("Audio", "audio", true, headset),
        "incoming": {
          "system": "Audio",
          "key": "master",
          "part": "bar",
          "card": false,
          "tile": {}
        },
        "elapsed": 300,
        "out": "suppress"
      },
      {
        "tag": "the user's own mute later",
        "shown": at("Audio", "microphone", true, other),
        "incoming": at("Audio", "microphone", false, other),
        "elapsed": w,
        "out": "beside"
      },
      // A card's own follow-up
      {
        "tag": "the other half of a VPN switch",
        "shown": at("Vpn", "vpn", true),
        "incoming": at("Vpn", "vpn", false, {
          "on": true
        }),
        "elapsed": 300,
        "out": "suppress"
      },
      {
        "tag": "another VPN up",
        "shown": at("Vpn", "vpn", true),
        "incoming": at("Vpn", "vpn", true, {
          "on": true
        }),
        "elapsed": 300,
        "out": "replace"
      },
      {
        "tag": "a drop just after: the card would say Connected",
        "shown": at("Vpn", "vpn", true),
        "incoming": at("Vpn", "vpn", false, {
          "on": false
        }),
        "elapsed": 300,
        "out": "retract"
      },
      {
        "tag": "a drop later too",
        "shown": at("Vpn", "vpn", true),
        "incoming": at("Vpn", "vpn", false, {
          "on": false
        }),
        "elapsed": 5000,
        "out": "retract"
      },
      {
        "tag": "unrelated: the card stays",
        "shown": at("Vpn", "vpn", true),
        "incoming": at("LockKeys", "capsLock"),
        "elapsed": 300,
        "out": "beside"
      },
      {
        "tag": "unplugged just after: the card would say Plugged in",
        "shown": at("Battery", "charger", true),
        "incoming": at("Battery", "charger", false, {
          "on": false
        }),
        "elapsed": 300,
        "out": "retract"
      },
      {
        "tag": "a charger's card isn't the battery's",
        "shown": at("Battery", "battery", true),
        "incoming": at("Battery", "charger", false, {
          "on": false
        }),
        "elapsed": 300,
        "out": "beside"
      },
      {
        "tag": "Wi-Fi off just after joining",
        "shown": at("Wifi", "wifi", true),
        "incoming": at("Wifi", "wifi", false, {
          "on": false
        }),
        "elapsed": 300,
        "out": "retract"
      },
      {
        "tag": "Wi-Fi still on",
        "shown": at("Wifi", "wifi", true),
        "incoming": at("Wifi", "wifi", false, {
          "on": true
        }),
        "elapsed": 300,
        "out": "suppress"
      },
      // Captures
      {
        "tag": "a capture stopping as it starts",
        "shown": at("Privacy", "camera", true),
        "incoming": at("Privacy", "camera", false),
        "elapsed": 300,
        "out": "suppress"
      },
      {
        "tag": "another capture stopping",
        "shown": at("Privacy", "camera", true),
        "incoming": at("Privacy", "micUse", false),
        "elapsed": 300,
        "out": "beside"
      },
      {
        "tag": "a capture's card isn't a device switch",
        "shown": at("Privacy", "camera", true),
        "incoming": at("Audio", "microphone", false, headset),
        "elapsed": 300,
        "out": "beside"
      },
      {
        "tag": "another capture's card",
        "shown": at("Privacy", "camera", true),
        "incoming": at("Privacy", "screenShare", true),
        "elapsed": 300,
        "out": "replace"
      },
      {
        "tag": "one app on the camera and the microphone: one card",
        "shown": at("Privacy", "camera", true, {
          "apps": ["Zoom"]
        }),
        "incoming": at("Privacy", "micUse", true, {
          "apps": ["Zoom"]
        }),
        "elapsed": 300,
        "out": "keep"
      },
      {
        "tag": "another app on the microphone",
        "shown": at("Privacy", "camera", true, {
          "apps": ["Zoom"]
        }),
        "incoming": at("Privacy", "micUse", true, {
          "apps": ["OBS"]
        }),
        "elapsed": 300,
        "out": "replace"
      },
      {
        "tag": "another app on the camera",
        "shown": at("Privacy", "camera", true, {
          "apps": ["Zoom"]
        }),
        "incoming": at("Privacy", "camera", true, {
          "apps": ["Zoom", "OBS"]
        }),
        "elapsed": 300,
        "out": "replace"
      },
      // Across systems
      {
        "tag": "a headset's card takes in Audio's switch to it",
        "shown": at("Bluetooth", "bluetooth", true, {
          "address": "60"
        }),
        "incoming": at("Audio", "audio", true, headset),
        "elapsed": 300,
        "out": "keep"
      },
      {
        "tag": "and its level",
        "shown": at("Bluetooth", "bluetooth", true, {
          "address": "60"
        }),
        "incoming": at("Audio", "audio", false, headset),
        "elapsed": 300,
        "out": "suppress"
      },
      // yieldsCard: the lowest card never covers another's, at any age
      {
        "tag": "a yielding card against another system's card",
        "shown": at("Audio", "audio", true, other),
        "incoming": at("Media", "media", true),
        "elapsed": w + 5000,
        "out": "keep"
      },
      {
        "tag": "a yielding card against its own",
        "shown": at("Media", "media", true),
        "incoming": at("Media", "media", true),
        "elapsed": w + 1000,
        "out": "replace"
      },
      {
        "tag": "another card against a yielding card",
        "shown": at("Media", "media", true),
        "incoming": at("Audio", "audio", true, other),
        "elapsed": 300,
        "out": "replace"
      },
      {
        "tag": "another device's switch",
        "shown": at("Bluetooth", "bluetooth", true, {
          "address": "60"
        }),
        "incoming": at("Audio", "audio", true, other),
        "elapsed": 300,
        "out": "replace"
      }
    ];
  }

  function test_arbitrate(row) {
    compare(OSDEngine.arbitrate(row.shown, row.incoming, row.elapsed, defs), row.out);
  }

  function test_shownAs() {
    const osd = {
      "cardsEnabled": true,
      "systems": [
        {
          "type": "Vpn",
          "tile": true,
          "card": true
        },
        {
          "type": "Wifi",
          "tile": true,
          "card": false
        }
      ]
    };
    compare(OSDEngine.shownAs(osd, {
      "system": "Vpn",
      "show": "card"
    }, true), "card");
    compare(OSDEngine.shownAs(osd, {
      "system": "Wifi",
      "show": "card"
    }, true), "tile", "its cards off: the icon");
    compare(OSDEngine.shownAs(Object.assign({}, osd, {
      "cardsEnabled": false
    }), {
      "system": "Vpn",
      "show": "card"
    }, true), "tile", "the OSD's cards off");
    compare(OSDEngine.shownAs(Object.assign({}, osd, {
      "cardsEnabled": false
    }), {
      "system": "Vpn",
      "show": "card"
    }, false), "", "a card-only key: nothing");
    compare(OSDEngine.shownAs(osd, {
      "system": "Vpn",
      "show": "level"
    }, false), "level");
    compare(OSDEngine.shownAs({
      "cardsEnabled": true,
      "systems": [
        {
          "type": "Audio",
          "tile": false
        }
      ]
    }, {
      "system": "Audio",
      "show": "level"
    }, false), "", "the item's tiles off: no level");
  }

  function test_cardRoute_data() {
    const osd = (systems, extra) => Object.assign({
        "enabled": true,
        "cardsEnabled": true,
        "systems": systems
      }, extra ?? {});
    const item = (type, extra) => Object.assign({
        "type": type,
        "tile": true,
        "card": true,
        "quiet": false
      }, extra ?? {});
    return [
      {
        "tag": "an OSD listing it",
        "osds": [osd([item("Drives")])],
        "notify": true,
        "out": "osd"
      },
      {
        "tag": "none: a notification",
        "osds": [osd([item("Dnd")])],
        "notify": true,
        "out": "notification"
      },
      {
        "tag": "its switch off: nowhere",
        "osds": [osd([item("Dnd")])],
        "notify": false,
        "out": ""
      },
      {
        "tag": "quiet never opens it",
        "osds": [osd([item("Drives", {
              "quiet": true
            })])],
        "notify": true,
        "out": "notification"
      },
      {
        "tag": "its cards off",
        "osds": [osd([item("Drives", {
              "card": false
            })])],
        "notify": true,
        "out": "notification"
      },
      {
        "tag": "the OSD's cards off",
        "osds": [osd([item("Drives")], {
            "cardsEnabled": false
          })],
        "notify": true,
        "out": "notification"
      },
      {
        "tag": "a disabled OSD",
        "osds": [osd([item("Drives")], {
            "enabled": false
          })],
        "notify": true,
        "out": "notification"
      },
      {
        "tag": "any of several",
        "osds": [osd([]), osd([item("Drives")])],
        "notify": false,
        "out": "osd"
      },
      {
        "tag": "no OSDs",
        "osds": [],
        "notify": true,
        "out": "notification"
      }
    ];
  }

  function test_cardRoute(row) {
    compare(OSDEngine.cardRoute(row.osds, "Drives", row.notify), row.out);
  }

  function test_opensCard() {
    verify(!OSDEngine.opensCard(null, "Message"));
    verify(OSDEngine.opensCard({
      "enabled": true,
      "cardsEnabled": true,
      "systems": [
        {
          "type": "Message"
        }
      ]
    }, "Message"), "a card-only system listed");
    compare(OSDEngine.itemOf({
      "systems": []
    }, "Message"), null);
  }

  // An event's key against an item whose `tiles` pick what it shows (a
  // low battery only where Battery shows its battery icon; was
  // OSDConfig.routeOf's own filter)
  function test_opensCard_key() {
    const osd = tiles => ({
          "enabled": true,
          "cardsEnabled": true,
          "systems": [
            {
              "type": "Battery",
              "tiles": tiles
            }
          ]
        });
    verify(OSDEngine.opensCard(osd(["charger", "battery"]), "Battery", "battery"), "picked");
    verify(!OSDEngine.opensCard(osd(["charger"]), "Battery", "battery"), "its tiles leave it out");
    verify(OSDEngine.opensCard(osd(["charger"]), "Battery"), "no key: the system alone");
    verify(OSDEngine.opensCard({
      "enabled": true,
      "cardsEnabled": true,
      "systems": [
        {
          "type": "Drives"
        }
      ]
    }, "Drives", "drive"), "an item with no tiles setting");
    compare(OSDEngine.cardRoute([osd(["charger"])], "Battery", true, "battery"), "notification");
    compare(OSDEngine.cardRoute([osd(["charger"]), osd(["battery"])], "Battery", false, "battery"), "osd");
  }

  // The declared behaviours (stage 3a): each a stand-in declaring only it
  function _def(body) {
    return Qt.createQmlObject(`
      import QtQuick
      import qs.components.surfaces.osd.engine
      OSDSystem {
        ${body}
      }`, this);
  }

  // keepThroughGap: an empty value is a gap, the next judged against the
  // one before it; settledKinds: a switch counts unsettled, a mute not
  function test_keepThroughGap_settledKinds() {
    const def = _def(`
      type: "Device"
      onAdd: "none"
      onChange: "card"
      onRemove: "none"
      keepThroughGap: true
      settledKinds: ["update", "level"]
      exposes: [{ "key": "dev", "part": "tile" }, { "key": "level", "part": "bar" }]
      function tile(key, state) { return { "on": state.muted !== true, "slash": state.muted === true }; }`);
    const d = (value, muted) => ({
          "value": value,
          "muted": muted === true
        });
    compare(OSDEngine.remember(def, {
      "dev": d("52")
    }, {
      "dev": d("")
    }).dev.value, "52", "a gap keeps the value before it");
    compare(OSDEngine.remember(def, {
      "dev": d("52")
    }, {
      "dev": d("60")
    }).dev.value, "60", "a value replaces it");
    compare(OSDEngine.remember(toggle, {
      "toggle": {
        "value": true
      }
    }, {
      "toggle": {
        "value": false
      }
    }).toggle.value, false, "not declared: as it is");
    verify(OSDEngine.judge(def, "dev", d("52"), d(""), {}) === null, "the gap: nothing");
    verify(OSDEngine.judge(def, "dev", d(""), d("52"), {}) === null, "the first appearing: onAdd none");
    const sw = OSDEngine.judge(def, "dev", d("52"), d("60"), {
      "settled": false
    });
    compare([sw.kind, sw.show], ["change", "card"], "a switch, unsettled");
    verify(OSDEngine.judge(def, "dev", d("52"), d("52", true), {
      "settled": false
    }) === null, "a mute unsettled: nothing");
    compare(OSDEngine.judge(def, "dev", d("52"), d("52", true), {}).kind, "update", "a mute settled");
    compare(OSDEngine.judge(def, "dev", d("52"), d("60", true), {
      "settled": false
    }).show, "card", "a switch and a mute unsettled: the switch");
    verify(OSDEngine.judge(def, "level", {
      "level": 0.5
    }, {
      "level": 0
    }, {
      "settled": false
    }) === null, "a level unsettled");
    verify(OSDEngine.judge(toggle, "toggle", {
      "value": false
    }, {
      "value": true
    }, {
      "settled": false
    }) === null, "undeclared: every kind needs it settled");
    def.destroy();
  }

  // resetBy: a field changing with it makes it nobody's; ignoreWithin: a
  // change just after an outside event, unless the user's own came too
  function test_resetBy_ignoreWithin() {
    const def = _def(`
      type: "Layout"
      onAdd: "none"
      onRemove: "none"
      updateFields: []
      resetBy: ["ids"]
      ignoreWithin: ({ "after": "focusedAt", "ms": 1000, "unlessAfter": "switchedAt" })
      exposes: [{ "key": "layout", "part": "tile" }]`);
    const s = (ids, value, focusedAt, switchedAt) => ({
          "ids": ids,
          "value": value,
          "label": value.toUpperCase(),
          "focusedAt": focusedAt ?? 0,
          "switchedAt": switchedAt ?? 0
        });
    const two = ["us", "de"];
    const at = {
      "at": 5000
    };
    compare(OSDEngine.judge(def, "layout", s(two, "us"), s(two, "de"), at).kind, "change", "a switch");
    verify(OSDEngine.judge(def, "layout", s(two, "us"), s(["us", "fr"], "fr"), at) === null, "a new list: a reload");
    verify(OSDEngine.judge(def, "layout", s(two, "us"), s(two, "de", 4900), at) === null, "just after a focus change");
    compare(OSDEngine.judge(def, "layout", s(two, "us"), s(two, "de", 4900, 4950), at).show, "tile", "the user switched then too");
    verify(OSDEngine.judge(def, "layout", s(two, "us"), s(two, "de", 4900, 3000), at) === null, "an old switch doesn't count");
    compare(OSDEngine.judge(def, "layout", s(two, "us"), s(two, "de", 4000), at).show, "tile", "a full window before");
    compare(OSDEngine.judge(def, "layout", s(two, "us"), s(two, "de", 0), at).show, "tile", "never focused");
    def.destroy();
  }

  // takesIn: what a card out takes in without a card
  function test_takesIn() {
    const key = _def(`type: "A"`);
    const system = _def(`type: "B"; takesIn: "system"`);
    const shown = at("A", "x", true);
    verify(key.sameChange(shown, at("A", "x", false)), "its own key");
    verify(!key.sameChange(shown, at("A", "y", false)), "another key: no");
    verify(system.sameChange(shown, at("B", "y", false)), "\"system\": any key");
    verify(!system.sameChange(shown, at("B", "y", true)), "never a card");
    key.destroy();
    system.destroy();
  }

  // groups: owners on the tile, one card for one owner on two keys, the
  // group's role, a "still" card of the key kept; roles: the engine's
  // set card, its memory the change's members
  function test_groups_roles() {
    const def = _def(`
      type: "Caps"
      model: "set"
      onAdd: "card"
      onRemove: "still"
      anyone: true
      ownerField: "app"
      groups: [{ "keys": ["cam", "mic"], "role": "Both" }]
      exposes: [
        { "key": "cam", "part": "tile", "icon": "videocam", "roles": { "add": "Cam", "still": "Still cam", "stopped": "Stopped cam" } },
        { "key": "mic", "part": "tile", "icon": "mic", "roles": { "add": "Mic", "still": "Still mic", "stopped": "Stopped mic" } },
        { "key": "share", "part": "tile", "icon": "share", "roles": { "add": "Share", "still": "Still share", "stopped": "Stopped share" } }
      ]`);
    const set = apps => ({
          "members": apps.map((app, i) => ({
                "id": app + i,
                "app": app
              }))
        });
    compare(OSDEngine.tileOf(def, "cam", set(["V", "V"])).owners, ["V"], "a grouped key's owners, once each");
    verify(OSDEngine.tileOf(def, "share", set(["V"])).owners === undefined, "none outside a group");

    // A call app dropping the camera, keeping the microphone
    const after = {
      "cam": set([]),
      "mic": set(["V"])
    };
    const drop = OSDEngine.judge(def, "cam", set(["V"]), after.cam, {
      "after": after
    });
    compare([drop.kind, drop.show, drop.still, drop.kept], ["remove", "card", true, "mic"], "a still card of the key kept");
    compare(OSDEngine.cardOf(def, drop, after), {
      "icon": "mic",
      "image": "",
      "title": "V",
      "role": "Still mic",
      "detail": "",
      "tone": "",
      "clickable": false
    }, "naming the app, with the kept key's icon and role");
    const other = OSDEngine.judge(def, "cam", set(["V"]), set([]), {
      "after": {
        "cam": set([]),
        "mic": set(["O"])
      }
    });
    compare([other.show, other.still], ["tile", false], "another app on the other key: the icon");
    const alone = _def(`
      type: "Caps"
      model: "set"
      onRemove: "still"
      ownerField: "app"
      groups: [{ "keys": ["cam", "mic"], "role": "Both" }]
      exposes: [{ "key": "cam", "part": "tile" }]`);
    compare(OSDEngine.judge(alone, "cam", set(["V"]), set([]), {
      "after": after
    }).show, "tile", "the kept key not listed: the icon");
    alone.destroy();

    // The engine's set card, re-read from the state
    const add = OSDEngine.judge(def, "cam", set([]), set(["V"]), {});
    compare(add.members, set(["V"]).members, "an arrival remembers its members");
    compare(OSDEngine.cardOf(def, add, {
      "cam": set(["V"]),
      "mic": set([])
    }).role, "Cam", "alone: its own role");
    compare(OSDEngine.cardOf(def, add, {
      "cam": set(["V"]),
      "mic": set(["V"])
    }).role, "Both", "the other key held by its owner: the group's");
    const stopped = OSDEngine.cardOf(def, add, {
      "cam": set([]),
      "mic": set([])
    });
    compare([stopped.title, stopped.role], ["V", "Stopped cam"], "stopped under it: the members it came with");
    const still = OSDEngine.judge(def, "share", set(["A", "B"]), set(["A"]), {});
    compare(OSDEngine.cardOf(def, still, {
      "share": set(["A"])
    }).title, "A", "a still card names those left");
    compare(OSDEngine.cardOf(def, still, {
      "share": set(["A"])
    }).role, "Still share");

    // Arbitration: one owner on both is kept, another replaces
    const card = (key, apps) => Object.assign(at("Caps", key, true, {
        "owners": apps
      }), {
        "kind": "add"
      });
    const defs = {
      "Caps": def
    };
    compare(OSDEngine.arbitrate(card("cam", ["V"]), card("mic", ["V", "O"]), 300, defs), "keep", "an owner in common");
    compare(OSDEngine.arbitrate(card("cam", ["V"]), card("mic", ["O"]), 300, defs), "replace", "none in common");
    compare(OSDEngine.arbitrate(card("cam", ["V"]), card("mic", ["V"]), OSDEngine.quietWindow, defs), "replace", "past the window");
    const stillCard = Object.assign(card("share", ["A"]), {
      "kind": "remove",
      "still": true
    });
    compare(OSDEngine.arbitrate(stillCard, stillCard, 300, defs), "keep", "a still card after its own key's still card");
    def.destroy();
  }

  // A scalar group: matched by value (a headset's output and input)
  function test_groups_scalar() {
    const def = _def(`
      type: "Dev"
      onChange: "card"
      groups: [{ "keys": ["out", "in"], "role": "Both" }]
      exposes: [{ "key": "out", "part": "tile" }, { "key": "in", "part": "tile" }]
      function card(change, state) { return { "role": change.key }; }`);
    const change = {
      "key": "out",
      "kind": "change"
    };
    compare(OSDEngine.cardOf(def, change, {
      "out": {
        "value": "84"
      },
      "in": {
        "value": "84"
      }
    }).role, "Both", "the same device on both");
    compare(OSDEngine.cardOf(def, change, {
      "out": {
        "value": "84"
      },
      "in": {
        "value": "53"
      }
    }).role, "out", "another device: its own");
    compare(OSDEngine.cardOf(def, Object.assign({}, change, {
      "kind": "update"
    }), {
      "out": {
        "value": "84"
      },
      "in": {
        "value": "84"
      }
    }).role, "out", "not an arrival (a mute): its own");
    def.destroy();
  }

  function test_actionOf() {
    compare(toggle.actionOf("toggle", {}), {
      "id": "idleInhibit",
      "call": "toggle"
    });
    verify(audio.actionOf("audio", {}) === null, "none declared");
  }

  // carriesEvents and alertKinds: a radio's value and its devices' events
  // on one key
  function test_carriesEvents_alertKinds() {
    const def = Qt.createQmlObject(`
      import qs.components.surfaces.osd.engine
      OSDSystem {
        carriesEvents: true
        alertKinds: ["low"]
        exposes: [{ "key": "radio", "part": "tile" }]
        function tile(key, state) { return { "on": state.value === true }; }
      }`, this);
    const s = (value, kind, seq) => ({
          "value": value,
          "event": kind ? {
            "kind": kind
          } : null,
          "seq": seq
        });
    const first = OSDEngine.judge(def, "radio", s(true, null, 0), s(true, "connected", 1), {});
    compare([first.kind, first.show, first.alert], ["event", "card", false], "a new event: its card");
    const low = OSDEngine.judge(def, "radio", s(true, "connected", 1), s(true, "low", 2), {
      "byUser": true
    });
    compare([low.kind, low.alert], ["event", true], "an alert kind");
    verify(OSDEngine.opens({}, def, low, false), "an alert opens even the user's");
    const off = OSDEngine.judge(def, "radio", s(true, "connected", 1), s(false, "connected", 1), {});
    compare([off.kind, off.show], ["remove", "tile"], "the same seq: the value's own change");
    verify(OSDEngine.judge(def, "radio", s(true, "connected", 1), s(true, null, 1), {}) === null, "the event cleared: nothing");
    const both = OSDEngine.judge(def, "radio", s(false, null, 0), s(true, "connected", 1), {});
    compare(both.kind, "event", "an event and the value at once: the event");
    verify(!OSDEngine.showsWhileSettling(def, first), "a carried event waits out the settle window (maybe the service's last one)");
    def.destroy();
  }

  // The settle window: only an event model's events show in it (an
  // `axiom message` just after a start isn't lost)
  function test_showsWhileSettling() {
    const msg = OSDEngine.judge(message, "message", {
      "event": null,
      "seq": 0
    }, {
      "event": {
        "text": "hi"
      },
      "seq": 1
    }, {});
    compare(msg.kind, "event");
    verify(OSDEngine.showsWhileSettling(message, msg), "a pulsed event shows while settling");
    const on = OSDEngine.judge(toggle, "toggle", {
      "value": false
    }, {
      "value": true
    }, {});
    verify(on !== null);
    verify(!OSDEngine.showsWhileSettling(toggle, on), "a toggle's change only moves the state on");
    verify(!OSDEngine.showsWhileSettling(message, null), "no change");
  }

  // countsWithin: a level counts only just after the user's own set (a
  // set at the limit too, its time moving on), and such a key isn't held
  // by the settle window
  function test_countsWithin() {
    const def = _def(`
      type: "Light"
      countsWithin: ({ "after": "setAt", "ms": 500 })
      exposes: [{ "key": "light", "part": "bar" }]`);
    const s = (level, setAt) => ({
          "available": true,
          "level": level,
          "setAt": setAt
        });
    const at = ms => ({
          "at": ms
        });
    const limit = OSDEngine.judge(def, "light", s(1, 1000), s(1, 5000), at(5000));
    compare(limit?.kind, "level", "a set at its limit: the level unchanged, still a level");
    verify(OSDEngine.judge(def, "light", s(0.5, 0), s(0.8, 0), at(5000)) === null, "never set: a refresh's");
    verify(OSDEngine.judge(def, "light", s(0.5, 4000), s(0.8, 4000), at(4600)) === null, "past its window: idle dimming");
    compare(OSDEngine.judge(def, "light", s(0.5, 4000), s(0.8, 4000), at(4400))?.kind, "level", "within its window");
    verify(OSDEngine.showsWhileSettling(def, limit), "a key gating itself isn't held by the start settle");
    const plain = _def(`
      type: "Plain"
      exposes: [{ "key": "light", "part": "bar" }]`);
    const level = OSDEngine.judge(plain, "light", s(0.5, 0), s(0.8, 0), at(5000));
    verify(level !== null);
    verify(!OSDEngine.showsWhileSettling(plain, level), "an ordinary level waits out the settle window");
    def.destroy();
    plain.destroy();
  }

  // contextTile: a tile's or a card's own; a bar's its mark's tile (whose
  // device it is), none for a bar marked by itself
  function test_contextTile() {
    const def = _def(`
      type: "Sound"
      exposes: [{ "key": "master", "part": "bar", "mark": "audio" }, { "key": "solo", "part": "bar" }, { "key": "audio", "part": "tile" }]
      function tile(key, state) { return { "address": state?.address ?? "" }; }`);
    const state = {
      "master": {
        "level": 0.5
      },
      "solo": {
        "level": 0.5
      },
      "audio": {
        "value": "84",
        "address": "AA"
      }
    };
    compare(OSDEngine.contextTile(def, "audio", state).address, "AA", "a tile: its own");
    compare(OSDEngine.contextTile(def, "master", state).address, "AA", "a bar: its mark's");
    verify(OSDEngine.contextTile(def, "solo", state) === null, "a bar marked by itself: none");
    def.destroy();
  }

  // A look update's card never outranks the value going (a player
  // quitting while it plays); its icon still does (Wi-Fi off)
  function test_update_vs_removal() {
    const cardOnLook = _def(`
      type: "Player"
      onRemove: "none"
      onUpdate: "card"
      updateFields: []
      exposes: [{ "key": "media", "part": "card" }]
      function tile(key, state) { return { "on": !!state?.value && state?.playing === true }; }`);
    verify(OSDEngine.judge(cardOnLook, "media", {
      "value": "Song",
      "playing": true
    }, {
      "value": "",
      "playing": false
    }, {}) === null, "quit while playing: no card");
    compare(OSDEngine.judge(cardOnLook, "media", {
      "value": "Song",
      "playing": true
    }, {
      "value": "Song",
      "playing": false
    }, {})?.show, "card", "paused: its card");
    const iconOnLook = _def(`
      type: "Radio"
      onRemove: "none"
      exposes: [{ "key": "radio", "part": "tile" }]
      function tile(key, state) { return { "on": state?.on === true }; }`);
    compare(OSDEngine.judge(iconOnLook, "radio", {
      "on": true,
      "value": true
    }, {
      "on": false,
      "value": false
    }, {})?.show, "tile", "off and left: the icon outranks the removal's nothing");
    cardOnLook.destroy();
    iconOnLook.destroy();
  }

  // memberState: a set judged by a member field across transit, and the
  // "last" removal policy
  function test_memberState_last() {
    const def = Qt.createQmlObject(`
      import qs.components.surfaces.osd.engine
      OSDSystem {
        model: "set"
        memberState: ({ "field": "state", "on": "on", "off": "off" })
        onAdd: "card"
        onUnexpectedRemove: "last"
        exposes: [{ "key": "vpn", "part": "tile" }]
      }`, this);
    // { id: state }
    const set = states => ({
          "members": Object.keys(states).map(id => ({
                "id": id,
                "state": states[id]
              }))
        });
    // Each step judged against what the watcher remembers
    let last = {};
    const step = (state, ctx) => {
      const what = OSDEngine.judge(def, "vpn", last.vpn, state, ctx ?? {});
      last = OSDEngine.remember(def, last, {
        "vpn": state
      });
      return what;
    };
    verify(step(set({
      "a": "off"
    })) === null, "the first reading");
    verify(step(set({
      "a": "connecting"
    })) === null, "in transit: nothing");
    compare(last.vpn.members[0].state, "off", "remembered as it settled");
    const up = step(set({
      "a": "on"
    }));
    compare([up.kind, up.show, up.added], ["add", "card", ["a"]], "up across connecting");
    verify(step(set({
      "a": "on",
      "b": "on"
    })) === null, "one appearing up: nothing");
    verify(step(set({
      "a": "on",
      "c": "connecting"
    })) === null, "one going, one appearing in transit: nothing");
    verify(step(set({
      "a": "on",
      "c": "on"
    })) === null, "never settled before: not known");
    const half = step(set({
      "a": "off",
      "c": "on"
    }));
    compare([half.kind, half.show, half.left], ["remove", "tile", ["c"]], "unexpected with another up: the icon (last)");
    const drop = step(set({
      "a": "off",
      "c": "off"
    }));
    compare([drop.kind, drop.show, drop.unexpected, drop.left], ["remove", "card", true, []], "the last one dropping: its card");
    step(set({
      "a": "on",
      "c": "off"
    }));
    const mine = step(set({
      "a": "off",
      "c": "off"
    }), {
      "byUser": true
    });
    compare(mine.show, "tile", "taken down on screen: onRemove's icon");
    def.destroy();
  }
}

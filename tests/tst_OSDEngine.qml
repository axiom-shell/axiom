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

  readonly property var defs: ({
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
        exposes: [{ "key": "odd", "part": "tile" }]
        function judge(before, after, ctx) {
          if (ctx.key !== "odd")
            return undefined;
          return after.value === "skip" ? null : { "kind": "change", "show": "card", "why": ctx.before.other };
        }
      }`, this);
    verify(OSDEngine.judge(own, "odd", {
      "value": 1
    }, {
      "value": "skip"
    }, {}) === null, "its own nothing");
    const card = OSDEngine.judge(own, "odd", undefined, {
      "value": 2
    }, {
      "before": {
        "other": "x"
      }
    });
    compare([card.show, card.card, card.why], ["card", true, "x"], "even a first reading, as it says");
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

  function test_actionOf() {
    compare(toggle.actionOf("toggle", {}), {
      "id": "idleInhibit",
      "call": "toggle"
    });
    verify(audio.actionOf("audio", {}) === null, "none declared");
  }
}

import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "OSDItems"

  function test_lockKeyChanged() {
    const off = {
      "available": true,
      "caps": false,
      "num": true,
      "scroll": false
    };
    const capsOn = Object.assign({}, off, {
      "caps": true
    });
    verify(OSDItems.lockKeyChanged(off, capsOn, "caps"));
    verify(OSDItems.lockKeyChanged(capsOn, off, "caps"));
    verify(!OSDItems.lockKeyChanged(off, capsOn, "num"), "another key");
    verify(!OSDItems.lockKeyChanged(null, capsOn, "caps"), "the first reading");
    verify(!OSDItems.lockKeyChanged(Object.assign({}, off, {
      "available": false
    }), capsOn, "caps"), "the LEDs appearing");
    compare(OSDItems.lockKeys.capsLock, "caps");
  }

  function test_layoutSwitched() {
    const two = ["us", "de"];
    verify(OSDItems.layoutSwitched({
      "layouts": two,
      "index": 0
    }, {
      "layouts": ["us", "de"],
      "index": 1
    }));
    verify(!OSDItems.layoutSwitched({
      "layouts": two,
      "index": 0
    }, {
      "layouts": two,
      "index": 0
    }), "the same layout");
    verify(!OSDItems.layoutSwitched({
      "layouts": two,
      "index": 0
    }, {
      "layouts": ["us", "fr"],
      "index": 1
    }), "a new list is a config reload");
    verify(!OSDItems.layoutSwitched({
      "layouts": [],
      "index": 0
    }, {
      "layouts": two,
      "index": 1
    }), "the first reading");
    verify(!OSDItems.layoutSwitched({
      "layouts": ["us"],
      "index": 0
    }, {
      "layouts": ["us"],
      "index": 0
    }), "one layout never shows");
    verify(!OSDItems.layoutSwitched(null, {
      "layouts": two,
      "index": 1
    }));
  }

  function test_tile() {
    const caps = OSDItems.tile("capsLock", {
      "available": true,
      "on": true
    });
    compare([caps.icon, caps.on, caps.slash, caps.notable, caps.hidden], ["keyboard_capslock", true, false, true, false]);
    const capsOff = OSDItems.tile("capsLock", {
      "available": true,
      "on": false
    });
    compare([capsOff.on, capsOff.slash, capsOff.notable], [false, false, false], "off: unlit, only a mute is struck through");
    verify(OSDItems.tile("numLock", {
      "available": true,
      "on": true
    }).notable, "Num Lock on is unusual, as Caps Lock is");
    verify(OSDItems.tile("scrollLock", {
      "available": false,
      "on": false
    }).hidden, "no LEDs");

    const layout = OSDItems.tile("keyboardLayout", {
      "layouts": ["us", "de"],
      "index": 1
    });
    compare([layout.label, layout.notable, layout.hidden], ["DE", true, false], "its code, unusual past the first");
    verify(!OSDItems.tile("keyboardLayout", {
      "layouts": ["us", "de"],
      "index": 0
    }).notable);
    verify(OSDItems.tile("keyboardLayout", {
      "layouts": ["us"],
      "index": 0
    }).hidden, "one layout");

    const muted = OSDItems.tile("microphone", {
      "muted": true,
      "icon": "",
      "device": "44"
    });
    compare([muted.icon, muted.on, muted.slash, muted.notable], ["mic", false, true, true], "the base icon, struck through");
    compare(OSDItems.tile("microphone", {
      "muted": false,
      "icon": "headset_mic",
      "device": "44"
    }).icon, "headset_mic", "the device's own icon");

    const device = OSDItems.tile("audio", {
      "muted": false,
      "name": "AudioBox Go",
      "detail": "Analog Stereo",
      "icon": "",
      "device": "44"
    });
    compare([device.icon, device.name, device.detail, device.device, device.on, device.slash, device.notable, device.hidden], ["volume_up", "AudioBox Go", "Analog Stereo", "44", true, false, false, false], "lit");
    compare([OSDItems.tile("audio", {
        "muted": true,
        "device": "44"
      }).slash, OSDItems.tile("audio", {
        "muted": true,
        "device": "44"
      }).notable], [true, true], "the output muted, struck through");
    verify(OSDItems.tile("microphone", {}).hidden, "no device");

    compare(OSDItems.tile("powerProfile", {
      "profile": "powerSaver"
    }).icon, "energy_savings_leaf");
    verify(OSDItems.tile("powerProfile", {
      "profile": "performance"
    }).notable);
    verify(!OSDItems.tile("powerProfile", {
      "profile": "balanced"
    }).notable);
    verify(OSDItems.tile("powerProfile", {
      "profile": ""
    }).hidden, "no profiles daemon");

    verify(OSDItems.tile("charger", {
      "available": true,
      "plugged": false
    }).notable, "on battery");
    verify(OSDItems.tile("charger", {
      "available": false,
      "plugged": true
    }).hidden, "no battery");

    const dnd = OSDItems.tile("dnd", {
      "on": true
    });
    compare([dnd.icon, dnd.on, dnd.slash, dnd.notable], ["do_not_disturb_on", true, false, true]);
    const dndOff = OSDItems.tile("dnd", {
      "on": false
    });
    compare([dndOff.icon, dndOff.on, dndOff.slash], ["do_not_disturb_on", false, false], "off: the same icon, unlit");
    verify(OSDItems.tile("wifi", {
      "available": true,
      "on": false
    }).notable, "Wi-Fi off is unusual");
    verify(!OSDItems.tile("wifi", {
      "available": true,
      "on": true
    }).notable);
    verify(!OSDItems.tile("bluetooth", {
      "on": false
    }).notable, "Bluetooth either way is ordinary");
    verify(OSDItems.tile("wifi", {
      "available": false,
      "on": false
    }).hidden);

    const message = OSDItems.tile("message", {
      "icon": "",
      "text": "Saved"
    });
    compare([message.icon, message.name, message.detail, message.tone, message.hidden], ["chat", "Saved", "", "", false]);
    const refusal = OSDItems.tile("message", {
      "icon": "nightlight",
      "text": "Night light",
      "detail": "Not available here",
      "tone": "warning"
    });
    compare([refusal.name, refusal.detail, refusal.tone], ["Night light", "Not available here", "warning"], "a refusal");
    const card = OSDItems.card("message", {
      "message": refusal
    }, []);
    compare([card.icon, card.title, card.role, card.detail, card.tone], ["nightlight", "Night light", "", "Not available here", "warning"], "its card, its two lines");
    verify(OSDItems.alwaysCard("message"));
    verify(!OSDItems.alwaysCard("audio"), "the others follow the OSD's detail cards");
    verify(OSDItems.tile("message", {}).hidden, "none yet");
    verify(OSDItems.tile("bogus", {}).hidden);
  }

  function test_cardRoute_data() {
    const osd = (items, quiet, cards, enabled) => ({
          "enabled": enabled !== false,
          "statuses": {
            "items": items,
            "quiet": quiet,
            "cards": cards
          }
        });
    return [
      {
        "tag": "listed: its card",
        "osds": [osd(["drive"], [], true)],
        "notify": true,
        "want": "osd"
      },
      {
        "tag": "not listed: a notification",
        "osds": [osd(["audio"], [], true)],
        "notify": true,
        "want": "notification"
      },
      {
        "tag": "not listed, notify off: nowhere",
        "osds": [osd(["audio"], [], true)],
        "notify": false,
        "want": ""
      },
      {
        "tag": "quiet: never opens it, so a notification",
        "osds": [osd(["drive"], ["drive"], true)],
        "notify": true,
        "want": "notification"
      },
      {
        "tag": "quiet, notify off: nowhere",
        "osds": [osd(["drive"], ["drive"], true)],
        "notify": false,
        "want": ""
      },
      {
        "tag": "detail cards off: a notification",
        "osds": [osd(["drive"], [], false)],
        "notify": true,
        "want": "notification"
      },
      {
        "tag": "a disabled OSD: a notification",
        "osds": [osd(["drive"], [], true, false)],
        "notify": true,
        "want": "notification"
      },
      {
        "tag": "any one OSD showing it is enough",
        "osds": [osd(["drive"], ["drive"], true), osd(["drive"], [], true)],
        "notify": true,
        "want": "osd"
      }
    ];
  }

  function test_cardRoute(row) {
    compare(OSDItems.cardRoute(row.osds, "drive", row.notify), row.want);
  }

  function test_opensCard_message() {
    const osd = (quiet, cards) => ({
          "enabled": true,
          "statuses": {
            "items": [],
            "quiet": quiet,
            "cards": cards
          }
        });
    verify(OSDItems.opensCard(osd([], false), "message"), "a message is its card, detail cards or not, listed or not");
    verify(!OSDItems.opensCard(osd(["message"], true), "message"), "quiet: a notification instead");
    verify(!OSDItems.opensCard(null, "message"), "no OSD");
  }

  function test_tile_base_icons() {
    // Off is the base icon unlit (a mute struck through), never an icon's
    // own off form, so every one looks the same
    const types = ["capsLock", "numLock", "scrollLock", "keyboardLayout", "audio", "microphone", "powerProfile", "caffeine", "dnd", "nightLight", "wifi", "bluetooth", "airplane", "charger", "message", "vpn", "drive", "battery", "monitor", "screenshot", "recording", "camera", "micUse", "screenShare"];
    for (const type of types) {
      for (const on of [true, false]) {
        const t = OSDItems.tile(type, {
          "available": true,
          "on": on,
          "muted": !on,
          "plugged": on,
          "profile": "balanced",
          "layouts": ["us", "de"],
          "index": 0,
          "text": "x",
          "apps": on ? ["Firefox"] : []
        });
        verify(!/_(off|disabled|inactive)$/.test(t.icon), `${type} ${on}: ${t.icon}`);
      }
    }
  }

  function test_tile_drive() {
    const mounted = OSDItems.tile("drive", {
      "available": true,
      "count": 1,
      "event": {
        "kind": "mounted",
        "name": "STICK",
        "mountPoint": "/run/media/u/STICK"
      }
    });
    verify(mounted.on && !mounted.hidden && !mounted.slash && mounted.notable, "a drive in: shown, unusual");
    compare(mounted.name, "STICK");
    let card = OSDItems.card("drive", {
      "drive": mounted
    }, ["drive"]);
    compare([card.icon, card.title, card.role, card.detail], ["usb", "STICK", "Mounted", "/run/media/u/STICK"]);
    verify(card.clickable, "a drive's card takes a click");
    const ejected = OSDItems.tile("drive", {
      "available": true,
      "count": 0,
      "event": {
        "kind": "ejected",
        "name": "STICK",
        "mountPoint": ""
      }
    });
    verify(ejected.hidden, "none left: shown only as it changes");
    card = OSDItems.card("drive", {
      "drive": ejected
    }, ["drive"]);
    compare([card.icon, card.role, card.detail], ["eject", "Safe to remove", ""]);
    card = OSDItems.card("drive", {
      "drive": OSDItems.tile("drive", {
        "available": true,
        "count": 1,
        "event": {
          "kind": "added",
          "name": "SD",
          "mountPoint": ""
        }
      })
    }, ["drive"]);
    compare(card.role, "Connected", "plugged in");
    const looks = [["locked", "lock", "Encrypted: click to unlock"], ["unmounted", "usb", "Unmounted"], ["removed", "usb_off", "Disconnected"], ["pulled", "warning", "Unplugged without ejecting"], ["busy", "warning", "In use: close what's using it"], ["ejectFailed", "warning", "Couldn't eject"]];
    for (const [kind, icon, role] of looks) {
      card = OSDItems.card("drive", {
        "drive": OSDItems.tile("drive", {
          "available": true,
          "count": 0,
          "event": {
            "kind": kind,
            "name": "STICK",
            "mountPoint": ""
          }
        })
      }, ["drive"]);
      compare([card.icon, card.title, card.role, card.detail], [icon, "STICK", role, ""], kind);
    }
    verify(OSDItems.tile("drive", {
      "available": false,
      "count": 1
    }).hidden, "no udisks2");
    verify(OSDItems.tile("drive", null).hidden, "no state yet");
  }

  function test_tile_battery() {
    const low = OSDItems.tile("battery", {
      "available": true,
      "level": "low",
      "percent": 18,
      "timeLeft": "1h 5m"
    });
    verify(low.on && low.notable && !low.hidden, "low: lit and unusual");
    compare(low.icon, "battery_low");
    let card = OSDItems.card("battery", {
      "battery": low
    }, ["battery"]);
    compare([card.icon, card.title, card.role, card.detail, card.tone, card.clickable], ["battery_low", "18%", "Battery low", "1h 5m", "", false]);
    const critical = OSDItems.tile("battery", {
      "available": true,
      "level": "critical",
      "percent": 6,
      "timeLeft": ""
    });
    verify(critical.notable, "critical is unusual");
    card = OSDItems.card("battery", {
      "battery": critical
    }, ["battery"]);
    compare([card.icon, card.role, card.detail, card.tone], ["battery_alert", "Battery critically low", "", "warning"]);
    const fine = OSDItems.tile("battery", {
      "available": true,
      "level": "none",
      "percent": 80
    });
    verify(!fine.on && !fine.notable && !fine.hidden, "fine: shown unlit");
    verify(OSDItems.tile("battery", {
      "available": false
    }).hidden, "no battery");
    verify(OSDItems.tile("battery", null).hidden, "no state yet");
  }

  function test_tile_monitor() {
    const added = OSDItems.tile("monitor", {
      "event": {
        "kind": "added",
        "name": "DP-1",
        "description": "Dell U2720Q",
        "width": 3840,
        "height": 2160
      }
    });
    verify(added.hidden && !added.notable, "only ever its card, never unusual");
    let card = OSDItems.card("monitor", {
      "monitor": added
    }, ["monitor"]);
    compare([card.icon, card.title, card.role, card.detail, card.clickable], ["monitor", "Dell U2720Q", "Connected", "DP-1 · 3840×2160", false]);
    card = OSDItems.card("monitor", {
      "monitor": OSDItems.tile("monitor", {
        "event": {
          "kind": "removed",
          "name": "HDMI-A-1",
          "description": "",
          "width": 1920,
          "height": 1080
        }
      })
    }, ["monitor"]);
    compare([card.icon, card.title, card.role, card.detail], ["desktop_access_disabled", "HDMI-A-1", "Disconnected", "1920×1080"], "no description: named by its connector, once");
    compare(OSDItems.card("monitor", {
      "monitor": OSDItems.tile("monitor", null)
    }, ["monitor"]).detail, "", "no event yet");
  }

  function test_tile_screenshot() {
    const shot = OSDItems.tile("screenshot", {
      "event": {
        "path": "/home/u/Pictures/Screenshots/a.png",
        "title": "Screenshot saved",
        "folder": "~/Pictures/Screenshots"
      }
    });
    verify(shot.hidden && !shot.notable, "only ever its card");
    const card = OSDItems.card("screenshot", {
      "screenshot": shot
    }, ["screenshot"]);
    compare([card.icon, card.title, card.role, card.detail, card.image], ["screenshot_monitor", "Screenshot saved", "Copied to the clipboard", "~/Pictures/Screenshots", "file:///home/u/Pictures/Screenshots/a.png"]);
    verify(card.clickable, "a screenshot's card opens it");
    compare(OSDItems.card("screenshot", {}, ["screenshot"]).image, "", "no picture yet");
    compare(OSDItems.card("drive", {}, ["drive"]).image, "", "no picture but a screenshot's");
  }

  function test_tile_vpn_capture() {
    const up = OSDItems.tile("vpn", {
      "available": true,
      "on": true,
      "name": "Home"
    });
    verify(up.on && up.notable && !up.slash && !up.hidden);
    compare(up.name, "Home");
    const down = OSDItems.tile("vpn", {
      "available": true,
      "on": false,
      "name": "Home"
    });
    verify(!down.on && !down.slash && !down.notable);
    compare(down.name, "", "no name while down: the tooltip says off");
    verify(OSDItems.tile("vpn", {
      "available": false
    }).hidden, "no NetworkManager");

    const rec = OSDItems.tile("recording", {
      "available": true,
      "on": true
    });
    verify(rec.on && rec.notable);
    verify(OSDItems.tile("recording", {
      "available": false,
      "on": false
    }).hidden, "no recorder");

    const cam = OSDItems.tile("camera", {
      "apps": ["Firefox", "OBS"]
    });
    verify(cam.on && cam.notable);
    compare(cam.icon, "videocam");
    compare(cam.name, "Firefox, OBS");
    const share = OSDItems.tile("screenShare", {
      "apps": []
    });
    verify(!share.on && !share.slash && !share.notable && !share.hidden);
    compare(share.icon, "screen_share");
  }

  function test_tile_names() {
    compare(OSDItems.tile("wifi", {
      "available": true,
      "on": true,
      "network": "Home"
    }).name, "Home", "Wi-Fi names the network joined");
    compare(OSDItems.tile("wifi", {
      "available": true,
      "on": false,
      "network": "Home"
    }).name ?? "", "", "never while off (its tooltip would read muted)");
    compare(OSDItems.tile("charger", {
      "available": true,
      "plugged": true,
      "percent": 64
    }).name, "64%");
    compare(OSDItems.tile("charger", {
      "available": true,
      "plugged": false,
      "percent": 64
    }).name, "", "on battery: the struck-through plug alone");
  }

  function test_call() {
    const call = {
      "camera": OSDItems.tile("camera", {
        "apps": ["Vesktop"]
      }),
      "micUse": OSDItems.tile("micUse", {
        "apps": ["Vesktop", "OBS"]
      })
    };
    const types = ["camera", "micUse"];
    compare(OSDItems.card("camera", call, types).role, "Using the camera and microphone");
    compare(OSDItems.card("micUse", call, types).role, "Using the camera and microphone", "whichever came first");
    compare(OSDItems.card("camera", call, ["camera"]).role, "Using the camera", "no microphone status");
    const apart = {
      "camera": call.camera,
      "micUse": OSDItems.tile("micUse", {
        "apps": ["OBS"]
      })
    };
    compare(OSDItems.card("micUse", apart, types).role, "Using the microphone", "another app");
    compare(OSDItems.card("micUse", apart, types).icon, "record_voice_over");

    verify(!OSDItems.replaces("camera", "micUse", 300, call, true, true), "one app taking both: one card");
    verify(!OSDItems.replaces("micUse", "camera", 300, call, true, true), "either order");
    verify(OSDItems.replaces("camera", "micUse", 300, apart, true, true), "another app's microphone");
    verify(OSDItems.replaces("camera", "micUse", OSDItems.quietWindow, call, true, true), "later");
  }

  function test_vpnStep() {
    let step = OSDItems.vpnStep(null, {
      "a": "off",
      "tailscale": "connecting"
    });
    verify(!step.changed, "the first reading");
    compare(JSON.stringify(step.last), JSON.stringify({
      "a": "off"
    }), "only settled states are kept");
    step = OSDItems.vpnStep(step.last, {
      "a": "connecting",
      "tailscale": "on"
    });
    verify(!step.changed, "on its way, and a row settling for the first time");
    compare(step.last.a, "off", "the settled state is kept through connecting");
    step = OSDItems.vpnStep(step.last, {
      "a": "on",
      "tailscale": "on"
    });
    verify(step.changed && step.up, "up, through connecting: its card");
    step = OSDItems.vpnStep(step.last, {
      "a": "off",
      "tailscale": "on"
    });
    verify(step.changed && !step.up, "a drop: no card");
    step = OSDItems.vpnStep(step.last, {
      "a": "disconnecting"
    });
    verify(!step.changed, "a row going away");
    compare(step.last.tailscale, undefined, "is forgotten");
    step = OSDItems.vpnStep(step.last, {
      "a": "off",
      "tailscale": "on"
    });
    verify(!step.changed, "back where it was, and a row appearing again");
  }

  function test_captureChange() {
    compare(OSDItems.captureChange([], [61]), "started");
    compare(OSDItems.captureChange([61], [61, 74]), "started", "another stream");
    compare(OSDItems.captureChange([61, 74], [61]), "", "one of two stopping");
    compare(OSDItems.captureChange([61], [61]), "", "the same stream (its name read late)");
    compare(OSDItems.captureChange([61], []), "stopped");
    compare(OSDItems.captureChange([], []), "");
  }

  function test_rowTypes() {
    const types = ["capsLock", "numLock", "dnd", "wifi", "message"];
    const tiles = {
      "capsLock": OSDItems.tile("capsLock", {
        "available": true,
        "on": true
      }),
      "numLock": OSDItems.tile("numLock", {
        "available": true,
        "on": true
      }),
      "dnd": OSDItems.tile("dnd", {
        "on": false
      }),
      "wifi": OSDItems.tile("wifi", {
        "available": false
      }),
      "message": OSDItems.tile("message", {
        "text": "Hi"
      })
    };
    compare(OSDItems.rowTypes(types, tiles, "notable", []), ["capsLock", "numLock"], "the lock keys on");
    compare(OSDItems.rowTypes(types, tiles, "notable", ["dnd"]), ["capsLock", "numLock", "dnd"], "the change, in its place");
    compare(OSDItems.rowTypes(types, tiles, "notable", ["wifi"]), ["capsLock", "numLock", "wifi"], "a hidden one as it changes");
    compare(OSDItems.rowTypes(types, tiles, "all", []), ["capsLock", "numLock", "dnd"], "not hidden ones, nor a message");
    compare(OSDItems.rowTypes(types, tiles, "all", ["message"]), ["capsLock", "numLock", "dnd"], "a message is a card, never a tile");
    compare(OSDItems.rowTypes(types, tiles, "changed", ["numLock"]), ["numLock"]);
    compare(OSDItems.rowTypes(types, tiles, "changed", ["dnd", "numLock"]), ["numLock", "dnd"], "every one kept, in the OSD's order");
    compare(OSDItems.rowTypes(types, tiles, "changed", []), []);
    compare(OSDItems.rowTypes([], tiles, "all", []), []);
  }

  function test_replaces() {
    verify(OSDItems.replaces("", "wifi", 0));
    verify(OSDItems.replaces("capsLock", "wifi", 0));
    verify(!OSDItems.replaces("airplane", "wifi", 300), "airplane mode switching the radio");
    verify(!OSDItems.replaces("airplane", "bluetooth", 1999));
    verify(OSDItems.replaces("airplane", "bluetooth", OSDItems.quietWindow), "the user's own toggle later");
    verify(OSDItems.replaces("wifi", "airplane", 0), "airplane mode always shows");
    verify(OSDItems.replaces("airplane", "capsLock", 0));
    verify(!OSDItems.replaces("message", "capsLock", 300, {}, true, false), "a message's card stays to be read");
    verify(OSDItems.replaces("message", "message", 300, {}, true, true), "another message");
    verify(OSDItems.replaces("message", "audio", 300, {}, true, true), "another card");
    verify(OSDItems.replaces("message", "capsLock", OSDItems.quietWindow, {}, true, false), "later");

    const headset = {
      "audio": OSDItems.tile("audio", {
        "device": "60"
      }),
      "microphone": OSDItems.tile("microphone", {
        "device": "60"
      })
    };
    verify(!OSDItems.replaces("audio", "microphone", 300, headset, true, true), "a headset taking both: one change");
    verify(!OSDItems.replaces("microphone", "audio", 300, headset, true, true), "either order");
    verify(OSDItems.replaces("audio", "microphone", OSDItems.quietWindow, headset, true, true), "the user's own switch later");
    verify(OSDItems.replaces("audio", "audio", 300, headset, true, true), "the output switching again");
    const apart = {
      "audio": headset.audio,
      "microphone": OSDItems.tile("microphone", {
        "device": "52"
      })
    };
    verify(OSDItems.replaces("audio", "microphone", 300, apart, true, true), "another device");
    verify(OSDItems.replaces("audio", "microphone", 300, undefined, true, true), "no tiles");
    verify(!OSDItems.replaces("microphone", "microphone", 300, apart, true, false), "the new input's mute coming in");
    verify(!OSDItems.replaces("audio", "microphone", 300, headset, true, false), "a headset's mute coming in");
    verify(OSDItems.replaces("microphone", "microphone", OSDItems.quietWindow, apart, true, false), "the user's own mute later");
    verify(OSDItems.replaces("microphone", "microphone", 300, apart, false, true), "a switch after a mute shows");
    verify(OSDItems.replaces("audio", "microphone", 300, headset, false, false), "mutes one after another");

    // Every card keeps its place against its own status's follow-up
    const vpnUp = {
      "vpn": OSDItems.tile("vpn", {
        "available": true,
        "on": true
      })
    };
    const vpnDown = {
      "vpn": OSDItems.tile("vpn", {
        "available": true,
        "on": false
      })
    };
    verify(!OSDItems.replaces("vpn", "vpn", 300, vpnUp, true, false), "the other half of a VPN switch");
    verify(OSDItems.replaces("vpn", "vpn", 300, vpnUp, true, true), "another VPN up");
    verify(OSDItems.replaces("vpn", "vpn", OSDItems.quietWindow, vpnUp, true, false), "a drop later");
    verify(OSDItems.replaces("vpn", "vpn", 300, vpnDown, true, false), "a drop just after: the card would say Connected");
    verify(OSDItems.replaces("charger", "charger", 300, {
      "charger": OSDItems.tile("charger", {
        "available": true,
        "plugged": false
      })
    }, true, false), "unplugged just after: the card would say Plugged in");
    verify(OSDItems.replaces("wifi", "wifi", 300, {
      "wifi": OSDItems.tile("wifi", {
        "on": false
      })
    }, true, false), "Wi-Fi off just after joining");
    verify(!OSDItems.replaces("wifi", "wifi", 300, {
      "wifi": OSDItems.tile("wifi", {
        "on": true,
        "network": "home"
      })
    }, true, false), "Wi-Fi still on");
    verify(!OSDItems.replaces("camera", "camera", 300, {}, true, false), "a capture stopping as it starts");
    verify(OSDItems.replaces("camera", "microphone", 300, headset, true, false), "a capture's card isn't a device switch");
    verify(OSDItems.replaces("camera", "screenShare", 300, {}, true, true), "another capture's card");
  }

  function test_card() {
    verify(OSDItems.card("dnd", {}, ["dnd"]) === null, "no card");
    verify(OSDItems.card("", {}, []) === null, "none shown yet");
    const headset = {
      "audio": OSDItems.tile("audio", {
        "device": "60",
        "name": "Headset",
        "detail": "Analog Stereo",
        "icon": "headset"
      }),
      "microphone": OSDItems.tile("microphone", {
        "device": "60"
      })
    };
    const both = OSDItems.card("audio", headset, ["audio", "microphone"]);
    compare(both.role, "Output and input");
    compare(both.title, "Headset");
    compare(both.detail, "Analog Stereo");
    compare(both.icon, "headset");
    compare(OSDItems.card("audio", headset, ["audio"]).role, "Output", "the other status left out of the OSD (a stale tile)");
    compare(OSDItems.card("microphone", {
      "microphone": headset.microphone
    }, ["microphone"]).role, "Input");

    const vpn = OSDItems.card("vpn", {
      "vpn": OSDItems.tile("vpn", {
        "available": true,
        "on": true,
        "name": "Tailnet",
        "address": "100.64.0.1"
      })
    }, ["vpn"]);
    compare(vpn.title, "Tailnet");
    compare(vpn.role, "Connected");
    compare(vpn.detail, "100.64.0.1");
    compare(vpn.icon, "vpn_key");

    const cam = OSDItems.card("camera", {
      "camera": OSDItems.tile("camera", {
        "apps": ["Firefox"]
      })
    }, ["camera"]);
    compare(cam.title, "Firefox");
    compare(cam.role, "Using the camera");
    compare(OSDItems.card("screenShare", {}, ["screenShare"]).role, "Sharing the screen", "no tile yet");
    verify(!OSDItems.card("screenShare", {}, ["screenShare"]).clickable, "only a drive's and a screenshot's cards take a click");
    const stopped = OSDItems.card("screenShare", {
      "screenShare": OSDItems.tile("screenShare", {
        "apps": [],
        "last": ["Vesktop"]
      })
    }, ["screenShare"]);
    compare(stopped.title, "Vesktop", "a preview stream stopped under its card: still named");
    compare(stopped.role, "Stopped sharing the screen");
    const sharing = OSDItems.card("screenShare", {
      "screenShare": OSDItems.tile("screenShare", {
        "apps": ["Firefox"],
        "last": ["Vesktop"]
      })
    }, ["screenShare"]);
    compare(sharing.title, "Firefox", "the apps sharing now, not the last ones");
    compare(sharing.role, "Sharing the screen");
    compare(OSDItems.card("micUse", {
      "micUse": OSDItems.tile("micUse", {
        "last": ["Vesktop"]
      })
    }, ["micUse"]).role, "Stopped using the microphone");
    const charging = OSDItems.card("charger", {
      "charger": OSDItems.tile("charger", {
        "available": true,
        "plugged": true,
        "percent": 64,
        "charging": true,
        "untilFull": "1h 20m"
      })
    }, ["charger"]);
    compare(charging.title, "64%");
    compare(charging.role, "Charging");
    compare(charging.detail, "1h 20m");
    const full = OSDItems.card("charger", {
      "charger": OSDItems.tile("charger", {
        "available": true,
        "plugged": true,
        "percent": 100,
        "full": true,
        "untilFull": "0m"
      })
    }, ["charger"]);
    compare(full.role, "Fully charged");
    compare(full.detail, "", "nothing left to full");
    compare(OSDItems.card("charger", {
      "charger": OSDItems.tile("charger", {
        "available": true,
        "plugged": true,
        "percent": 80
      })
    }, ["charger"]).role, "Plugged in", "not charging yet");

    const home = OSDItems.card("wifi", {
      "wifi": OSDItems.tile("wifi", {
        "available": true,
        "on": true,
        "network": "Home",
        "signal": 72
      })
    }, ["wifi"]);
    compare(home.title, "Home");
    compare(home.role, "Connected");
    compare(home.detail, "72%");
    compare(OSDItems.card("wifi", {
      "wifi": OSDItems.tile("wifi", {
        "available": true,
        "on": true,
        "network": ""
      })
    }, ["wifi"]).detail, "", "its name not in yet: no signal either");

    for (const type of OSDItems.cardTypes)
      verify(OSDItems.card(type, {}, [type]) !== null, type);
  }

  function test_fromScreen() {
    const rows = [
      // [type, elapsed, from the pointer, what]
      ["master", 500, true, "the output's bar: the audio mark"], ["app", 500, true, "an app's bar: the audio mark"], ["microphone", 1999, true, "inside the window"], ["microphone", 2000, false, "past it"], ["caffeine", Infinity, false, "never marked"], ["vpn", 10000, true, "a VPN settles slowly"], ["wifi", 9000, false, "past Wi-Fi's window"], ["dnd", -5, false, "a mark from the future (clock change)"]];
    for (const [type, elapsed, want, what] of rows)
      compare(OSDItems.fromScreen(type, elapsed), want, what);
    compare(OSDItems.onScreenKind("other"), "audio");
    compare(OSDItems.onScreenKind("brightness"), "brightness");
  }

  function test_deviceName() {
    const rows = [
      // [device, title, detail, translate, what]
      [
        {
          "nick": "CU34G4Z",
          "description": "Navi 31 HDMI/DP Audio Digital Stereo (HDMI) [CU34G4Z]",
          "profile": "Digital Stereo (HDMI)",
          "bus": "pci",
          "kind": "hdmi"
        },
        "CU34G4Z", "Digital Stereo (HDMI)", false, "a monitor by its model"], [
        {
          "nick": "AudioBox Go",
          "description": "AudioBox Go Analog Stereo",
          "profile": "Analog Stereo",
          "bus": "usb",
          "kind": "speaker"
        },
        "AudioBox Go", "Analog Stereo", false, "a USB interface"], [
        {
          "nick": "EMEET SmartCam C960",
          "description": "EMEET SmartCam C960 Mono",
          "profile": "Mono",
          "bus": "usb",
          "kind": "webcam"
        },
        "EMEET SmartCam C960", "Mono", false, "a webcam"], [
        {
          "description": "Easy Effects Sink"
        },
        "Easy Effects Sink", "", false, "a virtual sink"], [
        {
          "nick": "HD-Audio Generic",
          "description": "Family 17h/19h HD Audio Controller Analog Stereo",
          "profile": "Analog Stereo",
          "bus": "pci",
          "kind": "speaker"
        },
        "Speakers", "Analog Stereo", true, "a sound chip: its kind"], [
        {
          "nick": "HD-Audio Generic",
          "description": "Some USB Thing Analog Stereo",
          "profile": "Analog Stereo",
          "bus": "usb",
          "kind": "speaker"
        },
        "Some USB Thing", "Analog Stereo", false, "the description without its profile"], [
        {
          "nick": "WH-1000XM4",
          "description": "WH-1000XM4",
          "profile": "High Fidelity Playback (A2DP Sink)",
          "bus": "bluetooth",
          "kind": "bluetooth"
        },
        "WH-1000XM4", "High Fidelity Playback (A2DP Sink)", false, "a headset by its alias"], [
        {},
        "Speakers", "", true, "nothing known"]];
    for (const [device, title, detail, translate, what] of rows) {
      const name = OSDItems.deviceName(device);
      compare([name.title, name.detail, name.translate === true], [title, detail, translate], what);
    }
  }

  function test_besideCard() {
    const vpnDown = {
      "vpn": OSDItems.tile("vpn", {
        "available": true,
        "on": false
      })
    };
    compare(OSDItems.besideCard("vpn", "vpn", 300, vpnDown), "retract", "a drop: the card would say Connected");
    compare(OSDItems.besideCard("vpn", "vpn", 5000, vpnDown), "retract", "a drop later too");
    compare(OSDItems.besideCard("vpn", "capsLock", 300, vpnDown), "show", "unrelated: the card stays");
    compare(OSDItems.besideCard("camera", "camera", 300, {}), "suppress", "a capture stopping as it starts");
    compare(OSDItems.besideCard("microphone", "microphone", 300, {}), "suppress", "the new input's mute coming in");
    compare(OSDItems.besideCard("microphone", "microphone", OSDItems.quietWindow, {}), "show", "the user's own mute later");
    compare(OSDItems.besideCard("message", "capsLock", 300, {}), "show", "a message stays beside the buttons");
  }

  function test_partOrder() {
    compare(OSDItems.partOrder([], "level", false), ["level"]);
    compare(OSDItems.partOrder([], "status", false), ["status"]);
    compare(OSDItems.partOrder(["level"], "card", false), ["level", "card"], "the card always last");
    compare(OSDItems.partOrder(["level"], "status", false), ["level", "status"], "the icons past the bars");
    compare(OSDItems.partOrder(["status"], "level", false), ["level", "status"], "the bars by the edge, the icons moving out");
    compare(OSDItems.partOrder(["status", "card"], "level", false), ["level", "status", "card"], "the bars inside the icons and the card");
    compare(OSDItems.partOrder(["level"], "card", true), ["level", "card"], "holding still: the card past them all");
    compare(OSDItems.partOrder(["status"], "level", true), ["status", "level"], "holding still: the bars after the icons, nothing moving");
    compare(OSDItems.partOrder(["status", "card"], "level", true), ["status", "level", "card"], "holding still: after the box, still inside the card");
    compare(OSDItems.partOrder(["level", "status"], "status", false), ["level", "status"], "already shown");
    compare(OSDItems.partOrder(["status", "level"], "card", false), ["status", "level", "card"], "an order holding still left is kept");
    compare(OSDItems.partOrder(["level"], "status", false, true), ["status", "level"], "icons inside: by the edge, the bars moving out");
    compare(OSDItems.partOrder(["status"], "level", false, true), ["status", "level"], "icons inside: the bars past them");
    compare(OSDItems.partOrder(["level", "card"], "status", true, true), ["level", "status", "card"], "icons inside, holding still: after the bars");
  }

  function test_partsDue() {
    compare(OSDItems.partsDue({}, 1000, 750), {
      "due": [],
      "next": 0
    });
    compare(OSDItems.partsDue({
      "level": 1000,
      "card": 0
    }, 1000, 750), {
      "due": ["level"],
      "next": 0
    });
    compare(OSDItems.partsDue({
      "level": 1000,
      "card": 1500
    }, 1000, 750), {
      "due": [],
      "next": 1500
    }, "held for the card: they close together");
    compare(OSDItems.partsDue({
      "level": 1000,
      "card": 1500
    }, 1500, 750).due.sort(), ["card", "level"]);
    compare(OSDItems.partsDue({
      "level": 1000,
      "card": 3000
    }, 1000, 750), {
      "due": ["level"],
      "next": 3000
    }, "apart: each on its own");
  }

  function test_sharedDeadlines() {
    compare(OSDItems.sharedDeadlines({}), {});
    compare(OSDItems.sharedDeadlines({
      "level": 1000,
      "status": 2500,
      "card": 0
    }), {
      "level": 2500,
      "status": 2500,
      "card": 0
    }, "the bars and the icons share the latest");
    compare(OSDItems.sharedDeadlines({
      "level": 1000,
      "card": 4000
    }), {
      "level": 1000,
      "card": 4000
    }, "a card doesn't hold the bars");
    compare(OSDItems.sharedDeadlines({
      "level": 5000,
      "status": 3000,
      "card": 4000
    }), {
      "level": 5000,
      "status": 5000,
      "card": 4000
    }, "nor do they hold the card");
    compare(OSDItems.sharedDeadlines({
      "level": 0,
      "status": 3000
    }), {
      "level": 0,
      "status": 3000
    }, "a closed part stays closed");
  }
}

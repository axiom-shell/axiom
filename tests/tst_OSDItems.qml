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
    verify(!OSDItems.tile("numLock", {
      "available": true,
      "on": true
    }).notable, "Num Lock on is ordinary");
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

  function test_tile_base_icons() {
    // Off is the base icon unlit (a mute struck through), never an icon's
    // own off form, so every one looks the same
    const types = ["capsLock", "numLock", "scrollLock", "keyboardLayout", "audio", "microphone", "powerProfile", "caffeine", "dnd", "nightLight", "wifi", "bluetooth", "airplane", "charger", "message", "vpn", "recording", "camera", "micUse", "screenShare"];
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
    compare(OSDItems.rowTypes(types, tiles, "notable", ""), ["capsLock"]);
    compare(OSDItems.rowTypes(types, tiles, "notable", "dnd"), ["capsLock", "dnd"], "the change, in its place");
    compare(OSDItems.rowTypes(types, tiles, "all", ""), ["capsLock", "numLock", "dnd"], "not hidden ones, nor a message");
    compare(OSDItems.rowTypes(types, tiles, "all", "message"), ["capsLock", "numLock", "dnd"], "a message is a card, never a tile");
    compare(OSDItems.rowTypes(types, tiles, "changed", "numLock"), ["numLock"]);
    compare(OSDItems.rowTypes(types, tiles, "changed", ""), []);
    compare(OSDItems.rowTypes([], tiles, "all", ""), []);
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
}

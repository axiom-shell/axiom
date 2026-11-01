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
    compare([capsOff.on, capsOff.slash, capsOff.notable], [false, true, false], "off: struck through");
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

    const muted = OSDItems.tile("micMute", {
      "muted": true,
      "icon": ""
    });
    compare([muted.icon, muted.on, muted.slash, muted.notable], ["mic", false, true, true], "the base icon, struck through");
    compare(OSDItems.tile("micMute", {
      "muted": false,
      "icon": "headset_mic"
    }).icon, "headset_mic", "the device's own icon");

    const device = OSDItems.tile("outputDevice", {
      "name": "Speakers",
      "icon": ""
    });
    compare([device.icon, device.caption, device.notable], ["speaker", "Speakers", false]);

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
    compare([dndOff.icon, dndOff.slash], ["do_not_disturb_on", true], "off: the same icon, struck through");
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
    compare([message.icon, message.caption, message.hidden], ["chat", "Saved", false]);
    verify(OSDItems.tile("message", {}).hidden, "none yet");
    verify(OSDItems.tile("bogus", {}).hidden);
  }

  function test_tile_base_icons() {
    // An off state is a slash over the base icon, never an icon's own off
    // form, so every one looks the same
    const types = ["capsLock", "numLock", "scrollLock", "keyboardLayout", "micMute", "outputDevice", "powerProfile", "caffeine", "dnd", "nightLight", "wifi", "bluetooth", "airplane", "charger", "message"];
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
          "text": "x"
        });
        verify(!/_(off|disabled|inactive)$/.test(t.icon), `${type} ${on}: ${t.icon}`);
      }
    }
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
    compare(OSDItems.rowTypes(types, tiles, "all", "message"), ["capsLock", "numLock", "dnd", "message"]);
    compare(OSDItems.rowTypes(types, tiles, "changed", "numLock"), ["numLock"]);
    compare(OSDItems.rowTypes(types, tiles, "changed", ""), []);
    compare(OSDItems.rowTypes([], tiles, "all", ""), []);
  }

  function test_replaces() {
    verify(OSDItems.replaces("", "wifi", 0));
    verify(OSDItems.replaces("capsLock", "wifi", 0));
    verify(!OSDItems.replaces("airplane", "wifi", 300), "airplane mode switching the radio");
    verify(!OSDItems.replaces("airplane", "bluetooth", 1999));
    verify(OSDItems.replaces("airplane", "bluetooth", OSDItems.radioQuiet), "the user's own toggle later");
    verify(OSDItems.replaces("wifi", "airplane", 0), "airplane mode always shows");
    verify(OSDItems.replaces("airplane", "capsLock", 0));
  }
}

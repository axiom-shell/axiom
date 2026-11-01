import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "OSDItems"

  function test_shapeOf() {
    compare(OSDItems.shapeOf("master"), "level");
    compare(OSDItems.shapeOf("brightness"), "level");
    compare(OSDItems.shapeOf("lockKeys"), "status");
    compare(OSDItems.shapeOf("message"), "status");
    compare(OSDItems.shapeOf("media"), "media");
    compare(OSDItems.shapeOf(""), "", "no item (a delegate past the end)");
    compare(OSDItems.shapeOf("bogus"), "");
  }

  function test_ofShape() {
    const items = [
      {
        "type": "master"
      },
      {
        "type": "lockKeys"
      },
      {
        "type": "app"
      },
      {
        "type": "media"
      }
    ];
    compare(OSDItems.ofShape(items, "level").map(e => e.index), [0, 2], "keeps each item's place");
    compare(OSDItems.ofShape(items, "status").map(e => e.item.type), ["lockKeys"]);
    compare(OSDItems.ofShape(items, "media").length, 1);
    compare(OSDItems.ofShape([], "level"), []);
  }

  function test_lockKeyChange() {
    const off = {
      "available": true,
      "caps": false,
      "num": true,
      "scroll": false
    };
    const capsOn = Object.assign({}, off, {
      "caps": true
    });
    const item = {
      "caps": true,
      "num": true,
      "scroll": false
    };
    compare(OSDItems.lockKeyChange(off, capsOn, item), {
      "key": "caps",
      "on": true
    });
    compare(OSDItems.lockKeyChange(capsOn, off, item), {
      "key": "caps",
      "on": false
    });
    compare(OSDItems.lockKeyChange(off, Object.assign({}, off, {
      "num": false
    }), item), {
      "key": "num",
      "on": false
    });
    compare(OSDItems.lockKeyChange(off, Object.assign({}, off, {
      "scroll": true
    }), item), null, "a key the item doesn't show");
    compare(OSDItems.lockKeyChange(off, off, item), null, "nothing changed");
    compare(OSDItems.lockKeyChange(Object.assign({}, off, {
      "available": false,
      "num": false
    }), capsOn, item), null, "the first reading is not the user");
    compare(OSDItems.lockKeyChange(capsOn, {
      "available": false,
      "caps": false,
      "num": false,
      "scroll": false
    }, item), null, "the LEDs going away is not the user");
    compare(OSDItems.lockKeyChange(null, capsOn, item), null);
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

  function test_status() {
    compare(OSDItems.status("lockKeys", {
      "key": "caps",
      "on": true
    }), {
      "icon": "keyboard_capslock",
      "text": "Caps Lock on"
    });
    compare(OSDItems.status("lockKeys", {
      "key": "num",
      "on": false
    }).text, "Num Lock off");
    compare(OSDItems.status("keyboardLayout", {
      "name": "English (US)"
    }), {
      "icon": "keyboard",
      "value": "English (US)"
    }, "a name is shown as it is");
    compare(OSDItems.status("micMute", {
      "muted": true
    }), {
      "icon": "mic_off",
      "text": "Microphone off"
    });
    compare(OSDItems.status("powerProfile", {
      "profile": "performance"
    }).text, "Performance");
    compare(OSDItems.status("powerProfile", {
      "profile": "unknown"
    }).text, "Balanced", "an unknown profile reads as balanced");
    compare(OSDItems.status("charger", {
      "plugged": false
    }).text, "On battery");
    compare(OSDItems.status("wifi", {
      "on": false
    }), {
      "icon": "wifi_off",
      "text": "Wi-Fi off"
    });
    compare(OSDItems.status("caffeine", {
      "on": true
    }).text, "Caffeine on");
    compare(OSDItems.status("message", {
      "icon": "rocket",
      "text": "Deployed"
    }), {
      "icon": "rocket",
      "value": "Deployed"
    });
    compare(OSDItems.status("master", {}), {
      "icon": "",
      "text": ""
    }, "not a status");
  }

  function test_replaces() {
    verify(OSDItems.replaces("", "wifi", 0));
    verify(OSDItems.replaces("lockKeys", "wifi", 0));
    verify(!OSDItems.replaces("airplane", "wifi", 300), "airplane mode switching the radio");
    verify(!OSDItems.replaces("airplane", "bluetooth", 1999));
    verify(OSDItems.replaces("airplane", "bluetooth", OSDItems.radioQuiet), "the user's own toggle later");
    verify(OSDItems.replaces("wifi", "airplane", 0), "airplane mode always shows");
    verify(OSDItems.replaces("airplane", "lockKeys", 0));
  }
}

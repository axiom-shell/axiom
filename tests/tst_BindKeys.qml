import QtQuick
import QtTest
import qs.components.methods

TestCase {
  id: test
  name: "BindKeys"

  // Records the helpers' calls as shared fixtures for the axiom binary
  Shared {
    id: shared
    testCase: test
  }

  // hyprctl binds -j entries, trimmed to what BindKeys reads
  function entry(modmask, key, extra) {
    return Object.assign({
      "modmask": modmask,
      "key": key,
      "keycode": 0,
      "submap": ""
    }, extra ?? {});
  }

  function test_keyId() {
    compare(shared.calls.BindKeys.keyId("SUPER + SHIFT + Space"), "65:space");
    compare(shared.calls.BindKeys.keyId("mod4+control+Q"), "68:q");
    compare(shared.calls.BindKeys.keyId("F12"), "0:f12");
    compare(shared.calls.BindKeys.keyId(" SUPER + code:10 "), "64:code:10");
    compare(shared.calls.BindKeys.keyId("HYPER + A"), "", "unknown modifier");
    compare(shared.calls.BindKeys.keyId(""), "");
    compare(shared.calls.BindKeys.keyId(undefined), "");
  }

  function test_decodeMods() {
    compare(BindKeys.decodeMods(65), ["SUPER", "SHIFT"]);
    compare(BindKeys.decodeMods(4 | 8 | 2 | 128), ["CTRL", "ALT", "MOD5", "CAPS"], "in modifierNames' order");
    compare(BindKeys.decodeMods(0), []);
    for (const name of BindKeys.modifierNames)
      compare(BindKeys.decodeMods(BindKeys._modBits[name]), [name], "each name its own bit");
  }

  function test_entryId_matches_keyId() {
    compare(shared.calls.BindKeys.entryId(entry(65, "Space")), shared.calls.BindKeys.keyId("SUPER + SHIFT + space"));
    compare(shared.calls.BindKeys.entryId(entry(64, "", {
      "keycode": 10
    })), shared.calls.BindKeys.keyId("SUPER + code:10"));
  }

  function test_tapIds() {
    // Hyprland lists a tap with its modifier held, sway without
    compare(shared.calls.BindKeys.keyId("Super_L"), "0:super_l");
    compare(shared.calls.BindKeys.keyId("SUPER + Super_L"), "0:super_l");
    compare(shared.calls.BindKeys.entryId(entry(64, "SUPER_L")), "0:super_l");
    compare(shared.calls.BindKeys.entryId(entry(0, "Super_L")), "0:super_l");
    compare(shared.calls.BindKeys.keyId("CTRL + Super_L"), "4:super_l", "not a tap");
  }

  function test_userKeyCounts_less_axioms_own() {
    const entries = [entry(64, "a"), entry(64, "a"), entry(64, "b"), entry(64, "c", {
        "submap": "resize"
      })];
    const counts = shared.calls.BindKeys.userKeyCounts(entries, [
      {
        "key": "SUPER + A"
      },
      {
        "key": "SUPER + B"
      },
      {
        "key": "SUPER + Z"
      }
    ]);
    compare(counts["64:a"], 1);
    compare(counts["64:b"], 0);
    compare(counts["64:c"], undefined);
    compare(counts["64:z"], undefined);
  }

  function test_mergeBinds_one_bind_per_key() {
    const axiom = [
      {
        "key": "SUPER + Q",
        "action": "overlay"
      },
      {
        "key": "",
        "action": "lock"
      },
      {
        "key": "SUPER + E",
        "action": "fileManager"
      }
    ];
    const user = [
      {
        "key": "super+q",
        "action": "exec",
        "argument": "kitty"
      },
      {
        "key": "SUPER + R",
        "action": "exec",
        "argument": "a"
      },
      {
        "key": "SUPER + R",
        "action": "exec",
        "argument": "b"
      },
      {
        "key": "",
        "action": "pin"
      }
    ];
    const merged = shared.calls.BindKeys.mergeBinds(axiom, user);
    compare(merged.map(bind => bind.action), ["exec", "lock", "fileManager", "exec", "pin"]);
    compare(merged[0].argument, "kitty");
    compare(merged[3].argument, "b");
    // The inputs are left as they were
    compare(axiom[0].action, "overlay");
    compare(shared.calls.BindKeys.mergeBinds(axiom, []), axiom);
  }

  // A paused bind holds no key: the user's replaces the active one on it
  function test_mergeBinds_skips_paused() {
    const axiom = [
      {
        "key": "SUPER + W",
        "action": "focusDir",
        "argument": "up",
        "paused": true
      },
      {
        "key": "SUPER + W",
        "action": "workspaceStep",
        "argument": "up"
      },
      {
        "key": "SUPER + S",
        "action": "focusDir",
        "argument": "down",
        "paused": true
      }
    ];
    const user = [
      {
        "key": "SUPER + W",
        "action": "exec",
        "argument": "a"
      },
      {
        "key": "SUPER + S",
        "action": "exec",
        "argument": "b"
      }
    ];
    const merged = shared.calls.BindKeys.mergeBinds(axiom, user);
    compare(merged.map(bind => bind.action), ["focusDir", "exec", "focusDir", "exec"]);
    compare(merged[0].paused, true);
    compare(merged[2].paused, true);
  }

  // Shared with the binary's merge (manager.withIDs)
  function test_withIds() {
    const kept = {
      "id": "super-y",
      "key": "SUPER + Y"
    };
    const binds = shared.calls.BindKeys.withIds([kept,
      {
        "id": "super-y",
        "key": "SUPER + Y",
        "action": "exec"
      },
      {
        "key": "SUPER + SHIFT + space"
      },
      {
        "id": "-bad",
        "key": "Print"
      },
      {
        "key": ""
      },
      {
        "action": "exec"
      }
    ]);
    compare(binds.map(bind => bind.id), ["super-y", "super-y-2", "super-shift-space", "print", "bind", "bind-2"]);
    verify(binds[0] === kept, "a bind keeping its id is the same object");
    compare(Object.keys(binds[1])[0], "id", "the id first");
    compare(binds[1].action, "exec");
    compare(BindKeys.withIds(undefined), []);
  }
}

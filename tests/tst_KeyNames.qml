import QtQuick
import QtTest
import qs.components.methods

TestCase {
  id: test
  name: "KeyNames"

  // Records the helpers' calls as shared fixtures for the axiom binary
  Shared {
    id: shared
    testCase: test
  }

  function test_modifier_label() {
    compare(shared.calls.KeyNames.modifierLabel("SUPER"), "Super");
    compare(shared.calls.KeyNames.modifierLabel("CTRL"), "Ctrl");
    compare(shared.calls.KeyNames.modifierLabel("MOD3"), "Mod3");
  }

  function test_modifier_glyph() {
    compare(shared.calls.KeyNames.modifierGlyph("SHIFT"), "⇧");
    compare(shared.calls.KeyNames.modifierGlyph("CTRL"), "⌃");
    compare(shared.calls.KeyNames.modifierGlyph("SUPER"), "", "drawn as an icon");
    compare(shared.calls.KeyNames.modifierGlyph("MOD3"), "");
  }

  function test_key_name() {
    compare(shared.calls.KeyNames.keyName(Qt.Key_A, 0), "A");
    compare(shared.calls.KeyNames.keyName(Qt.Key_5, 0), "5");
    compare(shared.calls.KeyNames.keyName(Qt.Key_F12, 0), "F12");
    compare(shared.calls.KeyNames.keyName(Qt.Key_Space, 0), "space");
    compare(shared.calls.KeyNames.keyName(Qt.Key_Enter, 0), "Return");
    compare(shared.calls.KeyNames.keyName(Qt.Key_Shift, 50), "");
    compare(shared.calls.KeyNames.keyName(0x01ffffff, 191), "code:191");
    compare(shared.calls.KeyNames.keyName(0x01ffffff, 0), "");
  }

  function test_from_event_orders_modifiers() {
    compare(shared.calls.KeyNames.fromEvent(Qt.Key_Q, Qt.ShiftModifier | Qt.MetaModifier | Qt.ControlModifier, 0), "SUPER + CTRL + SHIFT + Q");
    compare(shared.calls.KeyNames.fromEvent(Qt.Key_Control, Qt.ControlModifier, 0), "");
  }

  function test_modifier_for() {
    compare(shared.calls.KeyNames.modifierFor(Qt.Key_Super_L), "SUPER");
    compare(shared.calls.KeyNames.modifierFor(Qt.Key_Alt), "ALT");
    compare(shared.calls.KeyNames.modifierFor(Qt.Key_A), "");
  }

  function test_split_normalises_aliases() {
    const parts = shared.calls.KeyNames.split(" mod4 + control+ Mod1 +space ");
    compare(parts.mods, ["SUPER", "CTRL", "ALT"]);
    compare(parts.key, "space");
    compare(shared.calls.KeyNames.split("").key, "");
    compare(shared.calls.KeyNames.split(null).mods, []);
  }

  function test_join_round_trips() {
    const combo = "SUPER + SHIFT + Return";
    const parts = shared.calls.KeyNames.split(combo);
    compare(shared.calls.KeyNames.join(parts.mods, parts.key), combo);
  }

  function test_from_wheel() {
    compare(shared.calls.KeyNames.fromWheel(0, -120, Qt.MetaModifier, []), "SUPER + mouse_down");
    compare(shared.calls.KeyNames.fromWheel(0, 120, Qt.NoModifier, ["SUPER"]), "SUPER + mouse_up");
    compare(shared.calls.KeyNames.fromWheel(120, 0, Qt.ShiftModifier | Qt.MetaModifier, []), "SUPER + SHIFT + mouse_left");
    compare(shared.calls.KeyNames.fromWheel(0, 0, Qt.MetaModifier, []), "");
  }

  function test_tap_modifier() {
    compare(shared.calls.KeyNames.tapModifier("Super_L"), "SUPER");
    compare(shared.calls.KeyNames.tapModifier("SUPER + SUPER_R"), "SUPER", "written with its own modifier");
    compare(shared.calls.KeyNames.tapModifier("control_r"), "CTRL");
    compare(shared.calls.KeyNames.tapModifier("CTRL + Super_L"), "", "held with another modifier");
    compare(shared.calls.KeyNames.tapModifier("SUPER + Q"), "");
    compare(shared.calls.KeyNames.tapModifier(""), "");
  }

  function test_tap_name() {
    compare(shared.calls.KeyNames.tapName(Qt.Key_Super_L, 133), "Super_L");
    compare(shared.calls.KeyNames.tapName(Qt.Key_Super_R, 134), "Super_R");
    compare(shared.calls.KeyNames.tapName(Qt.Key_Control, 105), "Control_R", "the keycode tells the side");
    compare(shared.calls.KeyNames.tapName(Qt.Key_Alt, 0), "Alt_L", "no keycode: the left one");
    compare(shared.calls.KeyNames.tapName(Qt.Key_Shift, 133), "Shift_L", "a keycode of another modifier is ignored");
    compare(shared.calls.KeyNames.tapName(Qt.Key_A, 38), "");
  }
}

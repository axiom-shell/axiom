pragma Singleton
import QtQuick

// Keys as Hyprland writes them ("SUPER + SHIFT + space"): turning a Qt key
// event into one (for recording a bind), and splitting one for display.
QtObject {
  id: root

  // Modifier names, in the order a combo is written
  readonly property var modifiers: ["SUPER", "CTRL", "ALT", "SHIFT"]

  // A modifier as a keycap shows it ("SUPER" -> "Super", "MOD3" -> "Mod3")
  function modifierLabel(name) {
    return root._modifierLabels[name] ?? name.charAt(0) + name.slice(1).toLowerCase();
  }
  readonly property var _modifierLabels: ({
      "SUPER": "Super",
      "CTRL": "Ctrl",
      "ALT": "Alt",
      "SHIFT": "Shift",
      "CAPS": "Caps"
    })

  // A modifier as a glyph ("SHIFT" -> "⇧"), or "" for one drawn another way
  // (SUPER, as an icon) or with no glyph
  function modifierGlyph(name) {
    return root._modifierGlyphs[name] ?? "";
  }
  readonly property var _modifierGlyphs: ({
      "CTRL": "⌃",
      "ALT": "⌥",
      "SHIFT": "⇧",
      "CAPS": "⇪"
    })

  // Other spellings Hyprland accepts, by the name used here
  readonly property var _aliases: ({
      "WIN": "SUPER",
      "LOGO": "SUPER",
      "MOD4": "SUPER",
      "META": "SUPER",
      "CONTROL": "CTRL",
      "MOD1": "ALT"
    })

  readonly property var _modifierKeys: [Qt.Key_Shift, Qt.Key_Control, Qt.Key_Alt, Qt.Key_AltGr, Qt.Key_Meta, Qt.Key_Super_L, Qt.Key_Super_R, Qt.Key_Hyper_L, Qt.Key_Hyper_R, Qt.Key_CapsLock, Qt.Key_NumLock]

  // Qt keys whose keysym name isn't just the letter or digit. Shifted
  // symbols go back to their unshifted key (US layout), since Hyprland
  // matches SHIFT + 1, not SHIFT + exclam.
  readonly property var _names: ({
      [Qt.Key_Space]: "space",
      [Qt.Key_Return]: "Return",
      [Qt.Key_Enter]: "Return",
      [Qt.Key_Tab]: "Tab",
      [Qt.Key_Backtab]: "Tab",
      [Qt.Key_Escape]: "Escape",
      [Qt.Key_Backspace]: "BackSpace",
      [Qt.Key_Delete]: "Delete",
      [Qt.Key_Insert]: "Insert",
      [Qt.Key_Home]: "Home",
      [Qt.Key_End]: "End",
      [Qt.Key_PageUp]: "Page_Up",
      [Qt.Key_PageDown]: "Page_Down",
      [Qt.Key_Left]: "Left",
      [Qt.Key_Right]: "Right",
      [Qt.Key_Up]: "Up",
      [Qt.Key_Down]: "Down",
      [Qt.Key_Print]: "Print",
      [Qt.Key_Pause]: "Pause",
      [Qt.Key_ScrollLock]: "Scroll_Lock",
      [Qt.Key_Menu]: "Menu",
      [Qt.Key_Minus]: "minus",
      [Qt.Key_Underscore]: "minus",
      [Qt.Key_Equal]: "equal",
      [Qt.Key_Plus]: "equal",
      [Qt.Key_BracketLeft]: "bracketleft",
      [Qt.Key_BraceLeft]: "bracketleft",
      [Qt.Key_BracketRight]: "bracketright",
      [Qt.Key_BraceRight]: "bracketright",
      [Qt.Key_Backslash]: "backslash",
      [Qt.Key_Bar]: "backslash",
      [Qt.Key_Semicolon]: "semicolon",
      [Qt.Key_Colon]: "semicolon",
      [Qt.Key_Apostrophe]: "apostrophe",
      [Qt.Key_QuoteDbl]: "apostrophe",
      [Qt.Key_Comma]: "comma",
      [Qt.Key_Less]: "comma",
      [Qt.Key_Period]: "period",
      [Qt.Key_Greater]: "period",
      [Qt.Key_Slash]: "slash",
      [Qt.Key_Question]: "slash",
      [Qt.Key_QuoteLeft]: "grave",
      [Qt.Key_AsciiTilde]: "grave",
      [Qt.Key_Exclam]: "1",
      [Qt.Key_At]: "2",
      [Qt.Key_NumberSign]: "3",
      [Qt.Key_Dollar]: "4",
      [Qt.Key_Percent]: "5",
      [Qt.Key_AsciiCircum]: "6",
      [Qt.Key_Ampersand]: "7",
      [Qt.Key_Asterisk]: "8",
      [Qt.Key_ParenLeft]: "9",
      [Qt.Key_ParenRight]: "0",
      [Qt.Key_VolumeUp]: "XF86AudioRaiseVolume",
      [Qt.Key_VolumeDown]: "XF86AudioLowerVolume",
      [Qt.Key_VolumeMute]: "XF86AudioMute",
      [Qt.Key_MicMute]: "XF86AudioMicMute",
      [Qt.Key_MediaPlay]: "XF86AudioPlay",
      [Qt.Key_MediaTogglePlayPause]: "XF86AudioPlay",
      [Qt.Key_MediaPause]: "XF86AudioPause",
      [Qt.Key_MediaStop]: "XF86AudioStop",
      [Qt.Key_MediaNext]: "XF86AudioNext",
      [Qt.Key_MediaPrevious]: "XF86AudioPrev",
      [Qt.Key_MonBrightnessUp]: "XF86MonBrightnessUp",
      [Qt.Key_MonBrightnessDown]: "XF86MonBrightnessDown",
      [Qt.Key_Calculator]: "XF86Calculator"
    })

  function isModifierKey(key) {
    return _modifierKeys.includes(key);
  }

  // The modifiers held in a Qt event's `modifiers`, in combo order
  function modifiersOf(qtModifiers) {
    const held = [];
    if (qtModifiers & Qt.MetaModifier)
      held.push("SUPER");
    if (qtModifiers & Qt.ControlModifier)
      held.push("CTRL");
    if (qtModifiers & Qt.AltModifier)
      held.push("ALT");
    if (qtModifiers & Qt.ShiftModifier)
      held.push("SHIFT");
    return held;
  }

  // The modifier a modifier key is, or "" (its own press may not be in
  // the event's `modifiers` yet)
  function modifierFor(key) {
    switch (key) {
    case Qt.Key_Meta:
    case Qt.Key_Super_L:
    case Qt.Key_Super_R:
      return "SUPER";
    case Qt.Key_Control:
      return "CTRL";
    case Qt.Key_Alt:
      return "ALT";
    case Qt.Key_Shift:
      return "SHIFT";
    }
    return "";
  }

  // The key's name, "code:N" (xkb keycode) for one with no name here, or
  // "" for a modifier on its own
  function keyName(key, scanCode) {
    if (isModifierKey(key))
      return "";
    if (_names[key] !== undefined)
      return _names[key];
    if (key >= Qt.Key_A && key <= Qt.Key_Z)
      return String.fromCharCode(key);
    if (key >= Qt.Key_0 && key <= Qt.Key_9)
      return String.fromCharCode(key);
    if (key >= Qt.Key_F1 && key <= Qt.Key_F35)
      return "F" + (key - Qt.Key_F1 + 1);
    return scanCode > 0 ? "code:" + scanCode : "";
  }

  // Modifier keys a bind can be on by themselves (a tap: pressed and let
  // go with no other key between), by keysym, as the modifier each is
  readonly property var _tapKeys: ({
      "super_l": "SUPER",
      "super_r": "SUPER",
      "control_l": "CTRL",
      "control_r": "CTRL",
      "alt_l": "ALT",
      "alt_r": "ALT",
      "shift_l": "SHIFT",
      "shift_r": "SHIFT"
    })

  // The modifier keys by xkb keycode, which tells left from right
  readonly property var _tapCodes: ({
      "133": "Super_L",
      "134": "Super_R",
      "37": "Control_L",
      "105": "Control_R",
      "64": "Alt_L",
      "108": "Alt_R",
      "50": "Shift_L",
      "62": "Shift_R"
    })

  // The modifier a combo taps ("Super_L" -> "SUPER"), or "" when it isn't
  // a tap. Its own modifier may be written too ("SUPER + Super_L"), as the
  // compositor holds it when the key is let go.
  function tapModifier(combo) {
    const parts = split(combo);
    const mod = _tapKeys[parts.key.toLowerCase()] ?? "";
    return parts.mods.every(held => held === mod) ? mod : "";
  }

  // A modifier key from a key event as a tap combo ("Super_L"), or ""
  function tapName(key, scanCode) {
    const own = modifierFor(key);
    const named = _tapCodes[String(scanCode)];
    if (named !== undefined && _tapKeys[named.toLowerCase()] === own)
      return named;
    return {
      "SUPER": "Super_L",
      "CTRL": "Control_L",
      "ALT": "Alt_L",
      "SHIFT": "Shift_L"
    }[own] ?? "";
  }

  // A full combo from a key event, or "" while only modifiers are down
  function fromEvent(key, qtModifiers, scanCode) {
    const name = keyName(key, scanCode);
    return name === "" ? "" : join(modifiersOf(qtModifiers), name);
  }

  // A combo from a wheel turn (a WheelEvent's angleDelta and modifiers):
  // Hyprland's mouse_up/mouse_down (mouse_left/mouse_right sideways), or
  // "" for no turn. `held` adds modifiers seen as key presses.
  function fromWheel(dx, dy, qtModifiers, held) {
    const key = dy > 0 ? "mouse_up" : dy < 0 ? "mouse_down" : dx > 0 ? "mouse_left" : dx < 0 ? "mouse_right" : "";
    if (key === "")
      return "";
    const mods = modifiersOf(qtModifiers);
    return join(modifiers.filter(mod => mods.includes(mod) || (held ?? []).includes(mod)), key);
  }

  function join(mods, key) {
    return mods.concat([key]).join(" + ");
  }

  // "SUPER + SHIFT + space" -> { mods: ["SUPER", "SHIFT"], key: "space" },
  // modifiers under the names above
  function split(combo) {
    const parts = String(combo ?? "").split("+").map(part => part.trim()).filter(part => part !== "");
    if (parts.length === 0)
      return {
        "mods": [],
        "key": ""
      };
    return {
      "mods": parts.slice(0, -1).map(mod => _aliases[mod.toUpperCase()] ?? mod.toUpperCase()),
      "key": parts[parts.length - 1]
    };
  }
}

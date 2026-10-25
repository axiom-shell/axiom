pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

import qs.config
import qs.services.compositor
import qs.components.methods

// The window switcher's keys where the compositor can't report their
// release (no supports.switcherRelease: sway fires a release bind only when
// no other key came between). While the switcher is open this invisible
// pixel takes the keyboard, so letting go of the modifier a switcher bind
// is held by picks the window, Escape cancels and Return picks; the
// switcher binds themselves still reach the compositor, which runs binds
// before the focused surface.
PanelWindow {
  id: root

  visible: WindowSwitcherManager.active
  anchors {
    left: true
    top: true
  }
  implicitWidth: 1
  implicitHeight: 1
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"
  mask: Region {}
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "axiom-switcher-keys"
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

  // The modifiers the switcher binds are held by (BindActions.switcherHeld),
  // as Qt's keys and modifier flags
  readonly property var _qtKeys: ({
      "SUPER": [Qt.Key_Meta, Qt.Key_Super_L, Qt.Key_Super_R],
      "ALT": [Qt.Key_Alt],
      "CTRL": [Qt.Key_Control],
      "SHIFT": [Qt.Key_Shift]
    })
  readonly property var _qtFlags: ({
      "SUPER": Qt.MetaModifier,
      "ALT": Qt.AltModifier,
      "CTRL": Qt.ControlModifier,
      "SHIFT": Qt.ShiftModifier
    })
  readonly property var _held: {
    const held = [].concat(...KeybindsConfig.activeBinds.filter(bind => BindActions.switcherSteps[bind.action] !== undefined).map(bind => BindActions.switcherHeld(KeyNames.split(bind.key).mods)));
    return held.length > 0 ? held.filter((mod, i) => held.indexOf(mod) === i) : ["SUPER", "ALT", "CTRL"];
  }
  readonly property var _heldKeys: [].concat(..._held.map(mod => _qtKeys[mod] ?? []))
  readonly property int _heldFlags: _held.reduce((flags, mod) => flags | (_qtFlags[mod] ?? 0), 0)

  Item {
    anchors.fill: parent
    focus: true

    Keys.onReleased: event => {
      if (root._heldKeys.includes(event.key))
        WindowSwitcherManager.commit();
    }
    Keys.onPressed: event => {
      if (event.key === Qt.Key_Escape)
        WindowSwitcherManager.cancel();
      else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
        WindowSwitcherManager.commit();
      else
      // A key with no switcher modifier held: it was let go before this
      // had the keyboard (a very quick tap), so the release was missed
      if (!root._heldKeys.includes(event.key) && (event.modifiers & root._heldFlags) === 0)
        WindowSwitcherManager.commit();
    }
  }
}

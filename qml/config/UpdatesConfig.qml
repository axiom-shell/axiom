pragma Singleton
import QtQuick
import qs.services.core

// Reader for the Updates section: how every updates widget and module
// checks for and installs updates (see UpdatesManager).
QtObject {
  id: root

  readonly property var _c: ConfigManager.live.Updates

  readonly property bool includeAur: _c.includeAur
  // "paru" | "yay"
  readonly property string aurHelper: _c.aurHelper
  // The helper to check the AUR with, "" for none
  readonly property string activeAurHelper: includeAur ? aurHelper : ""
  readonly property string terminal: _c.terminal
  readonly property string upgradeCommand: _c.upgradeCommand
}

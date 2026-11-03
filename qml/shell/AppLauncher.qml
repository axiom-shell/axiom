pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.components.surfaces.launcher
import qs.config

// The app launcher, one per screen its monitors setting picks
// (surfaces/launcher/Launcher).
Scope {
  Variants {
    model: General.screensFor(LauncherConfig.screen)
    delegate: Launcher {
      required property ShellScreen modelData
      screen: modelData
    }
  }
}

pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.config
import qs.services.session
import qs.components.surfaces.greeter

// The greeter (greeter.qml, greetd's login screen): a GreeterWindow per
// screen, and GreetdManager behind the login box. With
// AXIOM_GREETER_WINDOWED=1 it's one ordinary window instead, to look at
// it from a running session without taking over the screens.
Scope {
  id: root

  readonly property bool windowed: Quickshell.env("AXIOM_GREETER_WINDOWED") === "1"
  // Created up front: it reads the users and sessions and sets up the
  // greeter's Hyprland before anyone types
  readonly property var _services: [GreetdManager]

  Variants {
    model: root.windowed ? [] : General.outputs

    delegate: GreeterWindow {
      required property ShellScreen modelData
      screen: modelData
    }
  }

  LazyLoader {
    active: root.windowed

    FloatingWindow {
      id: window
      implicitWidth: 1280 // fixed px: the windowed test size, a screen stand-in
      implicitHeight: 720 // fixed px: the windowed test size, a screen stand-in
      color: Theme.background
      title: "axiom greeter"

      GreeterSurface {
        // Quickshell's list, not General.outputs: the window must exist
        // even with no monitor connected (a stand-in screen then)
        screen: Quickshell.screens[0]
      }
    }
  }
}

pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.services.session
import qs.components.surfaces.greeter

// The layouts editor's preview of the login screen (GreeterManager.editor's
// Show on screen), on the screen it started on. Built only while shown.
Scope {
  LazyLoader {
    active: GreeterManager.editor.previewing && !LockManager.builtinLocked

    GreeterPreviewWindow {
      // Quickshell's list, not General.outputs: there's always a screen to
      // put it on, a stand-in one while no monitor is connected
      screen: Quickshell.screens.find(screen => screen.name === GreeterManager.editor.previewScreen) ?? Quickshell.screens[0]
    }
  }
}
